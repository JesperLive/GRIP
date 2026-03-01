# Claude Code Prompt — Guild Name/Link Resolution Fix + Debug Copy Frame

> Copy-paste this entire prompt into Claude Code.

---

## Context

GRIP is a WoW guild recruitment addon (v0.4.0, Interface 120001). Two bugs have been identified:

1. `{guild}` and `{guildlink}` template tokens resolve to empty/fallback text — the Settings "Preview" button shows no guild name.
2. Debug window produces error spam from repeated failed `GetGuildFinderLink()` calls.
3. Users can't copy/paste from the WoW debug chat window — need a copyable frame.

**Before starting, read:** `Claude/Research_09_GuildName_GuildLink_Fix.md` for the full root cause analysis.

## Task Overview

You will:
1. Fix `GetGuildName()` in Core/Utils.lua — remove dead API path, improve cache logic
2. Fix `GetGuildFinderLink()` in Core/Utils.lua — add cache with expiry, suppress spam
3. Add guild data event handlers in Core/Events.lua — warm caches proactively
4. Add `/grip debug copy` command — copyable debug frame
5. Add `ShowDebugCopyFrame()` function

**Rules:**
- Do NOT change the recruitment pipeline (Who/Whisper/Invite/Post).
- Do NOT change the blacklist system.
- Do NOT change UI pages (UI_Home, UI_Settings, UI_Ads).
- Preserve the existing fallback chain in ApplyTemplate (guild name → "your guild").
- Every file must parse as valid Lua.
- Follow the 2-line header standard for any new files.

---

## Task 1: Fix `GetGuildName()` in Core/Utils.lua

### 1a. Remove the dead `C_GuildInfo.GetGuildInfo` code path

In `GetGuildName()`, remove the entire block that tries `C_GuildInfo.GetGuildInfo`:

```lua
-- REMOVE THIS BLOCK (approximately lines 95-100):
if C_GuildInfo and C_GuildInfo.GetGuildInfo then
    local ok, info = pcall(C_GuildInfo.GetGuildInfo, "player")
    if ok and type(info) == "table" and type(info.guildName) == "string" then
        name = info.guildName
    end
end
```

**Why:** `C_GuildInfo.GetGuildInfo` is not a real WoW API function. The `C_GuildInfo` namespace does not contain `GetGuildInfo`. This code never executes.

### 1b. Fix the cache logic to not poison with empty string

The current code clears the cache when `IsInGuild()` returns false, but it also overwrites the cache with "" when `GetGuildInfo("player")` returns nil (which happens during early login even when in a guild).

Replace the entire `GetGuildName()` function with:

```lua
function GRIP:GetGuildName()
  state._gripLastGuildName = state._gripLastGuildName or ""

  -- If the client explicitly says we're not in a guild, clear cache.
  if IsInGuild and not IsInGuild() then
    state._gripLastGuildName = ""
    return ""
  end

  -- Primary API: GetGuildInfo("player") returns (guildName, rankName, rankIndex, realm).
  -- Returns nil during early login before PLAYER_GUILD_UPDATE fires.
  if GetGuildInfo then
    local g = GetGuildInfo("player")
    if type(g) == "string" and g ~= "" then
      state._gripLastGuildName = g
      return g
    end
  end

  -- During early login, GetGuildInfo returns nil even when in a guild.
  -- Return cached value if we have one; don't overwrite cache with "".
  if state._gripLastGuildName ~= "" then
    return state._gripLastGuildName
  end

  return ""
end
```

