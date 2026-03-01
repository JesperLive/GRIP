# Hardware Event Mechanics — Complete Reference for GRIP

> Compiled March 2026. Covers Retail / Midnight (12.0+).

---

## 1. What Is a Hardware Event?

A hardware event is a direct, user-initiated input action that WoW recognizes as proof of human interaction. Blizzard uses this mechanism to prevent fully automated gameplay.

### Actions That Count as Hardware Events

- Mouse clicks (left, right, middle, any button)
- Mouse wheel scrolling
- Keyboard key presses
- Gamepad button presses / stick movements
- Slash commands typed by the user (e.g., `/grip invite`)

### Actions That Do NOT Count

- `C_Timer.After()` callbacks
- `C_Timer.NewTicker()` callbacks
- Event handler callbacks (`OnEvent`, `OnUpdate`)
- Coroutine resumption (`coroutine.resume()`)
- Protected calls (`pcall()`, `xpcall()`)
- Any function called from any of the above

---

## 2. GRIP's Hardware-Event-Restricted APIs

| API | Where in GRIP | Entry Points |
|-----|--------------|--------------|
| `C_FriendList.SendWho(filter)` | `Recruit/Who.lua` | Scan button, `/grip scan`, `GRIP_WHO_NEXT` keybind |
| `GuildInvite(name)` | `Recruit/Invite.lua`, `Hooks/UnitPopupInvite.lua` | Invite button, `/grip invite`, `GRIP_INVITE_NEXT` keybind, right-click menu |
| `SendChatMessage(..., "CHANNEL", ...)` | via `SendChatMessageCompat` | Post button, `/grip post`, `GRIP_POST_NEXT` keybind |

**WHISPER sends do NOT require hardware events.** This is why GRIP can run whispers on a ticker without user interaction.

---

## 3. How Hardware Event Propagation Works

The hardware event status persists **only through the immediate synchronous call chain** initiated by the user action. The moment execution enters any deferred or async context, it's gone.

```
User clicks button
  └─ OnClick handler fires (HW event = YES)
       ├─ Direct function call (HW event = YES)
       │    └─ GuildInvite("Name") ← WORKS
       └─ C_Timer.After(0, function()
              GuildInvite("Name") ← BLOCKED (HW event lost)
          end)
```

### What Preserves Hardware Events

- Direct synchronous function calls within the click handler
- Nested function calls (A calls B calls C — all have HW event)
- Multiple lines in the same handler (with caveats — see below)

### What Destroys Hardware Events

| Mechanism | HW Event Preserved? |
|-----------|---------------------|
| `C_Timer.After()` | NO |
| `C_Timer.NewTicker()` | NO |
| `coroutine.resume()` | NO |
| `pcall()` / `xpcall()` | NO |
| Event handlers (`OnEvent`) | NO |
| `OnUpdate` scripts | NO |
| Frame scripts from other frames | NO |

---

## 4. Can You Chain Multiple Restricted Calls?

**Partially.** Within a single click handler, you can call multiple restricted APIs, but there are limitations:

```lua
button:SetScript("OnClick", function()
    C_FriendList.SendWho("1-10")  -- Works (first restricted call)
    GuildInvite("PlayerName")      -- May work or may be blocked
end)
```

Behavior here is inconsistent and version-dependent. The safest pattern is **one restricted action per hardware event**. GRIP follows this principle:

- Scan button → one `SendWho()` call
- Invite button → one `GuildInvite()` call + unrestricted whisper
- Post button → one `SendChatMessage("CHANNEL")` call

---

## 5. The Taint System

### Overview

All addon code is inherently "tainted." Taint spreads like a virus: anything your addon touches becomes tainted. Protected (Blizzard) functions detect taint in the calling code and refuse to execute if tainted — unless a hardware event is in the call stack.

### Secure vs Insecure Execution

| Property | Secure (Blizzard) Code | Insecure (Addon) Code |
|----------|----------------------|----------------------|
| Source | FrameXML, Blizzard UI | Your addon, `/run` |
| Taint | Clean | Tainted |
| Protected APIs | Always allowed | Only with hardware event |

### What Causes "Action Blocked" Errors

`ADDON_ACTION_BLOCKED` fires when tainted code attempts to call a protected function without a hardware event in the call stack. This is the error you see if you try to call `GuildInvite()` from a timer.

### SecureActionButton vs Regular Buttons

- **SecureActionButton**: Maintains secure execution context in its `OnClick`. Can call protected functions during hardware events.
- **Regular addon button**: `OnClick` is tainted. Can still call protected functions IF a hardware event is in the stack (which it is, during a click).

For GRIP's purposes, regular buttons work fine because the click itself provides the hardware event. SecureActionButton is only needed for combat-related protected actions (spell casting, target changes).

---

## 6. Combat Lockdown

During combat (`InCombatLockdown() == true`):

- Cannot call `GuildInvite()` — blocked
- Cannot call `SendChatMessage("CHANNEL")` — blocked
- Cannot reconfigure SecureActionButton attributes
- CAN still call `SendChatMessage("WHISPER")` — unrestricted
- CAN still call non-protected APIs

