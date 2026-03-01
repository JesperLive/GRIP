# Club Finder / Guild Finder API — Complete Reference for GRIP

> Compiled March 2026. Covers Retail / Midnight (12.0+).

---

## 1. The Club System Architecture

### What Is a "Club"?

Since Patch 8.0.1 (BfA), WoW unifies guilds and communities under a "Club" abstraction:

- **Guilds** → character-specific, single-realm (now cross-realm since TWW)
- **Battle.net Communities** → cross-realm, linked to Battle.net account
- **Communities** → Other community types

The `C_Club` API provides a unified interface for managing all these types.

### Key Identifiers

| Identifier | Type | Source | Used For |
|-----------|------|--------|----------|
| `clubId` | string | `C_Club.GetGuildClubId()` | General club operations |
| `clubFinderGUID` | string | From `RecruitingClubInfo` table | Guild Finder links |

These are interchangeable for lookup but serve different API contexts.

---

## 2. GRIP's Guild Link Pipeline

GRIP generates `{guildlink}` tokens through this chain (in `Core/Utils.lua`):

```
GetGuildFinderLink()
  ├─ 1. Check C_Club.GetGuildClubId exists
  ├─ 2. Ensure Blizzard_ClubFinder is loaded (_TryLoadClubFinder)
  ├─ 3. pcall(C_Club.GetGuildClubId) → clubId
  ├─ 4. pcall(ClubFinderGetCurrentClubListingInfo, clubId) → listing
  ├─ 5. Extract listing.clubFinderGUID + listing.name
  ├─ 6. pcall(GetClubFinderLink, clubFinderGUID, name) → link
  └─ Return link string, or fallback to guild name, or ""
```

Every step can fail, which is why there are so many fallback paths.

---

## 3. API Details

### C_Club.GetGuildClubId()

```lua
local clubId = C_Club.GetGuildClubId()
```

- **Returns**: `string` or `nil`
- **Returns nil when**:
  - Player is not in a guild
  - Called before `INITIAL_CLUBS_LOADED` event fires (login timing)
  - Called during `ADDON_LOADED` (too early)
  - Rare: guild Club status not yet synchronized by backend

**Best practice**: Wait for `INITIAL_CLUBS_LOADED` or `PLAYER_GUILD_UPDATE` before calling.

**GRIP's approach**: Wraps in `pcall()`, falls back to guild name from `GetGuildName()` cache.

---

### ClubFinderGetCurrentClubListingInfo(clubId)

```lua
local listing = ClubFinderGetCurrentClubListingInfo(clubId)
```

**This is a GLOBAL function**, not part of the `C_ClubFinder` namespace. It was introduced in Patch 8.2.5.

**Requires**: `Blizzard_ClubFinder` addon must be loaded first.

**Returns**: `RecruitingClubInfo` table or `nil`

**Returns nil when**:
1. Guild has no active recruitment listing in Guild Finder
2. `Blizzard_ClubFinder` addon isn't loaded
3. Local cache hasn't been populated yet (timing)
4. Cross-realm/faction visibility restrictions
5. Guild listing expired (they have time limits)

### RecruitingClubInfo Structure

```lua
{
    clubFinderGUID = "ClubFinder-1-19160-1598-53720920",
    clubId = "15554351",
    name = "Guild Name",
    comment = "Recruitment message text",
    guildLeader = "LeaderName",
    isGuild = true,
    numActiveMembers = 42,
    minILvl = 0,
    isCrossFaction = false,         -- added 9.2.5
    emblemInfo = <number>,
    tabardInfo = <GuildTabardInfo>,  -- optional
    recruitingSpecIds = {62, 253},   -- array of spec IDs
    recruitmentFlags = <number>,     -- bitfield
    localeSet = false,               -- added 8.3.0
    recruitmentLocale = 0,           -- added 8.3.0
    lastPosterGUID = "Player-...",   -- added 8.2.5
    lastUpdatedTime = <number>,      -- added 8.2.5
    cached = <number>,
    cacheRequested = <number>,
}
```

