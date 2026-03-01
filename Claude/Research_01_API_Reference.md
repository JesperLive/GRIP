# GRIP API Reference — WoW Addon APIs Used by GRIP

> Compiled March 2026. Targets Retail / Midnight (12.0.1+).

---

## 1. C_FriendList — /who Scanning

### C_FriendList.SendWho(filter)

```lua
C_FriendList.SendWho(filter)  -- no return value
```

- **filter** `string` — query string, e.g. `"1-10"`, `"1-10 c-\"Warrior\""`, `"1-10 z-\"Stormwind City\""`
- **Hardware event required**: YES (since Patch 8.2.5)
- **Fires**: `WHO_LIST_UPDATE` when results arrive
- **Server-side throttle**: Silent — requests sent too quickly are dropped without any visible feedback. No `WHO_LIST_UPDATE` fires for throttled queries.
- **Recommended spacing**: 15+ seconds between queries (aligns with the UI cooldown). GRIP uses `minWhoInterval = 15`.

**Filter string format:**

| Component | Syntax | Example |
|-----------|--------|---------|
| Level range | `"min-max"` | `"1-10"` |
| Class filter | `c-"ClassName"` | `c-"Warrior"` |
| Zone filter | `z-"ZoneName"` | `z-"Stormwind City"` |
| Race filter | `r-"RaceName"` | `r-"Human"` |
| Guild filter | `g-"GuildName"` | `g-"My Guild"` |
| Name filter | `n-"Name"` | `n-"Thrall"` |

Filters can be combined: `"1-10 c-\"Warrior\" z-\"Stormwind City\""`

### C_FriendList.GetNumWhoResults()

```lua
local numWhos, totalCount = C_FriendList.GetNumWhoResults()
```

- **numWhos** `number` — results returned (capped at 50)
- **totalCount** `number` — total matching players server-side
- **No hardware event required** — safe to call from tickers/events
- **The 50-result cap**: Hard FrameXML ceiling. No pagination workaround. When `numWhos == 50`, the results are saturated and you're missing players.

**GRIP's saturation workaround**: When 50/50 detected, auto-expands the same level bracket with class sub-filters to get more complete coverage.

### C_FriendList.GetWhoInfo(index)

```lua
local info = C_FriendList.GetWhoInfo(index)  -- index is 1-based
```

Returns a table:
```lua
{
    fullName = "Name-Realm",   -- string
    fullGuildName = "Guild-Realm",  -- string (empty if unguilded)
    level = 10,                -- number
    raceStr = "Human",         -- string (localized)
    classStr = "Warrior",      -- string (localized)
    area = "Stormwind City",   -- string (localized)
    filename = "WARRIOR",      -- string (uppercased class token)
    sex = 2,                   -- number (1=unknown, 2=male, 3=female)
}
```

---

## 2. SendChatMessage / C_ChatInfo.SendChatMessage

### Signatures

```lua
-- Modern (preferred)
C_ChatInfo.SendChatMessage(msg, chatType, languageID, target)

-- Legacy fallback
SendChatMessage(msg, chatType, languageID, target)
```

- **msg** `string` — message text (max 255 bytes; exceeding causes disconnect)
- **chatType** `string` — "SAY", "YELL", "WHISPER", "GUILD", "PARTY", "RAID", "CHANNEL", etc.
- **languageID** `number|nil` — language ID or nil for default
- **target** `string|number` — player name for WHISPER, channel ID (number) for CHANNEL

### Hardware Event Requirements by Chat Type

| Chat Type | Hardware Event? | Notes |
|-----------|----------------|-------|
| WHISPER | **NO** | Unrestricted — safe from tickers/events |
| GUILD | **NO** | Unrestricted |
| PARTY | **NO** | Unrestricted |
| RAID | **NO** | Unrestricted |
| CHANNEL | **YES** | Always required (Trade, General, custom) |
| SAY | **YES** | Outdoors; unrestricted indoors/instances |
| YELL | **YES** | Outdoors; unrestricted indoors/instances |

### Message Size Limit

The hard limit is **255 bytes** (not 255 characters). Messages exceeding this are silently truncated. Some older documentation states it causes a disconnect — either way, exceeding the limit is problematic.

