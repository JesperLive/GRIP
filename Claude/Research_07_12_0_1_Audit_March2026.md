# Research 07 — GRIP 12.0.1 API Audit (March 2026)

> **Compiled:** 2026-03-01
> **Target build:** World of Warcraft, The War Within — Midnight, 12.0.1 (66192) Release x64, Feb 27 2026
> **GRIP version:** 0.4.0

---

## Purpose

This document cross-references every WoW API that GRIP uses against the actual 12.0.0 / 12.0.1 API state as confirmed by Warcraft Wiki (warcraft.wiki.gg) and live-game behavior in the Feb 27 2026 build. It corrects errors in the earlier Research_02 document and provides concrete action items.

---

## Corrections to Research_02 (Midnight Changes)

Research_02 listed two APIs as "removed in 12.0." After verification against Warcraft Wiki (updated Jan–Feb 2026), **both claims are wrong:**

| API | Research_02 Claim | Actual Status (12.0.1) | Source |
|-----|-------------------|----------------------|--------|
| `GetChannelList()` | "Removed in 12.0" | **Still available.** Listed for Mainline 12.0.1. Returns triplets: id, name, disabled. | [warcraft.wiki.gg/wiki/API_GetChannelList](https://warcraft.wiki.gg/wiki/API_GetChannelList) |
| `ChatFrame_AddMessageEventFilter()` | "Removed in 12.0" | **Still available.** No deprecation notice. Still the standard way to filter chat messages. | [warcraft.wiki.gg/wiki/API_ChatFrame_AddMessageEventFilter](https://warcraft.wiki.gg/wiki/API_ChatFrame_AddMessageEventFilter) |

**What actually happened:** Patch 12.0.0 removed APIs deprecated in 11.x (listed in `Deprecated_ChatFrame.lua`, `Deprecated_ChatInfo.lua`, etc.), but `GetChannelList` and `ChatFrame_AddMessageEventFilter` were never among those deprecated. The `Deprecated_ChatFrame.lua` file contains other chat frame functions that were moved to namespaced equivalents during TWW.

### Implication for GRIP

The "High Priority" action items in Research_Index.md to replace these APIs are **not needed**. GRIP's current usage of both functions is correct and will continue to work.

---

## Confirmed API Status for All GRIP Dependencies

### Chat & Messaging

| API | GRIP Usage | 12.0.1 Status | Action |
|-----|-----------|---------------|--------|
| `SendChatMessage(msg, type, lang, target)` | Utils.lua fallback | **Deprecated** in 11.2.0. Still works but will be removed "in the future." | **Migrate to C_ChatInfo.SendChatMessage** |
| `C_ChatInfo.SendChatMessage(msg, type, lang, target)` | Utils.lua primary path | **Current.** Added 11.2.0, available 12.0.1. | ✅ Already used as primary |
| `ChatFrame_AddMessageEventFilter(event, fn)` | Utils.lua whisper echo suppression | **Available.** Not deprecated. | ✅ No change needed |
| `GetChannelList()` | Post.lua channel discovery | **Available.** Not deprecated. | ✅ No change needed |

### Guild System

| API | GRIP Usage | 12.0.1 Status | Action |
|-----|-----------|---------------|--------|
| `GuildInvite(name)` | Invite.lua, UnitPopupInvite.lua | **Deprecated** since 10.2.6. Hardware-event restricted. Still works. | **Replace with C_GuildInfo.Invite(name)** |
| `C_GuildInfo.Invite(name)` | Not used yet | **Current.** Same signature, same hardware-event restriction. | Adopt as replacement |
| `IsInGuild()` | UnitPopupInvite.lua | **Available.** | ✅ No change needed |
| `CanGuildInvite()` | Invite.lua, UnitPopupInvite.lua | **Available.** | ✅ No change needed |
| `C_Club.GetGuildClubId()` | Utils.lua guild link | **Available.** | ✅ No change needed |
| `ClubFinderGetCurrentClubListingInfo()` | Utils.lua guild link | **Available.** | ✅ No change needed |
| `GetClubFinderLink()` | Utils.lua guild link | **Available.** | ✅ No change needed |

### /who System

| API | GRIP Usage | 12.0.1 Status | Action |
|-----|-----------|---------------|--------|
| `C_FriendList.SendWho(filter, origin)` | Who.lua | **Available.** Hardware-event restricted. `origin` arg added 10.2.0 (Enum.SocialWhoOrigin). | **Check: are we passing origin?** |
| `C_FriendList.GetNumWhoResults()` | Who.lua | **Available.** | ✅ No change needed |
| `C_FriendList.GetWhoInfo(index)` | Who.lua | **Available.** Returns WhoInfo struct. Field `timerunningSeasonID` added 10.2.7. | ✅ No change needed |

### Character/Race Data

| API | GRIP Usage | 12.0.1 Status | Action |
|-----|-----------|---------------|--------|
| `C_CharacterCreation.GetAvailableRaces()` | DB_Init.lua race seeding | **Available.** Returns structs with `.raceID` field. | ✅ Fixed in recent bugfix (extracts .raceID) |
| `C_CreatureInfo.GetRaceInfo(raceID)` | DB_Init.lua race seeding | **Available.** | ✅ No change needed |

### Map/Zone Data

| API | GRIP Usage | 12.0.1 Status | Action |
|-----|-----------|---------------|--------|
| `C_Map.GetMapChildrenInfo(mapID, type, all)` | DB_Zones.lua | **Available.** | ✅ No change needed |

### UI Framework

| API | GRIP Usage | 12.0.1 Status | Action |
|-----|-----------|---------------|--------|
| `FauxScrollFrame_*` functions | UI_Home.lua (2 scroll frames) | **Available.** Not deprecated. Blizzard added ScrollBox as a modern alternative but FauxScrollFrame still works. | ✅ No change needed now (optional modernization later) |
| `UISpecialFrames` | UI.lua (ESC-to-close) | **Available.** Still ipairs-iterated by Blizzard. | ✅ Fixed in recent bugfix (uses tinsert) |
| `CreateFrame()` | Throughout | **Available.** | ✅ No change needed |
| Menu API (rootDescription, etc.) | UnitPopupInvite.lua | **Available.** 12.0 standard. | ✅ No change needed |

### Timers & Utility

| API | GRIP Usage | 12.0.1 Status | Action |
|-----|-----------|---------------|--------|
| `C_Timer.After()` / `C_Timer.NewTicker()` | Throughout | **Available.** Do NOT preserve hardware events. | ✅ No change needed |
| `GetTime()` | Throughout | **Available.** | ✅ No change needed |
| `time()` | Throughout | **Available.** | ✅ No change needed |
| `InCombatLockdown()` | Invite, Post, GhostMode | **Available.** | ✅ No change needed |

---

## Required Code Changes

### 1. Replace `GuildInvite()` with `C_GuildInfo.Invite()` — HIGH

**Priority:** High — `GuildInvite()` is deprecated since 10.2.6 and could be removed at any time.

**Files affected:**
- `Recruit/Invite.lua` line 340: `GuildInvite(name)` → `C_GuildInfo.Invite(name)`
- `Hooks/UnitPopupInvite.lua` line 193: `GuildInvite(targetName)` → `C_GuildInfo.Invite(targetName)`

**Approach:** Create a compat wrapper that tries `C_GuildInfo.Invite` first, falls back to `GuildInvite`:
```lua
local function SafeGuildInvite(name)
  if C_GuildInfo and C_GuildInfo.Invite then
    C_GuildInfo.Invite(name)
  elseif GuildInvite then
    GuildInvite(name)
  end
end
```

**Also update:**
- `Hooks/UnitPopupInvite.lua` line 127-128: The `not GuildInvite` check should also check `C_GuildInfo.Invite`.
- All comments referencing `GuildInvite()` should mention both APIs.
- `Core/Core.lua` line 7 comment.

### 2. Update `scanMaxLevel` default to 90 — HIGH

**Priority:** High — Midnight raised the level cap from 80 to 90. The default scan range is stuck at 90 already in DB_Init.lua (line 34), BUT `Who.lua` line 352 has a fallback of `or 80` which is stale.

**Files affected:**
- `Recruit/Who.lua` line 352: `cfg.scanMaxLevel or 80` → `cfg.scanMaxLevel or 90`

**Note:** DB_Init.lua already defaults to 90 (correct). The `or 80` in Who.lua is a defensive fallback that would only trigger if config is nil, but it should still say 90 for consistency and correctness.

### 3. Add Midnight zones to static zone list — MEDIUM

**Priority:** Medium — Midnight adds new Quel'Thalas zones. GRIP's deep scan will find them, but the static fallback list in `Data/Maps_Zones.lua` should include them.

**New zones to add:**
- Eversong Woods (reimagined — already in static list but may have new mapID)
- Zul'Aman (new outdoor zone)
- Harandar (new zone)
- Ghostlands (reimagined)

### 4. Add Haranir to race awareness — LOW

**Priority:** Low — The race seed function already dynamically pulls races from `C_CharacterCreation.GetAvailableRaces()`. The Haranir allied race (added in Midnight, unlockable via campaign) will appear automatically once a player has unlocked them. No code change needed, but if GRIP ships a fallback race list, Haranir should be in it.

### 5. Pass `origin` parameter to `C_FriendList.SendWho()` — LOW

**Priority:** Low — The `origin` parameter was added in 10.2.0. It's optional (defaults work), but passing `Enum.SocialWhoOrigin.Social` or a numeric `1` would be more correct. Check if GRIP currently passes it.

### 6. TOC Interface version — VERIFY

**Priority:** Verify — GRIP.toc says `## Interface: 120001`. This is correct for 12.0.1. No change needed.

---

## What Midnight 12.0 Actually Changed (Relevant to GRIP)

### Combat API Restrictions ("Secret Values")
GRIP is **not affected** by the major Midnight addon changes. The "addon disarmament" focused on:
- Combat log events (removed for addons)
- Unit aura/buff details becoming "secret" during encounters
- Boss mod automation restricted
- Damage meter data restricted

None of these touch recruitment (/who, whispers, guild invites, channel posts). GRIP's feature set is entirely outside the combat domain.

### Instance Communication Lockdown
Midnight restricts addon comms during active mythic keystones, PvP matches, and encounter progression. This is irrelevant to GRIP — guild recruitment happens in the open world, not during encounters.

### New Events Added in 12.0.1
None relevant to GRIP. New events are for housing, encounter timelines, photo sharing, and damage meters.

### Removed APIs in 12.0.1
8 APIs removed — none used by GRIP:
- `C_BattleNet.SetAFK/SetDND`, `BNSetAFK/BNSetDND`
- `C_CombatAudioAlert.GetSpeakerVolume/SetSpeakerVolume`
- `C_NamePlate.GetTargetClampingInsets`
- `GetCurrentGraphicsSetting/SetCurrentGraphicsSetting`

---

## Summary of Action Items

| # | Change | Priority | Files |
|---|--------|----------|-------|
| 1 | Replace `GuildInvite()` → `C_GuildInfo.Invite()` with compat wrapper | HIGH | Invite.lua, UnitPopupInvite.lua, Core.lua (comments) |
| 2 | Fix `scanMaxLevel` fallback: `or 80` → `or 90` | HIGH | Who.lua |
| 3 | Add Midnight zones to static zone list | MEDIUM | Data/Maps_Zones.lua |
| 4 | Add Haranir to fallback race list (if one exists) | LOW | Data/Maps_Zones.lua or DB_Init.lua |
| 5 | Pass `origin` param to `SendWho()` | LOW | Who.lua |
| 6 | Correct Research_Index.md action items | DOCS | Claude/Research_Index.md |

---

## Sources

- [Patch 12.0.0 API Changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- [Patch 12.0.1 API Changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.1/API_changes)
- [Patch 12.0.0 Planned API Changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes)
- [GuildInvite — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_GuildInvite) — Deprecated 10.2.6
- [C_GuildInfo.Invite — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_GuildInfo.Invite) — Replacement, available 12.0.1
- [SendChatMessage — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_SendChatMessage) — Deprecated 11.2.0
- [C_ChatInfo.SendChatMessage — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendChatMessage) — Available since 11.2.0
- [ChatFrame_AddMessageEventFilter — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_ChatFrame_AddMessageEventFilter) — NOT deprecated
- [GetChannelList — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_GetChannelList) — NOT deprecated/removed
- [C_FriendList.SendWho — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_FriendList.SendWho) — origin param since 10.2.0
- [C_FriendList.GetWhoInfo — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_FriendList.GetWhoInfo) — WhoInfo struct docs
- [Combat Philosophy and Addon Disarmament — Blizzard](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)
- [Midnight Content Update Notes — Blizzard](https://news.blizzard.com/en-us/article/24244646/midnight-content-update-notes) — Level cap 90, new zones
