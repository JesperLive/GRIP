# Claude Code Prompt — GRIP Codebase Cleanup

> Copy-paste this entire prompt into Claude Code.

---

## Context

GRIP is a WoW guild recruitment addon (v0.4.0, Interface 120001). We've been building rapidly and the codebase has accumulated header bloat (revision changelogs in every file), a couple of dead code artifacts, and inconsistent inline comments. Now that we use git, the revision history in source files is pure bloat.

**Before starting, read:** `Claude/Research_08_Codebase_Cleanup_March2026.md` for the full audit.

## Task Overview

You will:
1. Replace all rev-history header blocks with clean 2-line headers
2. Remove two pieces of dead code
3. Clean up the TOC file
4. Clean up Bindings.xml
5. Tidy a handful of inline comments

**Rules:**
- Do NOT change any functional code. Zero behavior changes.
- Do NOT reorganize, reformat, or refactor anything.
- Do NOT touch the `Claude/` folder or `CLAUDE.md` — those are already updated.
- Preserve blank lines between the new header and the first `local` statement.
- Every file must still parse as valid Lua (or XML for Bindings.xml).

---

## Task 1: Replace Header Blocks

For **every `.lua` file listed below**, remove the entire revision-history comment block at the top (everything from line 1 down to and including the last `-- CHANGED (Rev N):` block or `--` blank comment line before the first real code line). Replace with exactly the 2-line header shown.

**Keep one blank line between the header and the first code line.**

### Core/Core.lua
```lua
-- GRIP: Core
-- Bootstrap, version, shared state, logger wrapper, keybind entry points.
```
(Remove lines 1–47 approximately — everything before `local ADDON_NAME, GRIP = ...`)

### Core/Debug.lua
```lua
-- GRIP: Debug
-- Logger capture override + SavedVariables ring buffer for debug persistence.
```

### Core/Utils.lua
```lua
-- GRIP: Utils
-- Shared helpers: template engine, chat compat, whisper echo suppression, pattern matching.
```

### Core/GhostMode.lua
```lua
-- GRIP: Ghost Mode
-- Optional hardware-event gated chat send queue (Phase 1: CHANNEL only).
```

### Core/Slash.lua
```lua
-- GRIP: Slash
-- /grip command handler and all subcommands.
```

### Core/Events.lua
```lua
-- GRIP: Events
-- Event frame wiring: ADDON_LOADED, PLAYER_LOGIN, WHO_LIST_UPDATE, system messages.
```

### Data/Maps_Zones.lua
```lua
-- GRIP: Maps & Zones (Static Data)
-- Shipped zone list, exclusion patterns, and exclusion exact-match list.
```

### DB/DB_Util.lua
```lua
-- GRIP: DB Utilities
-- Table merge, list helpers, filter pruning.
```

### DB/DB_Zones.lua
```lua
-- GRIP: DB Zones
-- Zone gathering, deep scan, exclusion building, export.
```

### DB/DB_Init.lua
```lua
-- GRIP: DB Init
-- SavedVariables defaults, EnsureDB, seeding (classes/races/zones), schema migration.
```

### DB/DB_Blacklist.lua
```lua
-- GRIP: DB Blacklist
-- Temp/perm blacklist, BL_ExecutionGate (last-line defense), no-response counters.
```

### DB/DB_Filters.lua
```lua
-- GRIP: DB Filters
-- Candidate filtering: zone/race/class allowlists applied to /who results.
```

### DB/DB_Potential.lua
```lua
-- GRIP: DB Potential
-- Potential candidate list: add, remove, finalize lifecycle.
```

### Recruit/Who.lua
```lua
-- GRIP: Who Scanner
-- /who queue builder, bracket expansion, result ingestion, blacklist enforcement at scan time.
```

### Recruit/Whisper.lua
```lua
-- GRIP: Whisper Queue
-- Whisper queue management, template rendering, rate-limited sending.
```

### Recruit/Invite.lua
```lua
-- GRIP: Invite Pipeline
-- Hardware-event gated guild invite with whisper+invite combo, no-response escalation.
```

### Recruit/Post.lua
```lua
-- GRIP: Post Scheduler
-- Trade/General channel post queue, scheduler, hardware-event gated sending.
```

### Hooks/UnitPopupInvite.lua
```lua
-- GRIP: Unit Popup Hook
-- Right-click "Invite to Guild (GRIP)" context menu via Menu API + legacy UnitPopup fallback.
```

### UI/UI_Widgets.lua
```lua
-- GRIP: UI Widgets
-- Reusable constructors: checkboxes, multiline edits, checklists, scroll pages.
```

### UI/UI_Home.lua
```lua
-- GRIP: UI Home Page
-- Potential candidate list, blacklist panel, action buttons, row context menu.
```

### UI/UI_Settings.lua
```lua
-- GRIP: UI Settings Page
-- Level range, filter checklists, whisper editor with byte-budget enforcement.
```