Key changes:
- Removed dead `C_GuildInfo.GetGuildInfo` path
- Only clear cache when `IsInGuild()` explicitly returns false
- When `GetGuildInfo` returns nil, preserve existing cache (don't poison it)

---

## Task 2: Fix `GetGuildFinderLink()` in Core/Utils.lua

### 2a. Add a cache with timestamp-based expiry

Add a cache mechanism so we don't call the full pipeline on every template expansion. Use `GRIP.state` for the cache:

Before `GetGuildFinderLink()`, add a helper:

```lua
local GUILD_LINK_CACHE_SUCCESS_TTL = 300  -- 5 minutes on success
local GUILD_LINK_CACHE_FAIL_TTL = 30      -- 30 seconds on failure

local function GetCachedGuildLink()
  local cache = state._gripGuildLinkCache
  if not cache then return nil, false end

  local age = GetTime() - (cache.at or 0)
  local ttl = cache.ok and GUILD_LINK_CACHE_SUCCESS_TTL or GUILD_LINK_CACHE_FAIL_TTL

  if age < ttl then
    return cache.link, true  -- link (may be ""), isCached
  end

  return nil, false  -- expired
end

local function SetGuildLinkCache(link, ok)
  state._gripGuildLinkCache = {
    link = link or "",
    at = GetTime(),
    ok = ok and true or false,
  }
end
```

### 2b. Modify `GetGuildFinderLink()` to use the cache and suppress spam

Replace the function with a version that:
1. Checks cache first
2. Only logs failures once per cache cycle (not on every call)
3. Stores result in cache

```lua
function GRIP:GetGuildFinderLink()
  -- Check cache first
  local cached, isCached = GetCachedGuildLink()
  if isCached then
    return cached
  end

  if not C_Club or not C_Club.GetGuildClubId then
    if self:IsDebugEnabled(3) and not state._gripGuildLinkLoggedFailure then
      self:Trace("GetGuildFinderLink: missing C_Club.GetGuildClubId")
      state._gripGuildLinkLoggedFailure = true
    end
    SetGuildLinkCache("", false)
    return ""
  end

  -- These globals may not exist until Blizzard_ClubFinder is loaded.
  if not ClubFinderGetCurrentClubListingInfo or not GetClubFinderLink then
    self:_TryLoadClubFinder()
  end

  if not ClubFinderGetCurrentClubListingInfo or not GetClubFinderLink then
    if self:IsDebugEnabled(3) and not state._gripGuildLinkLoggedFailure then
      self:Trace("GetGuildFinderLink: ClubFinder link APIs unavailable (Blizzard_ClubFinder not loaded?)")
      state._gripGuildLinkLoggedFailure = true
    end
    SetGuildLinkCache("", false)
    return ""
  end

  local ok, clubId = pcall(C_Club.GetGuildClubId)
  if not ok or not clubId then
    if self:IsDebugEnabled(3) and not state._gripGuildLinkLoggedFailure then
      self:Trace("GetGuildFinderLink: no clubId from C_Club.GetGuildClubId")
      state._gripGuildLinkLoggedFailure = true
    end
    SetGuildLinkCache("", false)
    return ""
  end

  local ok2, listing = pcall(ClubFinderGetCurrentClubListingInfo, clubId)
  if not ok2 or not listing then
    if self:IsDebugEnabled(3) and not state._gripGuildLinkLoggedFailure then
      self:Trace("GetGuildFinderLink: no listing info (guild listing may not be published or not cached yet)")
      state._gripGuildLinkLoggedFailure = true
    end
    SetGuildLinkCache("", false)
    return ""
  end
  if not listing.clubFinderGUID or not listing.name then
    if self:IsDebugEnabled(3) and not state._gripGuildLinkLoggedFailure then
      self:Trace("GetGuildFinderLink: listing missing clubFinderGUID/name")
      state._gripGuildLinkLoggedFailure = true
    end
    SetGuildLinkCache("", false)
    return ""
  end

  local ok3, link = pcall(GetClubFinderLink, listing.clubFinderGUID, listing.name)
  if ok3 and type(link) == "string" and link ~= "" then
    -- Success! Cache it and reset failure flag.
    state._gripGuildLinkLoggedFailure = false
    SetGuildLinkCache(link, true)
    if self:IsDebugEnabled(3) then
      self:Trace("GetGuildFinderLink: success, link cached")
    end
    return link
  end

  if self:IsDebugEnabled(3) and not state._gripGuildLinkLoggedFailure then
    self:Trace("GetGuildFinderLink: GetClubFinderLink failed or returned empty")
    state._gripGuildLinkLoggedFailure = true
  end
  SetGuildLinkCache("", false)
  return ""
end
```

---

## Task 3: Add Guild Data Event Handlers in Core/Events.lua

### 3a. Register new events

In Events.lua, after the existing `RegisterEvent` calls (around line 165), add:

```lua
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("INITIAL_CLUBS_LOADED")
```

### 3b. Add event handlers

In the `OnEvent` script handler, add these handlers (before the final `end` of the handler function, after the `CHAT_MSG_SYSTEM` block):

```lua
  if event == "PLAYER_GUILD_UPDATE" then
    -- Guild membership info is now available. Warm the guild name cache.
    local guildName = GRIP:GetGuildName()
    if GRIP:IsDebugEnabled(2) then
      GRIP:Debug("PLAYER_GUILD_UPDATE: guild=", tostring(guildName))
    end
    return
  end

  if event == "GUILD_ROSTER_UPDATE" then
    -- Roster data ready. Warm guild name cache (backup for PLAYER_GUILD_UPDATE).
    local guildName = GRIP:GetGuildName()
    if GRIP:IsDebugEnabled(3) then
      GRIP:Trace("GUILD_ROSTER_UPDATE: guild=", tostring(guildName))
    end
    return
  end

  if event == "INITIAL_CLUBS_LOADED" then
    -- Club system ready. C_Club.GetGuildClubId() should now work.
    -- Reset guild link cache so GetGuildFinderLink() retries with fresh data.
    state._gripGuildLinkCache = nil
    state._gripGuildLinkLoggedFailure = false
    if GRIP:IsDebugEnabled(2) then
      local link = GRIP:GetGuildFinderLink()
      GRIP:Debug("INITIAL_CLUBS_LOADED: guildLink=", (link ~= "" and "OK" or "unavailable"))
    end
    return
  end
```

---

## Task 4: Add Debug Copy Frame

### 4a. Add `ShowDebugCopyFrame()` to Core/Debug.lua

At the end of `Core/Debug.lua`, add a function that creates a scrollable, copyable text frame:

```lua
function GRIP:ShowDebugCopyFrame(n)
  n = tonumber(n) or 200
  n = GRIP:Clamp(n, 1, 2000)

  local lines = self:GetPersistedDebugLines()
  if type(lines) ~= "table" or #lines == 0 then
    self:Print("Debug log is empty. Enable with: /grip debug on, then /grip debug capture on")
    return
  end

  local total = #lines
  local start = math.max(1, total - n + 1)

  -- Build the text block
  local textLines = {}
  for i = start, total do
    textLines[#textLines + 1] = lines[i]
  end
  local text = table.concat(textLines, "\n")

  -- Reuse or create the frame
  local frame = state._gripDebugCopyFrame
  if not frame then
    frame = CreateFrame("Frame", "GRIPDebugCopyFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(650, 450)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -3)
    frame.title:SetText("GRIP Debug Log")

    -- ScrollFrame
    local sf = CreateFrame("ScrollFrame", "GRIPDebugCopyScrollFrame", frame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", frame.InsetBg or frame, "TOPLEFT", 8, -30)
    sf:SetPoint("BOTTOMRIGHT", frame.InsetBg or frame, "BOTTOMRIGHT", -27, 30)
    frame.scrollFrame = sf

    -- EditBox (multiline, for select/copy)
    local eb = CreateFrame("EditBox", "GRIPDebugCopyEditBox", sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetWidth(sf:GetWidth() or 580)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Prevent user from modifying the text (re-set on any change)
    eb._gripLocked = true
    eb:SetScript("OnTextChanged", function(self)
      if self._gripLocked and self._gripOrigText then
        self:SetText(self._gripOrigText)
      end
    end)
    sf:SetScrollChild(eb)
    frame.editBox = eb

    -- Footer hint
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 8)
    frame.hintText = hint

    -- ESC to close
    tinsert(UISpecialFrames, "GRIPDebugCopyFrame")

    state._gripDebugCopyFrame = frame
  end

  -- Populate
  local shown = total - start + 1
  frame.editBox._gripLocked = false
  frame.editBox:SetText(text)
  frame.editBox._gripOrigText = text
  frame.editBox._gripLocked = true
  frame.editBox:SetCursorPosition(0)

  local dropped = self:GetPersistedDebugDropped()
  frame.hintText:SetText(("Lines: %d of %d (dropped: %d) | Ctrl+A to select, Ctrl+C to copy"):format(shown, total, dropped))

  frame:Show()
  frame.editBox:SetFocus()
  frame.editBox:HighlightText()
end
```

### 4b. Add `/grip debug copy` command in Core/Slash.lua

In the `cmd == "debug"` block in `HandleSlash()`, add a new subcommand handler after the `sub == "dump"` block:

```lua
    if sub == "copy" then
      if GRIP.ShowDebugCopyFrame then
        GRIP:ShowDebugCopyFrame(tonumber(subrest) or 200)
      else
        GRIP:Print("Debug copy frame unavailable.")
      end
      return
    end
```

Also update `PrintDebugUsage()` to include the new command:

Change:
```lua
GRIP:Print("Usage: /grip debug on|off | dump [n] | clear | capture on|off [max] | status")
```
To:
```lua
GRIP:Print("Usage: /grip debug on|off | dump [n] | copy [n] | clear | capture on|off [max] | status")
```

And in `PrintHelp()`, add a line for the copy command:
```lua
self:Print("  /grip debug copy [n]        - open copyable debug log window (last n lines)")
```

---

## Task 5: Verification

After all changes:

1. **Lua syntax check**: Ensure all modified files parse without errors.
2. **GetGuildName() logic**: Verify the function correctly:
   - Returns cached guild name during early login (doesn't overwrite with "")
   - Clears cache only when `IsInGuild()` returns false
   - No reference to `C_GuildInfo.GetGuildInfo`
3. **GetGuildFinderLink() logic**: Verify:
   - Uses cache with TTL (300s success, 30s failure)
   - Only logs trace failures once per cache cycle
   - Resets cache on `INITIAL_CLUBS_LOADED`
4. **Events.lua**: Verify three new events registered and handled.
5. **Debug copy frame**: Verify `/grip debug copy` creates a frame with selectable text.
6. **No functional changes** to recruitment pipeline, blacklist, or UI pages.

---

## Output Format

When done, provide output in this exact format:

```
## Summary
Fix guild name/link resolution, add event-driven cache warming, add debug copy frame

## Description
- Fixed GetGuildName(): removed dead C_GuildInfo.GetGuildInfo path (API doesn't exist), improved cache to not poison with empty string during early login
- Fixed GetGuildFinderLink(): added timestamp-based cache (5min success / 30s failure TTL), suppressed repeated trace spam to one log per cache cycle
- Added PLAYER_GUILD_UPDATE, GUILD_ROSTER_UPDATE, INITIAL_CLUBS_LOADED event handlers to warm guild name and guild link caches proactively
- Added /grip debug copy [n] command with a copyable ScrollFrame+EditBox for debug log export

Zero changes to recruitment pipeline, blacklist system, or UI pages.

## Files Modified
[list every file you touched]

## Verification
- [ ] All .lua files parse without syntax errors
- [ ] GetGuildName() has no reference to C_GuildInfo.GetGuildInfo
- [ ] GetGuildName() preserves cache when GetGuildInfo returns nil but IsInGuild is true
- [ ] GetGuildFinderLink() uses cache with TTL
- [ ] GetGuildFinderLink() only logs failures once per cache cycle
- [ ] Events.lua registers PLAYER_GUILD_UPDATE, GUILD_ROSTER_UPDATE, INITIAL_CLUBS_LOADED
- [ ] INITIAL_CLUBS_LOADED handler resets guild link cache
- [ ] /grip debug copy opens copyable frame
- [ ] No functional code changes to Who/Whisper/Invite/Post/Blacklist/UI pages

## Lines Changed (approximate)
[total count]
```
