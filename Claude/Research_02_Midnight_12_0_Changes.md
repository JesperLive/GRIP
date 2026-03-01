# Midnight / 12.0 Changes Affecting GRIP

> Compiled March 2026. GRIP already targets Interface 120001.

---

## Overview

Patch 12.0.0 (Midnight pre-patch) introduced massive addon API changes, removing 138 APIs and adding 437 new ones. The primary focus was on combat data restrictions ("Secret Values") which don't directly affect guild recruitment. However, several changes are relevant to GRIP.

---

## 1. GRIP-Critical API Status

### Safe — No Changes Needed

| API | Status in 12.0 | Notes |
|-----|----------------|-------|
| `C_FriendList.SendWho()` | Still available | No changes to /who scanning |
| `C_FriendList.GetNumWhoResults()` | Still available | 50-result cap unchanged |
| `C_FriendList.GetWhoInfo()` | Still available | Still fires WHO_LIST_UPDATE |
| `GuildInvite()` | Still available | Deprecated since 10.2.6 but functional |
| `C_Club.GetGuildClubId()` | Still available | No changes |
| `C_ClubFinder` namespace | Still available | Guild Finder unchanged |
| `ClubFinderGetCurrentClubListingInfo()` | Still available | Global function unchanged |
| `GetClubFinderLink()` | Still available | Link format unchanged |
| `IsInGuild()` | Still available | No changes |
| `CanGuildInvite()` | Still available | No changes |
| `InCombatLockdown()` | Still available | No changes |
| `C_Timer.After()` / `C_Timer.NewTicker()` | Still available | No changes |
| `C_Map.GetMapChildrenInfo()` | Still available | No changes |
| `C_GuildInfo` namespace | Still available | No major changes |
| `C_AddOns.IsAddOnLoaded()` / `LoadAddOn()` | Still available | No changes |
| `Menu.ModifyMenu()` | Still available | GRIP's UnitPopup hook should still work |

### Potentially Affected — Needs Verification

| API | Status | Impact on GRIP | Action Required |
|-----|--------|---------------|-----------------|
| `GetChannelList()` | **Removed in 12.0** | GRIP uses this in `Recruit/Post.lua` to find Trade/General channel IDs | Migrate to alternative |
| `ChatFrame_AddMessageEventFilter()` | **Removed in 12.0** | GRIP uses this for whisper echo suppression | Migrate or remove feature |
| `SendChatMessage()` | Restricted in instances | Cannot send during M+/raid encounters | Add instance guard |

---

## 2. GetChannelList() Removal

`GetChannelList()` was removed in Patch 12.0.0. GRIP currently calls this in `Recruit/Post.lua` (lines 54-56) to discover Trade and General channel IDs.

### Migration Options

**Option A: Use C_ChatInfo.GetChannelInfoFromIdentifier()**
```lua
-- New approach for finding channel by name
local channelInfo = C_ChatInfo.GetChannelInfoFromIdentifier("Trade")
if channelInfo then
    local channelId = channelInfo.localID
end
```

**Option B: Use GetChannelName()**
```lua
-- May still be available — verify on 12.0
local id, name = GetChannelName("Trade - City")
```

**Option C: Hardcode common channel IDs**
Trade and General tend to have predictable IDs (General = 1, Trade = 2), but this varies by zone and isn't reliable.

**Recommendation**: Test `C_ChatInfo.GetChannelInfoFromIdentifier()` on 12.0. If unavailable, implement a fallback that listens for `CHANNEL_UI_UPDATE` or `CHAT_MSG_CHANNEL_NOTICE` events to discover channel IDs dynamically.

---

## 3. ChatFrame_AddMessageEventFilter() Removal

This was moved to `Deprecated_ChatFrame.lua` and removed in 12.0. GRIP uses it in `Core/Utils.lua` for whisper echo suppression.

### Impact on GRIP

The feature controlled by `GRIPDB.config.suppressWhisperEcho` (alias `hideOutgoingWhispers`) will break. This is a cosmetic/QoL feature, not core functionality.

### Migration Options

**Option A: Remove the feature entirely**
Whisper echo suppression is nice-to-have, not essential. Remove the filter registration and the config option.

