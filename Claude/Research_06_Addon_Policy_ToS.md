# Addon Policy & ToS — Recruitment Automation Compliance Guide

> Compiled March 2026. Covers current Blizzard policies for Retail / Midnight.

---

## 1. Blizzard's Official Addon Policy

### UI Add-On Development Policy (Summary)

Blizzard's published addon rules focus on:

1. **Addons must not negatively impact gameplay** for other players
2. **Addons must not automate gameplay** (combat, movement, decision-making)
3. **Addons may not circumvent restrictions** imposed by the game client
4. **Addons may not charge for functionality** (gold or real money)
5. **Blizzard reserves the right** to disable addon functionality at any time

### What This Means for GRIP

Guild recruitment is an administrative/social function, not combat or gameplay automation. The policy doesn't explicitly prohibit recruitment addons, but the automation aspect sits in a gray area:

- **Clearly allowed**: UI organization, message templates, candidate tracking
- **Gray area**: Automated whisper campaigns, mass /who scanning
- **Enforced by API design**: Hardware event requirements on invites, channel posts, /who queries

Blizzard's approach is to enforce restrictions at the API level rather than through policy bans. If they don't want you to automate something, they make the API require a hardware event.

---

## 2. Terms of Service Relevance

### "Bots" Definition

Blizzard's ToS defines bots as "automated control of a Game" and explicitly prohibits them. However, this is primarily aimed at:
- Leveling bots (automated character control)
- Farming bots (automated resource gathering)
- PvP bots (automated combat)

Guild recruitment addons don't control the character or automate gameplay decisions — they automate social communication.

### "Spam" Definition

Blizzard defines spam as "overly repeated message or large quantity of text" and considers it a violation.

**Where GRIP intersects**:
- Sending identical whispers to many players → could be considered spam
- Posting the same recruitment message in Trade → could be considered spam
- The distinction is volume and frequency, not the tool used

### The Critical Distinction

Blizzard's enforcement distinguishes between:
- **The addon itself**: Generally not actionable (it's just code that extends the UI)
- **The player's behavior**: Actionable if it results in spam/harassment reports

An addon that helps organize recruitment is fine. A player who uses it to blast whispers every 0.5 seconds will get silenced — not because of the addon, but because of the behavior.

---

## 3. Hardware Events as Policy Enforcement

### Blizzard's Philosophy

Hardware event requirements exist to ensure a human is actively deciding to perform each restricted action:

- `/who` queries → requires click/keybind (prevents automated mass scanning)
- `GuildInvite()` → requires click/keybind (prevents automated mass inviting)
- Channel sends → requires click/keybind (prevents automated spam)
- Whispers → NO requirement (considered lower-risk personal communication)

### Does GRIP's Queue-and-Flush Pattern Violate the Spirit?

GRIP queues candidates and lets the user flush one action per click. The user is still actively choosing to trigger each action.

**Arguments it's compliant**:
- User must actively click/press for each restricted action
- The queue just organizes work — the human decides when to execute
- This is exactly how macros work (pre-configure, then execute on keypress)
- The MessageQueue pattern is well-established in the addon community

**Arguments it's borderline**:
- A user mechanically clicking "Invite Next" 50 times without reading isn't meaningfully "deciding"
- The friction Blizzard intended (typing `/who`, manually inviting) is reduced to single clicks

**Practical reality**: Blizzard has not taken action against queue-and-flush patterns. If they wanted to prevent this, they would require per-target confirmation in the API.

---

## 4. Historical Precedent

### Recruitment Addons That Exist(ed)

| Addon | Status | Approach |
|-------|--------|----------|
| **Guild Recruiter** | Active on CurseForge | Similar scan/whisper/invite pattern |
| **Fast Guild Recruiter** | Active on CurseForge | Streamlined recruitment workflow |
| **SuperGuildInvite** | Discontinued | Was more aggressive; exact fate unclear |
| **MassInvite** | Discontinued | Name suggests aggressive inviting |
| **AutoGuildInvite** | Various versions | Common pattern in the addon space |

### What Gets Addons Broken (Not Banned)

Blizzard doesn't typically "ban" addons. Instead, they:
1. **Add hardware event requirements** to APIs (e.g., SendWho in 8.2.5)
2. **Remove or restrict APIs** in patches (e.g., GetChannelList in 12.0)
3. **Add client-side throttles** (e.g., chat message rate limiting)

This has affected recruitment addons over the years — each time Blizzard adds a restriction, addons adapt.

---

## 5. Community Reception

### The Player Perspective

Guild recruitment whispers are one of the most complained-about annoyances in WoW:
- Players frequently request "opt-out" mechanisms for recruitment whispers
- The addon "Guild Invite Whisper Blocker" exists specifically to block these
- Reddit/forum threads regularly complain about recruitment spam
- Some players immediately `/ignore` anyone who sends an automated recruitment whisper

### The Guild Leader Perspective

- Recruitment is genuinely difficult and time-consuming
- Manual recruitment (typing `/who`, individually messaging players) is impractical
- Addons like GRIP fill a real need for guild growth
- The alternative (posting in Trade chat only) has much lower conversion

### Best Practices to Minimize Negative Perception

1. **Personalize messages**: Use `{player}` token so it doesn't feel automated
2. **Be conversational**: Templates that sound like a human wrote them get better reception
3. **Respect "no"**: GRIP's blacklist system prevents re-contacting declined players
4. **Don't whisper during combat/dungeons**: Players hate being interrupted mid-fight
5. **Keep Trade posts modest**: 15-minute intervals, varied messages
6. **Don't cold-invite**: Whisper first, then invite if they respond positively (GRIP's workflow supports this)

