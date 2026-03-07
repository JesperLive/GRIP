# Changelog

All notable changes to **GRIP – Guild Recruitment Automation** are documented here.

This project follows a lightweight variant of *Keep a Changelog*  
and uses semantic-ish versioning.  
Dates are in **YYYY-MM-DD**.

---

## [1.5.3] - 2026-03-07

### Added
- `/grip perf` slash command — C_AddOnProfiler performance baseline metrics
  (session/recent averages, peak tick, memory usage, tick distribution)

### Fixed
- GRIP.VERSION and README now correctly show 1.5.3 (were stuck at 1.3.0/1.3.1)
- Whisper opt-out detection: fixed scope bug where `senderShort` was nil during
  pendingInvite lookup (variable was defined in a different block)
- Ghost Mode nil-guards added to Invite.lua and Post.lua — prevents errors if
  Ghost table isn't loaded
- Campaign cooldown messages and ghost-post string now routed through AceLocale
  L[] for localization consistency
- Replaced orphaned L[] keys in enUS.lua with actual strings used by Core.lua

### Changed
- Simplified .gitignore for Libs/ tracking — untracked redundant bundled
  AceLocale-3.0 files (packager fetches from external)

---

## [1.5.2] - 2026-03-06

### Fixed
- `/who` returning 0 results no longer triggers false "server throttle" warning —
  Events.lua now detects the WHO_NUM_RESULTS system message and clears pending state
- BigWigsMods packager changelog integration — added manual-changelog directive to
  .pkgmeta pointing at Docs/CHANGELOG.md
- Locale @localization@ keyword fix — removed empty namespace param that caused
  CurseForge API error 1006

---

## [1.5.1] - 2026-03-06

### Fixed
- Locale export fix — removed empty `namespace=""` from @localization@ keywords in
  all locale files (enUS/deDE/frFR/esES) to fix CurseForge API rejection

---

## [1.5.0] - 2026-03-06

### Added
- Full localization infrastructure via AceLocale-3.0 — all 553 user-facing
  strings now route through L[] locale keys (Locale/enUS.lua). German, French,
  and Spanish stub files ready for CurseForge community translations
  (Locale/deDE.lua, Locale/frFR.lua, Locale/esES.lua)
- AceLocale-3.0 library dependency added (.pkgmeta external)
- @localization@ keywords in all locale files for BigWigsMods packager
  integration with CurseForge translation portal

---

## [1.4.0] - 2026-03-06

### Added
- Officer sync v2 protocol — per-collection hash-compare-transfer for
  blacklists (set-union merge) and whisper templates (last-writer-wins with
  5-min clock tolerance). Backward compatible with v1 clients (Sync/Sync.lua)
- FE8 clipboard import/export for blacklists and whisper templates — encode to
  printable string for cross-guild/cross-addon sharing. `/grip export bl|templates`,
  `/grip import` with auto-detect (Sync/ImportExport.lua)
- Template sync opt-in toggle (`config.syncTemplates`, default: on) with
  `/grip sync` status display showing per-collection hashes
- New slash commands: `/grip export`, `/grip import`, `/grip templates`

---

## [1.3.1] - 2026-03-06

### Added
- FUNDING.yml activated with PayPal.me sponsor link
- Sponsor badge added to README.md

---

## [1.3.0] - 2026-03-05

### Added
- Raider.IO integration — optional M+ score filtering for candidates when RIO addon is installed. Fail-open design: all checks pass when RIO is absent. New config keys: `rioMinScore`, `rioShowColumn`. Settings UI with min-score slider and column toggle (DB/DB_RaiderIO.lua, DB/DB_Filters.lua, DB/DB_Potential.lua, UI/UI_Settings.lua, UI/UI_Home.lua)
- Officer blacklist sync — guild officers running GRIP automatically share permanent blacklist entries via AceComm on GUILD channel. Hash-compare-transfer protocol with djb2 hashing, LibSerialize + LibDeflate compression, set-union merge (add-only, never removes). 1-hour broadcast cooldown, 10-second startup delay, pcall-wrapped. `/grip sync on|off|now` (Sync/Sync.lua, Core/Events.lua, Core/Slash.lua)
- Aggressive opt-out tier — optional profanity-based rejection phrases ("fuck off", "piss off", etc.) behind `config.optOutAggressiveEnabled` toggle (default off). `/grip set aggressive on|off`. Per-language `aggressive` tables in Data/OptOut_Phrases.lua
- `origin` parameter passed to `C_FriendList.SendWho()` calls for good-citizen telemetry (Recruit/Who.lua)
- New slash commands: `/grip sync`, `/grip set aggressive`, `/grip set riominscore`, `/grip set riocolumn`
- Library dependencies: AceComm-3.0, LibSerialize, LibDeflate (managed via .pkgmeta externals)

### Changed
- README.md and platform descriptions updated for v1.3.0 feature set
- CHANGELOG.md brought current

---

## [1.0.0] - 2026-03-05