GRIP uses a conservative 250-char limit with `SafeTruncateChat()`. This is prudent, but note: multi-byte characters (emoji like the 🙂 in GRIP's default templates, non-ASCII text) count as multiple bytes. A 250-character message with emoji could exceed 255 bytes. Consider byte-counting for strict safety.

### Sending to Offline Players

Whispers to offline/non-existent players generate a `CHAT_MSG_SYSTEM` event with the pattern matching `ERR_CHAT_PLAYER_NOT_FOUND_S` ("No player named '%s' is currently playing.").

### CHAT_MSG_WHISPER_INFORM Event

Fires when YOUR outgoing whisper is confirmed sent:

```lua
-- arg1 = message text
-- arg2 = "" (empty)
-- arg3 = "" (empty)
-- arg4 = "" (empty)
-- arg5 = target player name (who received it)
-- arg6..arg11 = various metadata
```

GRIP uses this for whisper confirmation tracking.

---

## 3. GuildInvite

```lua
GuildInvite(fullName)
```

- **fullName** `string` — "Name" or "Name-Realm" for cross-realm
- **Hardware event required**: YES
- **Combat lockdown**: Blocked (check `InCombatLockdown()` first)
- **Deprecated**: Marked in Patch 10.2.6. Replacement: `C_GuildInfo.Invite()` (same HW event requirement).

### System Message Patterns (CHAT_MSG_SYSTEM)

| Global String | Pattern | Meaning |
|---------------|---------|---------|
| `ERR_GUILD_INVITE_S` | "You have invited %s to join your guild" | Invite sent (informational) |
| `ERR_GUILD_JOIN_S` | "%s has joined the guild" | Player accepted |
| `ERR_GUILD_DECLINE_S` | "%s declines your guild invitation" | Player declined |
| `ERR_ALREADY_IN_GUILD_S` | "%s is already in a guild" | Target is guilded |
| `ERR_ALREADY_INVITED_TO_GUILD_S` | "%s has already been invited to a guild" | Pending invite exists |
| `ERR_GUILD_PLAYER_NOT_FOUND_S` | "Player not found" | Invalid/offline name |

### Cross-Realm Names

- Same realm: `GuildInvite("PlayerName")` works
- Cross-realm: `GuildInvite("PlayerName-RealmName")` — realm name with no spaces (e.g., "Area52" not "Area 52")
- Connected realms: Either name format works

---

## 4. C_Club / C_ClubFinder — Guild Finder Links

### C_Club.GetGuildClubId()

```lua
local clubId = C_Club.GetGuildClubId()  -- returns string or nil
```

- Returns `nil` during login before `INITIAL_CLUBS_LOADED` fires
- Returns `nil` if player is not in a guild
- Race condition: Don't call on `ADDON_LOADED`; wait for `PLAYER_GUILD_UPDATE` or `INITIAL_CLUBS_LOADED`

### ClubFinderGetCurrentClubListingInfo(clubId)

```lua
local listing = ClubFinderGetCurrentClubListingInfo(clubId)
```

- **Global function** (NOT `C_ClubFinder.` namespaced)
- Requires `Blizzard_ClubFinder` addon to be loaded
- Returns `RecruitingClubInfo` table or `nil`
- Returns `nil` if: guild has no active listing, addon not loaded, cache not populated yet

**RecruitingClubInfo structure:**
```lua
{
    clubFinderGUID = "ClubFinder-1-19160-1598-53720920",  -- string
    clubId = "15554351",    -- string
    name = "Guild Name",    -- string
    comment = "...",        -- recruitment message
    guildLeader = "Name",   -- string
    isGuild = true,         -- boolean
    numActiveMembers = 42,  -- number
    minILvl = 0,            -- number
    isCrossFaction = false, -- boolean (9.2.5+)
    -- ... additional fields
}
```

### GetClubFinderLink(clubFinderGUID, name)

```lua
local link = GetClubFinderLink(listing.clubFinderGUID, listing.name)
-- Returns: "|cffffd100|HclubFinder:ClubFinder-1-19160-...|h[Guild: Name]|h|r"
```

- Returns a clickable hyperlink string (~60-120 chars depending on name length)
- Works in all chat types: whispers, channel messages, guild chat
- Recipients can click to open Guild Finder listing and apply
- Cross-realm compatible

### Loading Blizzard_ClubFinder

```lua
if not C_AddOns.IsAddOnLoaded("Blizzard_ClubFinder") then
    local loaded, reason = C_AddOns.LoadAddOn("Blizzard_ClubFinder")
end
```

**Pitfall**: Don't call `LoadAddOn()` inside an `ADDON_LOADED` event handler — the newly loaded addon's own `ADDON_LOADED` event may not fire. GRIP wraps this in `pcall()` for safety.

---

## 5. C_Map

### C_Map.GetMapChildrenInfo(mapID, mapType, allDescendants)

```lua
local children = C_Map.GetMapChildrenInfo(mapID, mapType, allDescendants)
```

- **mapID** `number` — parent map ID
- **mapType** `Enum.UIMapType|nil` — filter by type (Zone, Continent, etc.) or nil for all
- **allDescendants** `boolean` — if true, recursively includes all descendants
- **Returns**: array of `UIMapDetails` tables

GRIP uses this in `DB_Zones.lua` for building the zone allowlist and exclusion sets.

---

## 6. C_Timer

### C_Timer.After(seconds, callback)

```lua
C_Timer.After(2.5, function()
    -- runs once after ~2.5 seconds
end)
```

- Precision is frame-rate dependent (~16.67ms at 60 FPS)
- Does **NOT** preserve hardware event status
- Callback runs in insecure/tainted context

### C_Timer.NewTicker(seconds, callback, iterations)

```lua
local ticker = C_Timer.NewTicker(2.5, function(self)
    -- runs every ~2.5 seconds
    -- self:Cancel() to stop
end)
-- or with iteration limit:
local ticker = C_Timer.NewTicker(1.0, callback, 10)  -- 10 times then auto-stops
```

- **ticker:Cancel()** — stops the ticker
- Does **NOT** preserve hardware event status
- GRIP uses this for whisper queue (2.5s default) and post scheduler

---

## 7. Guild Status APIs

### IsInGuild()
```lua
if IsInGuild() then ... end  -- returns boolean
```

### CanGuildInvite()
```lua
if CanGuildInvite() then ... end  -- returns boolean (has invite permission)
```

### InCombatLockdown()
```lua
if InCombatLockdown() then ... end  -- returns boolean
```
Must check before calling any protected API (GuildInvite, CHANNEL sends, etc.).

### GetGuildInfo("player") vs C_GuildInfo

```lua
-- Legacy
local guildName, guildRankName, guildRankIndex, realm = GetGuildInfo("player")

-- Modern
local guildInfo = C_GuildInfo.GetGuildInfo("player")
-- Returns: { guildName, guildRankName, guildRankIndex, realm }
```

Both may return nil during login or if not in a guild. GRIP caches the last known guild name to survive transient empty returns.

---

## 8. ChatFrame_AddMessageEventFilter

```lua
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", function(self, event, msg, sender, ...)
    -- return true to suppress the message
    -- return false (or nothing) to let it through
    return false
end)
```

GRIP uses this for whisper echo suppression when `suppressWhisperEcho` is enabled.

**12.0 status**: This function was marked as deprecated. See the Midnight Changes document for migration notes.

---

## 9. GetChannelList

```lua
local id1, name1, disabled1, id2, name2, disabled2, ... = GetChannelList()
```

Returns triplets: `(channelID, channelName, isDisabled)` for all joined channels.

GRIP iterates this to find Trade and General channel IDs:
```lua
local channelId, channelName
for i = 1, 20 do
    local id, name, disabled = select(i*3-2, GetChannelList())
    if not id then break end
    if name and name:lower():find("trade") then
        channelId = id
    end
end
```

**12.0 status**: `GetChannelList()` was removed in Patch 12.0.0. See Midnight Changes document for replacement approach.

---

## 10. Global Strings — System Message Patterns

These are the localized format strings GRIP uses for pattern matching in `CHAT_MSG_SYSTEM`:

```lua
ERR_GUILD_INVITE_S           -- "You have invited %s to join your guild"
ERR_GUILD_JOIN_S             -- "%s has joined the guild"
ERR_GUILD_DECLINE_S          -- "%s declines your guild invitation"
ERR_ALREADY_IN_GUILD_S       -- "%s is already in a guild"
ERR_ALREADY_INVITED_TO_GUILD_S -- "%s has already been invited to a guild"
ERR_GUILD_PLAYER_NOT_FOUND_S -- contains "not found"
ERR_CHAT_PLAYER_NOT_FOUND_S  -- "No player named '%s' is currently playing"
ERR_CHAT_PLAYER_AMBIGUOUS_S  -- "Player not found (ambiguous)"
ERR_CHAT_PLAYER_IGNORED_S    -- "Player is ignoring you"
```

**Localization concern**: These strings change per locale. GRIP's `NormGS()` helper strips grammar tokens like `|3-6(%s)` and provides English fallback patterns for safety.

---

## Quick Reference: Throttle Behavior

| API | Hardware Event | Server Throttle | Safe Interval |
|-----|---------------|-----------------|---------------|
| C_FriendList.SendWho | YES | Silent drop | 15s+ |
| GuildInvite | YES | Per-invite | 1-2s |
| SendChatMessage (WHISPER) | NO | Soft rate limit | 2-3s |
| SendChatMessage (CHANNEL) | YES | "Too fast" error | 8-15s |
| C_Club.GetGuildClubId | NO | None | Anytime |
| ClubFinderGetCurrentClubListingInfo | NO | Cache-based | Anytime |