### UI/UI_Ads.lua
```lua
-- GRIP: UI Ads Page
-- Trade/General message editors, post scheduler config, queue/post buttons.
```

### UI/UI.lua
```lua
-- GRIP: UI Controller
-- Main frame, tabs, page routing, resize handling, UpdateUI coalescing.
```

### UI/Minimap.lua
```lua
-- GRIP: Minimap Button
-- Minimap ring button with drag-to-reposition and click shortcuts.
```

---

## Task 2: Clean TOC File

In `GRIP.toc`:
- Remove `## Rev 10` (line 1)
- Remove `## CHANGED (Rev 10): ...` (line 8)
- Simplify each section separator from 3 lines to 1 line. Replace:
```
# ============================================================================
# Section description
# ============================================================================
```
with:
```
# -- Section description
```

The resulting TOC should look like:
```
## Interface: 120001
## Title: GRIP – Guild Recruitment Automation
## Notes: /who scan for unguilded players, whisper/invite queues, and Trade/General post queue (queued; click/keybind to send).
## Author: GRIP
## Version: 0.4.0
## SavedVariables: GRIPDB

# -- Core bootstrap (must load first)
Core/Core.lua
Core/Debug.lua
Core/Utils.lua

# -- Optional modules (inert unless enabled in config)
Core/GhostMode.lua

# -- Static data
Data/Maps_Zones.lua

# -- Database layer
DB/DB_Util.lua
DB/DB_Zones.lua
DB/DB_Init.lua
DB/DB_Blacklist.lua

# -- Hooks (depend on DB + gate)
Hooks/UnitPopupInvite.lua

DB/DB_Filters.lua
DB/DB_Potential.lua

# -- Recruitment pipeline (who → whisper → invite → post)
Recruit/Who.lua
Recruit/Whisper.lua
Recruit/Invite.lua
Recruit/Post.lua

# -- UI layer
UI/UI_Widgets.lua
UI/UI_Home.lua
UI/UI_Settings.lua
UI/UI_Ads.lua
UI/UI.lua
UI/Minimap.lua

# -- Commands + events (depend on everything above)
Core/Slash.lua
Core/Events.lua
```

---

## Task 3: Clean Bindings.xml

In `Bindings.xml`:
- Remove `<!-- Rev 3 -->` (line 1)
- Remove the multi-line NOTE comment block (lines 3–9, the block about BindingHeader and taint).

Keep the `<Bindings>` tag and all four `<Binding>` elements intact.

---

## Task 4: Remove Dead Code

### 4a. Remove `STATIC_ZONES_BY_GROUP` from Data/Maps_Zones.lua
Find and remove the entire block (approximately lines 215–218):
```lua
-- Optional scaffolding for future: categorizing zones (e.g. by expansion). Not used yet.
GRIP.STATIC_ZONES_BY_GROUP = GRIP.STATIC_ZONES_BY_GROUP or {
  -- ["The War Within"] = { "Isle of Dorn", "The Ringing Deeps", "Hallowfall", "Azj-Kahet" },
}
```
This is never referenced anywhere in the codebase.

### 4b. Remove `U.AnySelected()` from DB/DB_Util.lua
Find and remove:
```lua
function U.AnySelected(t)
  ...
end
```
This is never called. `DB_Filters.lua` and `Who.lua` define their own local copies.

---

## Task 5: Tidy Inline Comments

In `Core/Core.lua`, find and remove this comment (it's on the line above `GRIP.state = {` or near it):
```lua
-- Shared runtime state (safe across files via the same addon table)
```
The addon table pattern is self-evident and documented in CLAUDE.md.

Also, throughout the codebase, if you encounter any remaining `-- (Rev N change)` or `-- (Rev N)` inline annotations within code blocks (not at the top of files), remove them. These are scattered remnants. But do NOT touch comments that explain *what* or *why* — only remove the ones that just say which revision something was added in.

---

## Output Format

When done, provide output in this exact format:

```
## Summary
Codebase cleanup: strip rev-history headers, remove dead code, simplify TOC

## Description
- Replaced revision-history comment blocks in all 24 .lua files with standardized 2-line headers
- Simplified GRIP.toc section separators and removed rev metadata
- Cleaned Bindings.xml of rev comment and stale NOTE block
- Removed dead code: STATIC_ZONES_BY_GROUP (Maps_Zones.lua), U.AnySelected (DB_Util.lua)
- Removed stale inline (Rev N) annotations

Zero functional changes. All modifications are comments, dead code, and formatting only.

## Files Modified
[list every file you touched]

## Verification
- [ ] All .lua files parse without syntax errors
- [ ] TOC load order unchanged
- [ ] No functional code was modified
- [ ] Bindings.xml is valid XML
- [ ] Dead code removals confirmed: STATIC_ZONES_BY_GROUP not referenced, U.AnySelected not called

## Lines Removed (approximate)
[total count]
```