### Changed
- Invite-first mode now whispers on invite delivery (ERR_GUILD_INVITE_S) instead of waiting for accept — players who receive the invite get a follow-up whisper immediately
- First stable release — no code changes from v0.9.0
- Version bumped to 1.0.0 for distribution
- Author field changed to Sataana in TOC metadata
- README updated with full feature list, Stats tab documentation, and missing slash commands
- Platform descriptions refreshed for CurseForge, Wago, and WoWInterface

---

## [0.9.0] - 2026-03-05

### Added
- Hybrid opt-out detection algorithm — SAFE phrases (multi-word, abbreviations) use plain substring matching, RISKY phrases ("no", "stop", "pass", "spam", "nope", "nah") use word-boundary-aware matching via MatchWholeWord() to prevent false positives (Recruit/Whisper.lua)
- French, German, and Spanish opt-out phrase lists in new data file (Data/OptOut_Phrases.lua)
- Language selection config key (optOutLanguages) with Settings UI checkboxes for EN/FR/DE/ES (DB/DB_Init.lua, UI/UI_Settings.lua)

### Changed
- Extracted magic numbers to named constants across codebase (pipeline thresholds, UI dimensions, color values)
- UI color constants consolidated for consistent theming

---

## [0.8.4] - 2026-03-05

### Added
- Hourly activity bucketing — each daily stats bucket now tracks `hours[0..23]` action counts for time-of-day analysis (DB_Init.lua)
- "Peak Hour" display on Stats page — shows busiest hour per time window (today/7d/30d) with action count (UI_Stats.lua)
- `/grip stats [7d|30d]` slash command — print today/7-day/30-day recruitment summary to chat (Slash.lua)
- `/grip stats reset` — clear all stats history (Slash.lua)
- GitHub repository topics for WoWUp Hub discoverability (wow, world-of-warcraft, wow-addon, lua, guild-recruitment, warcraft, retail, midnight)

### Fixed
- Onboarding overlay no longer shows for experienced users — smart-dismiss guard skips if blacklist, potential list, or stats history exists (UI_Home.lua)
- Onboarding overlay no longer bleeds outside GRIP window — page container now clips children (UI.lua)
- Added `_onboardingDismissed` to DEFAULT_DB_CHAR schema for explicit documentation (DB_Init.lua)

---

## [0.8.3] - 2026-03-05

### Added
- Daily recruitment statistics tracking — 30-day rolling history stored per-character in SavedVariables, auto-pruned on login (DB_Init.lua)
- `RecordStat()` helper with hooks across the full pipeline: whispers sent, invites sent, accepted, declined, opt-outs, posts sent, scans completed (Whisper.lua, Invite.lua, Post.lua, Events.lua)
- New "Stats" tab (4th tab) showing Today / Last 7 Days / Last 30 Days summaries with per-metric counters and accept rate (UI_Stats.lua, UI.lua)

---

## [0.8.2] - 2026-03-05

### Improved
- Guild link fallback now prints a one-time per-session notice explaining why `{guildlink}` resolved to plain text, with actionable steps (open Communities window, check Guild Finder listing, use `/grip link`) (Utils.lua)
- `/grip status` now shows perm/temp blacklist split and conditional breakdown of permanent entries by reason (opt-out, no-response, other) (Slash.lua)

### Added
- First-run onboarding overlay on Home page — dismissible setup guide shown once until "Got it!" is clicked, persisted via `_onboardingDismissed` config flag (UI_Home.lua)
- Documentation comment for `NormalizeWhoCounts` explaining the return-value swap detection (Who.lua)

---

## [0.8.1] - 2026-03-05

### Changed
- Expanded opt-out phrase detection with 9 new entries: "nty" (abbreviation), polite rejections ("i'll pass", "ill pass", "not for me", "thanks but no thanks"), hostile responses ("go away", "fuck off", "piss off"), and WoW-specific ("just looking") (Whisper.lua)
- Documented opt-out detection design rationale and false positive trade-offs in CLAUDE.md

---

## [0.8.0] - 2026-03-05

### Added
- Invite-first safety toggle — send guild invite before whisper, only whispers players who accept the invite. Reduces Silence penalty risk from players with "Block Guild Invites" enabled. Off by default. (DB_Init.lua, Invite.lua, Whisper.lua, UI_Settings.lua, Slash.lua)

### Changed
- All chat sends (whisper, channel post) now check `C_ChatInfo.InChatMessagingLockdown()` before sending, silently skipping when the player is chat-restricted (Recruit/Whisper.lua, Recruit/Post.lua, Recruit/Invite.lua)
- Max level clamp corrected from 100 to 90 for Midnight level cap (Slash.lua, UI_Settings.lua, Who.lua)

### Fixed
- Ghost Mode `/who` timeout closure now uses reference equality to prevent stale session callbacks (Who.lua)
- Variable shadowing in opt-out whisper name resolution fixed (Whisper.lua)
- Post target regex no longer matches loose hyphenated words, preventing false-positive post attribution (Post.lua)

