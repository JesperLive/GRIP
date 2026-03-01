<!-- Rev 5 -->
# Changelog

All notable changes to **GRIP – Guild Recruitment Automation** are documented here.

This project follows a lightweight variant of *Keep a Changelog*  
and uses semantic-ish versioning.  
Dates are in **YYYY-MM-DD**.

---

## [Unreleased]

### Added
- `Docs/SavedVariables_Schema.md` (source of truth for `GRIPDB`)
- `Docs/Public_API.md`
- `Docs/Execution_Gate.md`
- `Docs/GhostMode.md`
- Updated canonical state doc with verified TOC order + revs (see `Docs/GRIP_Canonical_State.md`)

### Fixed
- `RemovePotential(fullName)` now returns `true|false` (contract alignment for purge/cleanup paths).

### Planned / In Progress
- Align Home page “Blacklist…” UI with canonical SV schema:
  - Temp blacklist = expiry timestamps
  - Permanent blacklist = `{at, reason}` metadata entries
- Ghost Mode: finish integration wiring and call signature alignment (keep disabled until complete).
- Optional: global right-click invite hook (outside GRIP UI) for same-realm names, while preserving Blizzard restrictions.
- Additional queue discipline improvements
- Further nil-safety hardening across remaining modules
- Minor performance polish

---

## [0.4.0] - 2026-02-26

### Added
- **Minimap button**
  - Left-click: toggle UI (Home)
  - Middle-click: Settings
  - Right-click: Ads
  - Drag to reposition
  - `/grip minimap on|off|toggle`
- All/None shortcuts for Zones/Races/Classes allowlists.
- Scrollable Settings and Ads pages (prevents layout overflow).
- Automatic excluded-zone building:
  - Encounter Journal instances
  - Battlegrounds
  - Manual excludes/pattern patterns
- Static zone list (`Maps_Zones.lua`) used for seeding zone selections.
- `/grip zones export` — writes copy/paste-ready Lua table to `GRIPDB.lists.zonesExportLua`.
- Persisted debug capture (SavedVariables) with configurable cap.

### Changed
- Default `/who` minimum interval set to 15s to align with UI cooldown.
- Edit boxes now use “dirty” tracking to prevent ticker overwrites.
- `/who` ingestion now normalizes `C_FriendList.GetWhoInfo()` fields for correct race/class/zone consistency.
- Minimap drag logic now commits SavedVariables only on drag stop (reduced churn).
- UI now hardens against DB-not-ready states (graceful disable instead of hard error).
- Logger refactor:
  - Introduced `GRIP.Logger` wrapper
  - Plain-text persistence for SavedVariables
  - Debug window resolution caching

### Refactored
- Split monolithic `DB.lua` into modular DB files:
  - `DB_Init`
  - `DB_Zones`
  - `DB_Filters`
  - `DB_Blacklist`
  - `DB_Potential`
  - `DB_Util`
- Split `UI.lua` into page modules:
  - `UI_Home.lua`
  - `UI_Settings.lua`
  - `UI_Ads.lua`
  - `UI.lua` retained as controller

### Fixed
- Apply+Rebuild no longer reverts Max/Step on first click (ticker overwrite race resolved).
- Whisper/Ads message Save reliably persists.
- Append `{guildlink}` no longer flashes and disappears.
- Classes list no longer includes “Adventurer”; filter keys pruned correctly.
- Zones list pre-populates from map API (fallback to current zone if enumeration fails).
- Whisper UI status no longer shows premature failure before confirmation.
- Invite failure attribution hardened (prevents mis-attribution when multiple candidates pending).

---

## [0.3.0] - 2026-02-26

### Added
- Multi-page minimal UI:
  - **Home** (candidate list + actions)
  - **Settings** (scan & filter config + whisper message)
  - **Ads** (General/Trade advert config + scheduler queue)

- Structured whisper queue
- Invite tracking + blacklist cooldown
- Post scheduler (queues only; hardware-triggered send)