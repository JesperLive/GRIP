# Chat & Channel Throttling — Complete Reference for GRIP

> Compiled March 2026. Covers Retail / Midnight (12.0+).

---

## 1. Whisper Throttling

### Rate Limits

Whispers use WoW's general output throttle, not a dedicated per-message limit. The underlying system is the same one ChatThrottleLib manages.

- **Burst allowance**: ~4,000 bytes before throttling kicks in
- **Sustained rate**: ~800 characters per second (CPS) across all output
- **Per-target**: Throttling is per-CHARACTER, not per-target. All whispers (regardless of recipient) share the same budget.
- **No hardware event needed**: Whispers can be sent from tickers/events freely.

### Safe Intervals for GRIP

| Scenario | Recommended Interval | Rationale |
|----------|---------------------|-----------|
| Conservative (minimize reports) | 3-5 seconds | Feels "human speed" to recipients |
| GRIP default | 2.5 seconds | Balance between speed and perception |
| Aggressive (technical minimum) | 0.5-1 second | Risks player reports |

GRIP's default `whisperDelay = 2.5` is a reasonable middle ground. The 8-second confirmation timeout (`NO_RESPONSE_TIMEOUT = 70s` for invites) adds natural spacing.

### Detection and Flagging

- Blizzard cannot technically distinguish addon-sent whispers from manual ones at the protocol level
- However, rapid identical messages are visible to recipients, who can report
- Players using spam-blocking addons (BadBoy, SpamThrottle) will filter repetitive whispers
- Multiple reports trigger the Silence penalty system (see section 5)

---

## 2. Channel Message Throttling (Trade/General)

### Client-Side Rate Limit

- **Hard limit**: ~2 messages per second before triggering the throttle
- **Error**: "You are sending messages too fast" — blocks further sends for ~5 seconds
- **Applies equally** to Trade, General, and custom channels

### Server-Side/Practical Limits

For recruitment posting, the real constraints are social:

| Consideration | Limit | Source |
|---------------|-------|--------|
| Client throttle | 2 msg/sec max | Built-in |
| SpamThrottle addon | 600s (10 min) duplicate filter | Player-side addon |
| BadBoy addon | Aggressive duplicate/pattern detection | Player-side addon |
| Player perception | 15+ minutes between posts | Community norms |

### GRIP's Approach

- `postIntervalMinutes = 15` (default) — queues one post cycle every 15 minutes
- `minPostInterval = 8` (seconds) — minimum gap between consecutive channel sends
- Posts require hardware event (button/keybind/slash) — can't spam programmatically
- Ghost Mode may queue multiple posts but flushes one per click

### Recommendation

15-minute intervals between Trade/General posts is the sweet spot. This avoids:
- Client-side throttle errors
- Player-side spam filter blocking
- Player reports
- Community hostility

---

## 3. /who Query Throttling

### Server-Side Throttle

`C_FriendList.SendWho()` is subject to silent server-side throttling:

- **Throttled requests are dropped** — no error, no `WHO_LIST_UPDATE` event
- **No published rate limit** — Blizzard doesn't document the exact threshold
- **Empirical safe rate**: 15+ seconds between queries
- **Hardware event required**: Must originate from click/keybind/slash

### The 50-Result Cap

`GetNumWhoResults()` returns at most 50 results. This is a hard FrameXML ceiling.

**GRIP's workaround**: When `numWhos == 50 == totalCount`, the query is saturated. GRIP auto-expands the same level bracket with class sub-filters:
```
"1-10"  →  saturated (50/50)
  → "1-10 c-\"Warrior\""
  → "1-10 c-\"Mage\""
  → "1-10 c-\"Priest\""
  → ... (each class individually)
```

This gives better coverage but requires multiple queries per bracket (one per class).

### Practical Implications

- Users must click "Scan" for each /who query — can't automate
- GRIP enforces `minWhoInterval = 15` seconds between scans
- Caching results locally avoids redundant queries
- Plan for 13 classes × N brackets = many clicks for full coverage

---

## 4. SendChatMessage Output Budget

### The Disconnect Threshold

WoW servers disconnect clients that sustain >3,000 CPS output. This counts ALL output: chat, addon messages, combat events, everything.

### ChatThrottleLib Parameters

ChatThrottleLib (embedded in Ace3) is the standard library for managing this:

```
MAX_CPS:       800 CPS (conservative; 2000 seems safe empirically)
BURST:         4,000 bytes (allows brief high-volume sends)
MSG_OVERHEAD:  40 bytes (estimated per-message overhead)
MIN_FPS:       20 FPS (below this, throttle halves to 400 CPS)
```

### Priority System

| Priority | Use Case | Bandwidth Share |
|----------|----------|----------------|
| ALERT | Real-time critical | ~1/3 when loaded |
| NORMAL | Standard traffic (whispers, posts) | ~1/3 when loaded |
| BULK | Background, non-urgent | ~1/3 when loaded |

When the system isn't fully loaded, unused bandwidth from higher priorities flows down to lower ones.

### Post-Login Restriction

For the first 5 seconds after login or zone change, ChatThrottleLib reduces output to 1/10 normal (80 CPS instead of 800). The server's rate limiter is particularly sensitive during these transitions.

### GRIP's Current Approach

GRIP does NOT use ChatThrottleLib — it implements its own simpler throttling:
- Whisper ticker: one whisper per 2.5s
- Post scheduler: queues at intervals, sends one per click
- No burst management or CPS tracking

**Consideration**: For a recruitment addon with modest message volume, GRIP's simple approach is adequate. ChatThrottleLib integration would be beneficial if GRIP ever needs to coexist better with other high-volume addons.