**Option B: Use MessageEventFilter via C_ChatInfo (if available)**
Check if `C_ChatInfo` exposes an equivalent filtering mechanism in 12.0.

**Option C: Hook ChatFrame:AddMessage()**
```lua
-- Override the ChatFrame's AddMessage to filter specific whisper lines
local origAddMessage = ChatFrame1.AddMessage
ChatFrame1.AddMessage = function(self, msg, ...)
    if not ShouldSuppressWhisper(msg) then
        origAddMessage(self, msg, ...)
    end
end
```
This is fragile and may cause taint. Not recommended.

**Recommendation**: Remove the feature for 12.0 compatibility. It's low-value relative to the maintenance cost.

---

## 4. Instance Communication Restrictions

Midnight introduced restrictions on addon communication during active encounters:

- **Blocked during**: Active M+ keystones, PvP matches, boss encounters
- **Still works**: Open world (all recruitment scenarios), between pulls, in cities

### Impact on GRIP

Minimal. Guild recruitment happens in the open world, cities, and general chat. GRIP's core loop (scan → whisper → invite → post) operates entirely outside instances.

### Recommended Guard

Add a safety check before sends:
```lua
local function IsInRestrictedContent()
    -- Check if in M+ or active encounter
    local _, instanceType = GetInstanceInfo()
    if instanceType == "party" or instanceType == "raid" then
        local difficultyID = select(3, GetInstanceInfo())
        -- Could check for M+ specifically
        return true
    end
    return false
end
```

---

## 5. Secret Values System

The headline Midnight change — "Secret Values" — makes combat data (cooldowns, auras, health values) opaque to addons during encounters. This caused major disruption for combat addons (WeakAuras ended support, Hekili discontinued).

**Impact on GRIP**: Zero. GRIP doesn't read combat data. Guild recruitment is a social/administrative function.

---

## 6. TOC Version

GRIP already has `## Interface: 120001` which is correct for 12.0.1. Addons without the 120000+ interface version won't load.

---

## 7. Other Noteworthy 12.0 Changes

### GuildInvite() Deprecation Path
`GuildInvite()` was deprecated in 10.2.6. The replacement is `C_GuildInfo.Invite()`. While the deprecated function still works in 12.0, it could be removed in a future patch.

**Recommendation**: Add a compat wrapper:
```lua
local function SafeGuildInvite(name)
    if C_GuildInfo and C_GuildInfo.Invite then
        C_GuildInfo.Invite(name)
    else
        GuildInvite(name)
    end
end
```

### UnitPopup Menu System
The legacy `UnitPopup_OnClick` path was already deprecated. GRIP's `Menu.ModifyMenu()` approach for Retail is the correct pattern and continues to work in 12.0.

### Blizzard's Relaxation Post-Launch
After community backlash, Blizzard eased several 12.0 restrictions in hotfixes and 12.0.1. The trend is toward loosening restrictions based on developer feedback, not tightening them. Guild recruitment addons are not in Blizzard's crosshairs.

---

## 8. Action Items for GRIP

| Priority | Item | Effort |
|----------|------|--------|
| **High** | Replace `GetChannelList()` usage in `Recruit/Post.lua` | Medium |
| **Medium** | Remove or replace `ChatFrame_AddMessageEventFilter` for whisper suppression | Low |
| **Low** | Add `C_GuildInfo.Invite()` compat wrapper | Trivial |
| **Low** | Add instance-content guard for sends | Trivial |
| **None** | No changes needed for /who, Club Finder, C_Timer, or core recruitment flow | — |

---

## Sources

- [Patch 12.0.0/API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- [Patch 12.0.0/Planned API changes — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes)
- [Combat Addon Restrictions Eased in Midnight — Icy Veins](https://www.icy-veins.com/wow/news/combat-addon-restrictions-eased-in-midnight/)
- [Blizzard Walks Back Some API Changes — Warcraft Tavern](https://www.warcrafttavern.com/wow/news/blizzard-walks-back-some-api-changes-for-addons-in-midnight/)
- [Lua API Changes for Midnight Launch — Wowhead](https://www.wowhead.com/news/addon-changes-for-midnight-launch-ending-soon-with-release-candidate-coming-380133)