---

## 6. Risk Assessment for GRIP

### Design Compliance Score

| GRIP Feature | Compliance | Risk |
|-------------|------------|------|
| Hardware-event-gated invites | Fully compliant | None |
| Hardware-event-gated channel posts | Fully compliant | None |
| Hardware-event-gated /who scans | Fully compliant | None |
| Rate-limited whispers (2.5s default) | Technically compliant | Medium — volume-dependent |
| Blacklist system | Best practice | Reduces risk |
| BL_ExecutionGate (last-line defense) | Excellent safety | Reduces risk |
| Template system with personalization | Best practice | Reduces risk |
| Message character limit (250) | Compliant | None |
| Ghost Mode (queue+flush) | Accepted pattern | Low |

### Primary Risks

**1. Silence Penalty from Player Reports (Medium-High)**
The biggest risk to GRIP users. If enough players report the recruitment whispers as spam, the player gets silenced. This isn't about the addon — it's about volume and player perception.

Mitigation: Conservative default intervals, personalized messages, mandatory blacklisting.

**2. Future API Restrictions (Low-Medium)**
Blizzard could add hardware event requirements to whispers, restrict `GetWhoInfo()`, or further limit channel posting. This would require GRIP updates but wouldn't ban the addon.

Mitigation: Modular design, fallback paths, stay current with PTR changes.

**3. Player Backlash (Low)**
If GRIP becomes widely used and generates community complaints, Blizzard might respond with restrictions. This happened with other categories of addons (e.g., WeakAuras in M+).

Mitigation: Promote responsible defaults, document best practices for users.

**4. Direct Addon Ban (Very Low)**
Blizzard has almost never directly banned a non-combat addon by name. They restrict APIs instead. GRIP's design is compliant with all current restrictions.

---

## 7. Recommendations for GRIP

### Defaults That Protect Users

```lua
-- Conservative defaults that minimize Silence risk
whisperDelay = 3.0,           -- Slightly slower than current 2.5
postIntervalMinutes = 20,     -- Slightly longer than current 15
blacklistDays = 14,           -- Longer cooldown before re-contact
```

### Features to Consider

1. **Daily whisper cap**: e.g., max 200 whispers per session (configurable)
2. **"Opt-out" response detection**: If candidate replies "no thanks" or "stop", auto-blacklist
3. **First-whisper-only mode**: Only whisper candidates who haven't been whispered by ANY GRIP user (cross-character tracking via SavedVariables)
4. **Campaign cooldown**: After X minutes of active recruiting, prompt user to take a break
5. **Template variety**: Support multiple message templates with random rotation

### Documentation to Include

1. "GRIP complies with all hardware event requirements"
2. "Your account may receive a Silence penalty if players report your messages as spam"
3. "We recommend conservative intervals and personalized messages"
4. "Your guild must have an active Guild Finder listing for {guildlink} to work"
5. "GRIP is not endorsed by Blizzard. Use at your own discretion."

---

## 8. The Big Picture

GRIP sits in a well-established addon category. Multiple similar addons have operated on CurseForge for years. Blizzard has chosen to manage recruitment automation through API restrictions (hardware events, throttles) rather than outright bans.

The primary risk isn't the addon being banned — it's the user getting silenced because too many players reported them. GRIP's built-in safeguards (blacklist, rate limiting, hardware event compliance) are strong, but the addon can't prevent users from running aggressive campaigns.

The key message: **GRIP is a tool. Whether it causes problems depends on how aggressively the user configures it.**

---

## Sources

- [Blizzard Add-On Policy — Official](https://www.blizzard.com/en-us/legal/44fe4f19-27e4-4c6f-8b39-11a15094e826/add-on-policy)
- [WoW Terms of Use — Blizzard](https://www.blizzard.com/en-us/legal/fba4d00f-c7e4-4883-b8b9-1b4500a402ea/blizzard-end-user-license-agreement)
- [New Silence Penalty — Official Blizzard](https://worldofwarcraft.blizzard.com/en-us/news/20177161/new-silence-penalty-coming-to-world-of-warcraft)
- [Guild Recruiter — CurseForge](https://www.curseforge.com/wow/addons/guild-recruiter)
- [Guild Invite Whisper Blocker — CurseForge](https://www.curseforge.com/wow/addons/guild-invite-whisper-blocker)
- [Using Addon to Recruit — WoW Forums](https://us.forums.blizzard.com/en/wow/t/using-addon-to-recruit/1369300)