---

### GetClubFinderLink(clubFinderGUID, name)

```lua
local link = GetClubFinderLink(listing.clubFinderGUID, listing.name)
```

**Returns**: A formatted clickable hyperlink string:
```
|cffffd100|HclubFinder:ClubFinder-1-19160-1598-53720920|h[Guild: Happy Leveling]|h|r
```

**Format breakdown**:
- `|cffffd100` — Gold color code
- `|HclubFinder:` — Hyperlink type identifier
- `ClubFinder-...` — The clubFinderGUID
- `|h[Guild: Name]|h` — Display text
- `|r` — Reset formatting

**Character length**: ~60-120 characters depending on guild name. A guild named "The Magnificent Dwarven Brewmasters of Khaz-Modan" would produce a very long link.

**GRIP's handling**: The `ApplyTemplate()` function in `Utils.lua` treats `{guildlink}` as "non-droppable" — it reserves tail space during truncation so the link always survives the 250-char limit.

---

### Clickability and Compatibility

| Chat Channel | Link Works? |
|-------------|-------------|
| Whisper | YES — clickable |
| Trade/General | YES — clickable |
| Guild chat | YES — clickable |
| Party/Raid | YES — clickable |
| Instance chat | YES — clickable |
| Cross-realm | YES — links are realm-independent |
| Cross-faction | NO — filtered out |

When a player clicks the link, it opens the Guild Finder UI showing that guild's listing with an "Apply" button.

---

## 4. Loading Blizzard_ClubFinder

### Why Is It Load-On-Demand?

