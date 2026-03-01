# Research 08 — GRIP Codebase Cleanup Audit (March 2026)

> **Compiled:** 2026-03-01
> **GRIP version:** 0.4.0

---

## 1. Header Bloat — Revision History Comments

Every `.lua` file carries a multi-line revision changelog at the top that grew with each rev. These served a purpose during rapid development but now that GRIP uses git, they're pure bloat. The TOC file has the same pattern.

### What to keep per file
Each file should have **exactly** a 2-line header:
```lua
-- GRIP: <Module Name>
-- <One-line description of what this module does>
```

### What to remove
All `-- Rev N`, `-- CHANGED (Rev N):`, `-- CHANGED:`, multi-line revision history blocks, and the `-- Retail (Midnight) 12.0.1+ / Interface 120001` line (that info is in the TOC).

### Files affected (all 21 .lua files + TOC + Bindings.xml)

| File | Header lines to remove | Approx lines saved |
|------|----------------------|-------------------|
| Core/Core.lua | Lines 1–47 (Rev 1–8 changelog) | ~47 |
| Core/Debug.lua | Rev header block | ~15 |
| Core/Utils.lua | Rev header block | ~30 |
| Core/GhostMode.lua | Rev header block | ~10 |
| Core/Slash.lua | Rev header block | ~12 |
| Core/Events.lua | Rev header block | ~15 |
| Data/Maps_Zones.lua | Rev header block | ~8 |
| DB/DB_Util.lua | Rev header block | ~8 |
| DB/DB_Zones.lua | Rev header block | ~10 |
| DB/DB_Init.lua | Rev header block | ~15 |
| DB/DB_Blacklist.lua | Rev header block | ~20 |
| DB/DB_Filters.lua | Rev header block | ~8 |
| DB/DB_Potential.lua | Rev header block | ~10 |
| Recruit/Who.lua | Rev header block | ~20 |
| Recruit/Whisper.lua | Lines 1–24 (Rev 1–7 changelog) | ~24 |
| Recruit/Invite.lua | Lines 1–41 (Rev 1–11 changelog) | ~41 |
| Recruit/Post.lua | Rev header block | ~20 |
| Hooks/UnitPopupInvite.lua | Rev header block | ~12 |
| UI/UI_Widgets.lua | Rev header block | ~15 |
| UI/UI_Home.lua | Lines 1–23 (Rev 17–19 changelog) | ~23 |
| UI/UI_Settings.lua | Rev header block | ~10 |
| UI/UI_Ads.lua | Rev header block | ~12 |
| UI/UI.lua | Rev header block | ~15 |
| UI/Minimap.lua | Rev header block | ~10 |
| GRIP.toc | `## Rev 10`, `## CHANGED (Rev 10):` line | ~2 |
| Bindings.xml | `<!-- Rev 3 -->` line | ~1 |

**Total estimated savings:** ~400+ lines of comments

---

## 2. Dead / Unused Code

### 2a. `GRIP.STATIC_ZONES_BY_GROUP` — Dead scaffolding
- **Location:** `Data/Maps_Zones.lua` lines 215–218
- **Status:** Defined with a commented-out example, never referenced anywhere else in the codebase.
- **Action:** Remove entirely.

### 2b. `U.AnySelected()` in DB_Util.lua — Never called
- **Location:** `DB/DB_Util.lua` line 67
- **Status:** Defined as `U.AnySelected(t)` but never called. `DB_Filters.lua` and `Who.lua` both define their own `local function AnySelected(t)` instead.
- **Action:** Remove from DB_Util.lua.

---

## 3. Duplicate Local Helpers (NOT bloat — intentional pattern)

These functions are duplicated across files but this is **by design** in WoW addon development. Each file is a separate scope, and local helpers like `GetCfg()`, `IsBlank()`, `HasDB()`, `GetPotential()` are intentionally localized to avoid cross-file coupling. They're tiny (2–3 lines each) and the duplication is the WoW addon convention.

| Helper | Files | Keep? |
|--------|-------|-------|
| `local function GetCfg()` | 7 files | ✅ Keep — standard WoW addon pattern |
| `local function IsBlank(s)` | 6 files | ✅ Keep — same pattern |
| `local function GetPotential()` | 2 files | ✅ Keep |
| `local function HasDB()` | 3 files | ✅ Keep |
| `local function AnySelected(t)` | DB_Filters.lua, Who.lua | ✅ Keep (local copies) |

**Do NOT centralize these.** In WoW's addon environment, reducing local helpers to shared functions on the addon table adds load-order dependencies and makes each module less self-contained. The current approach is correct.

---

## 4. Inline Comments to Revise

### 4a. Comments that should be REMOVED (stale or obvious)
- `-- Shared runtime state (safe across files via the same addon table)` in Core.lua — Obvious from context; the addon table pattern is documented in CLAUDE.md.
- Any `-- (Rev N change)` inline annotations within code blocks.

### 4b. Comments that should stay
- Hardware-event restriction notes (`-- #hwevent`, `-- hardware-event restricted`) — these are safety-critical reminders.
- `-- last-line defense` / `-- defense-in-depth` near BL_ExecutionGate calls — important architectural markers.
- Section dividers (`-- ============`) within long files — they aid navigation.

### 4c. Comments to ADD or improve
- TOC section headers are fine but overly loud (6 lines of `=====` per section). Could simplify to single-line `# --- Section ---` comments.

---

## 5. TOC File Cleanup

The TOC has verbose section separators (3-line blocks with `========`). These can be simplified.

Current:
```
# ============================================================================
# Core bootstrap (must load first)
# ============================================================================
```

Replace with:
```
# -- Core bootstrap (must load first)
```

---

## Summary of Safe Changes

| # | Category | Change | Risk | Lines saved |
|---|----------|--------|------|-------------|
| 1 | Headers | Replace all rev-history blocks with 2-line headers | None — comments only | ~400 |
| 2 | Dead code | Remove `STATIC_ZONES_BY_GROUP` scaffolding | None — never referenced | ~4 |
| 3 | Dead code | Remove `U.AnySelected()` from DB_Util.lua | None — never called | ~6 |
| 4 | Comments | Remove stale inline `(Rev N)` annotations | None — comments only | ~20 |
| 5 | TOC | Simplify section separators | None — comments only | ~20 |
| 6 | TOC | Remove `## Rev 10` and `## CHANGED` lines | None — not used by WoW client | ~2 |
