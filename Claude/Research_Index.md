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

---

## Key Action Items (from all research)

### High Priority
- **Replace `GetChannelList()`** — Removed in 12.0. Used in `Recruit/Post.lua` to find Trade/General channels. Try `C_ChatInfo.GetChannelInfoFromIdentifier()` or `GetChannelName()`.
- **Replace `ChatFrame_AddMessageEventFilter()`** — Removed in 12.0. Used in `Core/Utils.lua` for whisper echo suppression. Consider removing the feature or finding a new approach.

### Medium Priority
- **Add `C_GuildInfo.Invite()` compat wrapper** — `GuildInvite()` deprecated since 10.2.6.
- **Byte-count messages, not char-count** — Emoji (🙂 in default templates) are multi-byte. A 250-char message with emoji can exceed the 255-byte limit.

### Low Priority
- Add instance-content guard before sends (Midnight blocks addon comms during encounters)
- Consider daily whisper caps to protect users from Silence penalties
- Add `/grip link` debug command for {guildlink} troubleshooting
- Document for users that guild must have active Guild Finder listing for {guildlink}

---

## Verification Notes

All major claims in these documents were fact-checked against official sources (Warcraft Wiki, Wowpedia, Blizzard announcements). One item remains unconfirmed: whether `pcall()` definitively breaks hardware event propagation. The documents flag this uncertainty explicitly. All other claims were confirmed.