---

## 5. The Silence Penalty System

### How It Works

The Silence system is triggered by **player reports**, not automated addon detection:

1. Multiple players report a character for Spam or Abusive Chat
2. Reports are reviewed (automated + potentially manual)
3. If threshold met, a Silence penalty is applied

### Escalation

| Offense | Duration |
|---------|----------|
| 1st silence | 24 hours |
| 2nd silence | 48 hours |
| 3rd silence | 96 hours |
| Nth silence | Continues doubling |

Penalties are account-wide (all characters affected).

### What Silenced Players Can/Cannot Do

| Allowed | Blocked |
|---------|---------|
| Whisper Battle.net friends | Send in-game mail |
| Reply to whispers (non-friends) | Invite to party/guild |
| Guild chat | Talk in instance chat |
| | Post in global channels (Trade/General) |
| | Create groups in Group Finder |

### Interaction with GRIP

A silenced player running GRIP would be unable to:
- Send guild invites
- Post in Trade/General
- Send whispers to non-friends

This effectively disables GRIP's core functionality. The Silence system is the primary enforcement mechanism against aggressive recruitment.

### Risk Factors for GRIP Users

| Factor | Risk Level | Mitigation |
|--------|-----------|------------|
| High whisper volume | **High** | Conservative intervals (3-5s), personalized messages |
| Identical messages | **High** | Vary templates, use {player} token |
| Frequent Trade posts | **Medium** | 15+ minute intervals |
| Players with spam-blocker addons | **Low** | Can't control, but spacing reduces filtering |
| Manual reports from annoyed players | **High** | Blacklist system, no-repeat-contacts |

---

## 6. Addon Communication Throttle

### Per-Prefix Limits (SendAddonMessage)

Each addon message prefix gets an independent allowance:
- **Bucket size**: 10 messages
- **Regeneration**: 1 message per second
- **Exceeding**: Returns `Enum.SendAddonMessageResult.AddonMessageThrottle`

GRIP doesn't currently use `SendAddonMessage`, but this is relevant if addon-to-addon communication is added in the future.

### Message Size

- Addon messages: max 254 bytes (prefix + text combined)
- Chat messages: max 255 bytes (exceeding causes disconnect)
- GRIP enforces 250 chars with `SafeTruncateChat()` as safety margin

---

## 7. Anti-Spam Measures — What Players Use

### Popular Spam-Blocking Addons

| Addon | Detection Method | Impact on GRIP |
|-------|-----------------|----------------|
| **BadBoy** | Pattern matching, known spam phrases | Low risk if messages are conversational |
| **SpamThrottle** | Duplicate detection (10-min window) | Will filter identical messages |
| **SpamBlock** | Normalized duplicate matching | Ignores spaces/punctuation in comparisons |
| **Global Ignore List** | Shared blocklists | If GRIP users get added, all GIL users block them |
| **Guild Invite Whisper Blocker** | Specifically blocks guild invite whispers | Directly targets GRIP-style addons |

### Key Insight: Guild Invite Whisper Blocker

This addon exists specifically to block automated recruitment whispers. Its existence proves:
1. Recruitment addons are common enough to spawn counter-addons
2. A significant player segment dislikes automated recruitment whispers
3. Some whispers will simply never reach their targets

---

## 8. Practical Safe Limits Summary

### GRIP Configuration Recommendations

| Parameter | GRIP Default | Conservative | Aggressive |
|-----------|-------------|-------------|------------|
| `whisperDelay` | 2.5s | 4-5s | 1.5s |
| `postIntervalMinutes` | 15 | 20-30 | 10 |
| `minWhoInterval` | 15s | 20s | 15s |
| `minPostInterval` | 8s | 15s | 5s |
| `blacklistDays` | 7 | 14-30 | 3 |

### Daily Throughput Estimates (Conservative)

With 2.5s whisper delay:
- ~24 whispers per minute
- ~1,440 whispers per hour of active use
- Realistically limited by /who scan speed + user click rate

With 15-min post intervals:
- 4 Trade/General posts per hour
- Each requiring a hardware event (click)

### The Golden Rules

1. **Never send identical messages** within 10 minutes (SpamThrottle filter window)
2. **Use {player} and {guild} tokens** to personalize messages
3. **Space whispers 2.5s+ apart** (GRIP's default is good)
4. **Space channel posts 15+ minutes apart** (GRIP's default is good)
5. **Blacklist aggressively** — never contact the same person twice
6. **Monitor for silence** — if users report getting silenced, increase intervals

---

## Sources

- [ChatThrottleLib — Wowpedia](https://wowpedia.fandom.com/wiki/ChatThrottleLib)
- [ChatThrottleLib — Warcraft Wiki](https://warcraft.wiki.gg/wiki/ChatThrottleLib)
- [C_ChatInfo.SendAddonMessage — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)
- [New Silence Penalty — Official Blizzard](https://worldofwarcraft.blizzard.com/en-us/news/20177161/new-silence-penalty-coming-to-world-of-warcraft)
- [BadBoy Anti-Spam — CurseForge](https://www.curseforge.com/wow/addons/bad-boy)
- [SpamThrottle — CurseForge](https://www.curseforge.com/wow/addons/spamthrottle)
- [Guild Invite Whisper Blocker — CurseForge](https://www.curseforge.com/wow/addons/guild-invite-whisper-blocker)
- [ChatThrottleLib Source — GitHub](https://github.com/hurricup/WoW-Ace3/blob/master/AceComm-3.0/ChatThrottleLib.lua)