`Blizzard_ClubFinder` is marked `LoadOnDemand=1` in its TOC to:
- Reduce login overhead (most players don't open Guild Finder often)
- Lower memory footprint until needed
- Only initialize when relevant features are accessed

### GRIP's Loading Approach

```lua
local function _TryLoadClubFinder()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        if not C_AddOns.IsAddOnLoaded("Blizzard_ClubFinder") then
            pcall(C_AddOns.LoadAddOn, "Blizzard_ClubFinder")
        end
    elseif IsAddOnLoaded then  -- Legacy fallback
        if not IsAddOnLoaded("Blizzard_ClubFinder") then
            pcall(LoadAddOn, "Blizzard_ClubFinder")
        end
    end
end
```

### Race Condition Warning

**Do NOT call `LoadAddOn()` inside an `ADDON_LOADED` event handler.** The newly loaded addon's own `ADDON_LOADED` event may not fire because new event registrations don't take effect until the current event dispatch cycle completes.

**Safe alternatives**:
- Call from a `C_Timer.After(0.1, ...)` deferred callback
- Call from `PLAYER_LOGIN` handler (fires after all ADDON_LOADED)
- Call on first use (GRIP's approach — loads when first building a guild link)

### Side Effects of Loading

- `ClubFinderGetCurrentClubListingInfo()` global function becomes available
- `GetClubFinderLink()` global function becomes available
- Club Finder event handlers registered
- UI frames created (not shown)
- Generally safe — no dangerous state changes or performance impact

---

## 5. Why It's Flaky — Root Causes

### Cause 1: Guild Must Be Actively Listed

The #1 reason `ClubFinderGetCurrentClubListingInfo()` returns nil: **the guild doesn't have an active recruitment listing**. Many guild leaders never post to the Guild Finder, or their listing expired.

**How to verify**: Open the Guild Finder UI (J → Guild & Communities → Your Guild → Recruitment). If there's no active listing, the API will always return nil.

### Cause 2: Cache Not Populated

Even with an active listing, the local client cache may not have the data yet. The cache is populated asynchronously and may lag behind.

**GRIP's mitigation**: Multiple `pcall()` wrappers and fallback to plain guild name.

### Cause 3: Login Timing

During the first 5-30 seconds after login:
- `C_Club.GetGuildClubId()` may return nil
- `INITIAL_CLUBS_LOADED` hasn't fired yet
- Club Finder data hasn't synchronized

**GRIP's mitigation**: Caches last known guild name. Falls back gracefully.

### Cause 4: Addon Load State

If `Blizzard_ClubFinder` isn't loaded yet, the global functions don't exist. GRIP's `_TryLoadClubFinder()` handles this, but loading takes a frame or two.

### Cause 5: Cross-Faction Visibility

Cross-faction guild listings exist in the API but may be filtered in certain contexts. If a guild is cross-faction (since 9.2.5), the link might not be visible to all players.

---

## 6. GRIP's Fallback Chain

```
Attempt clickable Club Finder link
  ├─ Success → "|cffffd100|HclubFinder:...|h[Guild: Name]|h|r"
  │
  ├─ ClubFinder unavailable → Fall back to guild name
  │   └─ "My Guild Name"
  │
  ├─ Not in guild → Fall back to generic text
  │   └─ "your guild"
  │
  └─ All fail → Empty string ""
```

### Template Integration

The `ApplyTemplate()` function:
1. Resolves `{guildlink}` → clickable link or fallback
2. Resolves `{guild}` → guild name
3. Resolves `{player}` / `{name}` → candidate's short name
4. Truncates to 250 chars with link protection

**Non-droppable link strategy**: If the message exceeds 250 chars after template expansion, GRIP reserves tail space for the guild link. The message text before the link gets truncated, but the link itself is always preserved.

---

## 7. Alternative Guild Link Approaches

### Manual Hyperlink Construction (Not Recommended)

```lua
local link = "|cFFFFD100|HclubFinder:" .. clubFinderGUID .. "|h[" .. guildName .. "]|h|r"
```

Advantages: Doesn't require `Blizzard_ClubFinder` loaded.
Disadvantages: Format may change between patches. Fragile.

### Guild Achievement Links

```lua
GetAchievementLink(achievementID)
```
Not a direct guild recruitment link. Less useful.

### Plain Text Fallback

When all API paths fail, GRIP falls back to just using the guild name as text. Players can then manually search for the guild in the Guild Finder.

---

## 8. Known Issue: GuildApplicantsFix

The `C_ClubFinder.RequestApplicantList()` function sometimes fails silently — it doesn't fire `CLUB_FINDER_APPLICATIONS_UPDATED`. A community addon "GuildApplicantsFix" exists to work around this by manually firing the event on `GUILD_ROSTER_UPDATE`.

This doesn't directly affect GRIP's link generation, but it's relevant context for the Club Finder API's general unreliability.

---

## 9. Recommendations for GRIP

1. **Keep the current fallback chain** — it's robust and handles all failure modes
2. **Don't cache guild links indefinitely** — the listing could expire or change
3. **Refresh link data on `CLUB_FINDER_RECRUITS_UPDATED`** event if registered
4. **Document for users**: "Your guild must have an active Guild Finder listing for {guildlink} to generate a clickable link"
5. **Consider adding a `/grip link` command** that shows what {guildlink} resolves to, for debugging
6. **Monitor link character length** — very long guild names can eat significant message budget

---

## Sources

- [C_Club.GetGuildClubId — Wowpedia](https://wowpedia.fandom.com/wiki/API_C_Club.GetGuildClubId)
- [C_ClubFinder Namespace — Wowpedia](https://wowpedia.fandom.com/wiki/Category:API_namespaces/C_ClubFinder)
- [Hyperlinks — Wowpedia](https://wowpedia.fandom.com/wiki/Hyperlinks)
- [C_AddOns.LoadAddOn — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_AddOns.LoadAddOn)
- [GuildApplicantsFix — GitHub](https://github.com/Xatan/GuildApplicantsFix)
- [Cross-Realm Guilds — Wowhead](https://www.wowhead.com/news/cross-realm-guilds-available-with-the-war-within-pre-patch-345350)