GRIP checks `InCombatLockdown()` before all restricted calls:
```lua
if InCombatLockdown() then
    GRIP:Log(1, "Cannot invite during combat")
    return
end
GuildInvite(fullName)
```

---

## 7. Practical Patterns for GRIP

### Pattern 1: One Action Per Click (GRIP's Primary Pattern)

```lua
-- Invite button: one invite + unrestricted whisper
inviteButton:SetScript("OnClick", function()
    if InCombatLockdown() then return end
    local candidate = GetNextCandidate()
    if candidate then
        GuildInvite(candidate.fullName)          -- HW event ✓
        SendChatMessage(msg, "WHISPER", nil, candidate.fullName)  -- No HW needed
    end
end)
```

### Pattern 2: Queue and Flush (Ghost Mode)

GRIP's Ghost Mode queues CHANNEL sends and flushes one per hardware event:

```lua
-- Queue phase (from ticker — no HW event)
Ghost:Queue("CHANNEL", msg, nil, channelId, meta)

-- Flush phase (from button click — HW event)
postButton:SetScript("OnClick", function()
    Ghost:FlushOne(true)  -- isHardwareEvent = true
end)
```

This is a well-established addon pattern (see MessageQueue addon on GitHub). It respects Blizzard's intent: the human decides WHEN to send, the addon just organizes WHAT to send.

### Pattern 3: Slash Commands as Hardware Events

Slash commands count as hardware events:

```lua
SLASH_GRIP1 = "/grip"
SlashCmdList["GRIP"] = function(msg)
    if msg == "scan" then
        SendNextWho()   -- HW event from slash command ✓
    elseif msg == "invite" then
        InviteNext()    -- HW event from slash command ✓
    elseif msg == "post" then
        PostNext()      -- HW event from slash command ✓
    end
end
```

### Pattern 4: Keybindings

GRIP registers keybindings in `Bindings.xml`:

```xml
<Binding name="GRIP_WHO_NEXT" description="Send next /who scan">
    GRIP_WhoNext()
</Binding>
```

Key presses are hardware events, so bound actions can call restricted APIs.

---

## 8. Edge Cases and Gotchas

### Hardware Event Doesn't "Expire" by Time

There's no timeout. The hardware event is consumed at the point of the first protected API call. After that call completes, subsequent protected calls in the same handler may or may not work (inconsistent behavior — treat as one-per-click).

### pcall() and Hardware Events

The interaction between `pcall()` and hardware events is not definitively documented. Evidence suggests it may interfere with the secure execution path:

```lua
button:SetScript("OnClick", function()
    pcall(GuildInvite, "PlayerName")  -- May be BLOCKED — unconfirmed
end)
```

**GRIP's pragmatic approach**: Avoid wrapping restricted API calls in `pcall()` as a precaution. Use pre-flight checks instead:
```lua
if IsInGuild() and CanGuildInvite() and not InCombatLockdown() then
    GuildInvite(fullName)
end
```

### OnUpdate Is Never a Hardware Event

`OnUpdate` fires every frame. Even if the user is pressing a key or clicking while `OnUpdate` runs, the frame script doesn't have hardware event status.

### Reload/Login Timing

After `/reload` or login, there's a brief window where hardware event status may behave unexpectedly. GRIP's `ReconcileAfterReload()` handles this by not attempting restricted calls until the UI is fully initialized.

---

## 9. Recent Changes (12.0 Era)

- Hardware event requirements for guild recruitment APIs are **unchanged** in Midnight
- Gamepad-related APIs got new HW event restrictions (irrelevant to GRIP)
- Blizzard has been **loosening** restrictions post-launch based on feedback, not tightening
- No indication that whisper sends will gain HW event requirements
- The combat lockdown system is unchanged

---

## Summary: GRIP's Hardware Event Architecture

```
Hardware Event Sources:
  ├─ UI Buttons (Scan, Invite, Post Next)
  ├─ Keybindings (GRIP_WHO_NEXT, GRIP_INVITE_NEXT, GRIP_POST_NEXT)
  ├─ Slash Commands (/grip scan, /grip invite, /grip post)
  └─ Right-Click Menu (UnitPopup guild invite)
       │
       ▼
  One restricted action per event:
  ├─ SendWho()           ← from Scan
  ├─ GuildInvite()       ← from Invite (+ unrestricted whisper)
  └─ SendChatMessage(CHANNEL) ← from Post (or Ghost:FlushOne)

Non-hardware-event actions (run freely):
  ├─ Whisper queue (ticker every 2.5s)
  ├─ Post scheduler (queues messages for later HW-event flush)
  ├─ Blacklist management
  └─ /who result processing (WHO_LIST_UPDATE event)
```

---

## Sources

- [Secure Execution and Tainting — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Secure_Execution_and_Tainting)
- [Category: Restricted API functions — Warcraft Wiki](https://warcraft.wiki.gg/wiki/Category:API_functions/restricted)
- [SecureActionButtonTemplate — Warcraft Wiki](https://warcraft.wiki.gg/wiki/SecureActionButtonTemplate)
- [Taint in WoW — Townlong Yak](https://www.townlong-yak.com/taint.log/about)
- [MessageQueue Addon — GitHub](https://github.com/LenweSaralonde/MessageQueue)
