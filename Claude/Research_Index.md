# GRIP Research Index

> Compiled March 2026 for GRIP v0.4.0 targeting Retail / Midnight (12.0.1+).

---

## Documents

| # | Document | Focus |
|---|----------|-------|
| 01 | [API Reference](Research_01_API_Reference.md) | Full signatures, return types, quirks, and throttle behavior for every WoW API GRIP uses |
| 02 | [Midnight / 12.0 Changes](Research_02_Midnight_12_0_Changes.md) | Deprecations, removals, and additions since TWW/11.0 — action items for GRIP |
| 03 | [Hardware Event Mechanics](Research_03_Hardware_Events.md) | What counts as a hardware event, propagation rules, taint system, practical patterns |
| 04 | [Chat & Channel Throttling](Research_04_Chat_Throttling.md) | Rate limits on whispers, channels, /who queries — safe intervals, Silence penalty system |
| 05 | [Club Finder / Guild Finder API](Research_05_Club_Finder_API.md) | Why {guildlink} is flaky, the full API chain, fallback strategies |
| 06 | [Addon Policy & ToS](Research_06_Addon_Policy_ToS.md) | What Blizzard allows/prohibits, risk assessment, community reception |
| 07 | [12.0.1 API Audit (March 2026)](Research_07_12_0_1_Audit_March2026.md) | Cross-reference of ALL GRIP APIs against live 12.0.1 build — corrections to earlier research, concrete action items |
| 08 | [Codebase Cleanup Audit (March 2026)](Research_08_Codebase_Cleanup_March2026.md) | Header bloat, dead code, comment quality — what to remove and why |
| 09 | [Guild Name & Guild Link Fix (March 2026)](Research_09_GuildName_GuildLink_Fix.md) | Root cause: `C_GuildInfo.GetGuildInfo` doesn't exist, login timing, missing events, debug spam — full fix plan |

---

## Key Action Items (from all research)

> **Updated 2026-03-01** — Research_07 corrects two false claims from Research_02. See Research_07 for full details and sources.

### High Priority
- ~~**Replace `GetChannelList()`**~~ — ❌ **NOT removed.** Still available in 12.0.1. No action needed. (Research_02 was wrong.)
- ~~**Replace `ChatFrame_AddMessageEventFilter()`**~~ — ❌ **NOT removed.** Still available, not deprecated. No action needed. (Research_02 was wrong.)
- ~~**Replace `GuildInvite()` with `C_GuildInfo.Invite()`**~~ — ✅ **Done.** Compat wrapper `SafeGuildInvite()` added in Utils.lua, used by Invite.lua and UnitPopupInvite.lua.
- ~~**Fix `scanMaxLevel` fallback**~~ — ✅ **Done.** Changed `or 80` to `or 90` in Who.lua.
- **Fix `GetGuildName()` — dead API path + login timing** — `C_GuildInfo.GetGuildInfo` doesn't exist. No event-driven cache warming. See Research_09.
- **Fix `GetGuildFinderLink()` — spam + timing** — No cache, no throttle, spams debug on every failed call. See Research_09.
- **Add guild data events** — GRIP doesn't listen for PLAYER_GUILD_UPDATE, GUILD_ROSTER_UPDATE, or INITIAL_CLUBS_LOADED. See Research_09.

### Medium Priority
- **Add Midnight zones to static zone list** — Zul'Aman, Harandar, reimagined Eversong/Ghostlands.
- **Byte-count messages, not char-count** — Emoji (🙂 in default templates) are multi-byte. A 250-char message with emoji can exceed the 255-byte limit.

### Low Priority
- Pass `origin` parameter to `C_FriendList.SendWho()` (optional but correct)
- Add Haranir to any fallback race lists
- Consider daily whisper caps to protect users from Silence penalties
- Add `/grip link` debug command for {guildlink} troubleshooting
- Document for users that guild must have active Guild Finder listing for {guildlink}

---

## Verification Notes

All major claims in these documents were fact-checked against official sources (Warcraft Wiki, Wowpedia, Blizzard announcements). One item remains unconfirmed: whether `pcall()` definitively breaks hardware event propagation. The documents flag this uncertainty explicitly. All other claims were confirmed.