---

## [0.7.0] - 2026-03-04

### Added
- Slider widgets for Ghost Mode session max / cooldown settings (UI_Settings.lua)
- Ghost session lock — pipeline slash commands, Home buttons, minimap menu items, and Settings filters locked during active Ghost session (GhostMode.lua, Slash.lua, UI_Home.lua, Minimap.lua, UI_Settings.lua)

### Changed
- Right-click "Invite to Guild" now checks blacklist gate before sending invite (UnitPopupInvite.lua)
- Whisper ticker skips candidates when invite can't follow due to combat lockdown (Whisper.lua)
- /who window flash suppressed during automated scans via FriendsFrame hide/show guard (Who.lua)
- Suppress whisper echo checkbox added to Settings page (UI_Settings.lua)
- Removed dead GetRealmToken() from Who.lua
- Cleaned up misleading "Phase 1 backward compat" / "legacy" comments across codebase (BC1–BC6)
- Fixed stale comments in DB_Init, UnitPopupInvite, Core (SC1–SC3)

### Fixed
- Edit box text no longer reverts on focus loss — dirty tracking rewritten with programmatic-set flag (UI_Widgets.lua, UI.lua)
- /who panel no longer flashes despite suppressWhoUI being enabled (Who.lua)
- Whisper echo suppression now works correctly — filter registration timing and buffer matching fixed (Utils.lua, Events.lua)
- WASD movement no longer blocked while GRIP UI is open — removed SetPropagateKeyboardInput(false) from main frame (UI.lua)

---

## [0.6.0] - 2026-03-04

### Changed
- Migrated Potential list (UI_Home.lua) and Blacklist panel (UI_Home_Blacklist.lua) from manual FauxScrollFrame to WowScrollBoxList + DataProvider pattern — automatic row recycling, no manual pool management
- Updated CLAUDE.md UI Architecture section to document ScrollBox patterns

---

## [0.5.0-beta] - 2026-03-02

### Added
- Daily whisper cap (500/day default) with 80% warning, calendar-date reset, `/grip set dailycap`
- Opt-out response detection — auto-blacklists candidates who reply "no thanks", "stop", etc.
- Whisper template variety — multiple messages with sequential/random rotation
- Sound feedback — optional audio cues for queue complete, invite accepted, scan results, cap warning
- Multi-template whisper editor with navigation, add/remove, rotation selector
- /grip link command — prints current guild name and Guild Finder link for troubleshooting
- EnsureDB now enforces 10-template cap on whisperMessages (defensive against manual SV edits)
- Campaign cooldown — sliding-window timer with soft warning (30 min) and hard auto-pause (60 min), gap reset after inactivity, `/grip set cooldown`
- Ghost Mode (experimental, disabled by default) — invisible overlay frame captures hardware events to drain a universal action queue. Full pipeline: auto-scan → auto-whisper → auto-invite → auto-post. 1-hour max session, 10-minute persistent cooldown (survives /reload, relog, restart). `/grip ghost start|stop|status`
- Ghost Mode UX — Settings page checkbox + session/cooldown config, Home page session status strip with Start/Stop button and live timer
- Addon compartment right-click dropdown — 5 quick actions (Toggle UI, Status, Build Scan Queue, Ghost toggle, Whisper toggle) via MenuUtil context menu
- Account-wide blacklist — GRIPDB (account-wide: blacklists, no-response counters) + GRIPDB_CHAR (per-character: config, potential, filters). Automatic migration from old single-SV schema via MigrateToSplitSV()
- Frame pooling for Home page potential + blacklist rows (CreateFramePool)

### Changed
- Zone system: removed dead `STATIC_ZONES_BY_GROUP`, added expansion grouping, seasonal detection, improved exclusion rules, `SeedZones` fix
- `scanMaxLevel` default corrected from 80 to 90
- Stripped revision header bloat from all source files; removed dead code (`U.AnySelected()`)
- Upvalue localization — hot-path WoW API and Lua stdlib globals localized as file-top upvalues across all 22 .lua modules
- SavedVariables split: GRIPDB is now account-wide (## SavedVariables), GRIPDB_CHAR is per-character (## SavedVariablesPerCharacter)

### Fixed
- `RemovePotential(fullName)` now returns `true|false` (contract alignment for purge/cleanup paths).
- `GuildInvite()` → `C_GuildInfo.Invite()` deprecated API migration with compat wrapper
- `GetGuildName()` removed dead `C_GuildInfo.GetGuildInfo` reference, improved cache warming via guild events
- `GetGuildFinderLink()` added cache with 5-min TTL, suppressed debug spam
- `ApplyTemplate()` Lua gsub count leak fixed

### Known Limitations / Future
- Ghost Mode is functional but disabled by default. Enable in Settings and start via `/grip ghost start` or the Home page button.
- ChatThrottleLib runtime detection implemented (Utils.lua). Routes WHISPER through CTL when present; falls back gracefully when absent.

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