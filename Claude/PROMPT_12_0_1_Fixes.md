# Claude Code Prompt — GRIP 12.0.1 API Migration

> Copy-paste this entire prompt into Claude Code.

---

## Context

GRIP is a WoW guild recruitment addon targeting Retail / Midnight 12.0.1 (build 66192, Feb 27 2026). I've completed an API audit against the live 12.0.1 build (documented in `Claude/Research_07_12_0_1_Audit_March2026.md`). The audit found that two previously-flagged APIs (`GetChannelList` and `ChatFrame_AddMessageEventFilter`) are actually fine — they were never removed. But there are real deprecations that need fixing.

**Before you start, read:** `Claude/Research_07_12_0_1_Audit_March2026.md` for full details and sources.

## Tasks

Apply the following changes. Each one is small and surgical — do NOT refactor surrounding code.

### 1. Replace `GuildInvite()` with `C_GuildInfo.Invite()` compat wrapper (HIGH)

`GuildInvite()` has been deprecated since 10.2.6. `C_GuildInfo.Invite(name)` is the replacement — same signature (takes a single string), same hardware-event restriction.

**Create a compat wrapper** in `Core/Utils.lua` (or `Core/Core.lua`, whichever is more appropriate given the load order):

```lua
-- Guild invite compat: prefer C_GuildInfo.Invite (12.0+), fall back to GuildInvite (deprecated 10.2.6)
function GRIP:SafeGuildInvite(name)
  if C_GuildInfo and C_GuildInfo.Invite then
    C_GuildInfo.Invite(name)
  elseif GuildInvite then
    GuildInvite(name)
  else
    self:Print("No guild invite API available.")
    return false
  end
  return true
end
```

Then replace all direct calls:

- **`Recruit/Invite.lua`** — find `GuildInvite(name)` and replace with `self:SafeGuildInvite(name)` (or `GRIP:SafeGuildInvite(name)` depending on context).
- **`Hooks/UnitPopupInvite.lua`** — find `GuildInvite(targetName)` and replace with `GRIP:SafeGuildInvite(targetName)`.
- **`Hooks/UnitPopupInvite.lua`** — find the `not GuildInvite` availability check (around line 127-128) and update it to check `not (C_GuildInfo and C_GuildInfo.Invite) and not GuildInvite`.
- **`Core/Core.lua`** — update the comment on line 7 from `-- - GuildInvite()` to `-- - C_GuildInfo.Invite() (compat: GuildInvite deprecated 10.2.6)`.

### 2. Fix stale `scanMaxLevel` fallback in Who.lua (HIGH)

Midnight raised the level cap to 90. `DB_Init.lua` already defaults `scanMaxLevel = 90`, but `Who.lua` has a defensive fallback:

- **`Recruit/Who.lua`** — find `cfg.scanMaxLevel or 80` and change to `cfg.scanMaxLevel or 90`.

### 3. Add Midnight zones to static zone list (MEDIUM)

**`Data/Maps_Zones.lua`** contains a shipped static zone list. Add the new Midnight zones. Look at how existing zones are added (they're just string entries in a table). Add these to the appropriate section:

```lua
-- Midnight (12.0)
"Eversong Woods",       -- reimagined
"Ghostlands",           -- reimagined
"Zul'Aman",             -- new outdoor zone
"Harandar",             -- new zone
```

Note: "Eversong Woods" and "Ghostlands" may already be in the list from the original TBC entries. If so, don't duplicate them — just add "Zul'Aman" and "Harandar". Check first.

### 4. Pass `origin` parameter to `SendWho()` (LOW)

**`Recruit/Who.lua`** — find the call to `C_FriendList.SendWho(filter)` and add the origin parameter:

```lua
C_FriendList.SendWho(filter, Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social or 1)
```

This is optional but correct. The `Enum.SocialWhoOrigin` check is a nil guard for older clients.

## Rules

- Do NOT touch any code beyond what's described above.
- Do NOT refactor, reorganize, or "improve" surrounding code.
- Preserve all existing comments, whitespace style, and patterns.
- Every file you touch: verify it still loads correctly in the TOC dependency order.
- The compat wrapper must be in a file that loads BEFORE `Recruit/Invite.lua` and `Hooks/UnitPopupInvite.lua` in the TOC order.

## Output

When you're done, provide a copy-paste-ready summary in this exact format:

```
## GRIP 12.0.1 API Migration — Changes Applied

### Files Modified
[list each file and what changed]

### Change Details

**1. GuildInvite → C_GuildInfo.Invite compat wrapper**
- Added: [where the wrapper was added]
- Replaced: [list each callsite]
- Updated checks: [list]
- Updated comments: [list]

**2. scanMaxLevel fallback**
- File: Recruit/Who.lua
- Change: `or 80` → `or 90`

**3. Midnight zones**
- File: Data/Maps_Zones.lua
- Added: [list zones added]

**4. SendWho origin parameter**
- File: Recruit/Who.lua
- Change: [describe]

### Verification
- [ ] All modified files parse without Lua syntax errors
- [ ] TOC load order dependencies are satisfied
- [ ] No unintended changes to other code
```
