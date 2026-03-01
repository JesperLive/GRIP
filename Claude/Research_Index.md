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

---

## Key Action Items (from all research)

> **Updated 2026-03-01** — Research_07 corrects two false claims from Research_02. See Research_07 for full details and sources.

### High Priority
- ~~**Replace `GetChannelList()`**~~ — ❌ **NOT removed.** Still available in 12.0.1. No action needed. (Research_02 was wrong.)
- ~~**Replace `ChatFrame_AddMessageEventFilter()`**~~ — ❌ **NOT removed.** Still available, not deprecated. No action needed. (Research_02 was wrong.)
- **Replace `GuildInvite()` with `C_GuildInfo.Invite()`** — `GuildInvite()` deprecated since 10.2.6, could be removed at any time. Used in Invite.lua and UnitPopupInvite.lua. Create compat wrapper.
- **Fix `scanMaxLevel` fallback** — Who.lua line 352 has `or 80` but Midnight level cap is 90. Should be `or 90`.

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
