-- Rev 6
-- GRIP – Trade/General posting module
-- NOTE: Sending to "CHANNEL" is restricted (#hwevent). This module queues posts and provides PostNext().
--
-- CHANGED (Rev 2):
-- - Add GRIPDB/config nil-safety guards for scheduler and enqueue.
-- - Clamp minPostInterval to a sane minimum to avoid click-spam.
-- - Skip enqueue when template resolves to empty/whitespace.
-- - Guard GetChannelList() return shape.
--
-- CHANGED (Rev 3):
-- - Reduce redundant UpdateUI() calls (update once when something actually changed).
-- - QueuePostCycle only refreshes UI if it enqueued at least one message.
-- - PostNext avoids extra UpdateUI() on early returns; refreshes once when queue state changes.
--
-- CHANGED (Rev 4):
-- - Blacklist execution gate (last-line defense): if ad target (player name) is blacklisted, never post to them.
-- - Purge/skip blacklisted names in post queue/pending states (handles bad SavedVariables state after /reload).
-- - Enforce InCombatLockdown() guard for the protected "CHANNEL" post execution.
--
-- CHANGED (Rev 5):
-- - Deduplicate blacklist gating: route post-path blacklist decisions through GRIP:BL_ExecutionGate().
--
-- CHANGED (Rev 6):
-- - Gate Trace Mode plumbing: pass structured context tables to BL_ExecutionGate() so trace logs
--   show action + phase + module when trace is enabled (default trace remains off).

local ADDON_NAME, GRIP = ...
local state = GRIP.state

local function GetCfg()
  return (_G.GRIPDB and GRIPDB.config) or nil
end

local function IsBlank(s)
  if type(s) ~= "string" then return true end
  return s:gsub("%s+", "") == ""
end

-- Structured context for execution gate diagnostics (trace remains opt-in).
local function GateCtx(phase, extra)
  local ctx = {
    action = "post",
    phase = tostring(phase or ""),
    module = "Recruit/Post",
  }
  if extra ~= nil then
    ctx.extra = extra
  end
  return ctx
end

local function GetChannelIdByToken(tokenLower)
  if not GetChannelList then return nil end
  local list = { GetChannelList() } -- triplets: id, name, disabled
  if #list < 3 then return nil end

  local bestId, bestName

  for i = 1, #list, 3 do
    local id = list[i]
    local name = list[i + 1]
    if type(id) == "number" and type(name) == "string" then
      local lname = name:lower()
      if lname:find(tokenLower, 1, true) then
        -- Prefer "trade" that is NOT services, if applicable
        if tokenLower == "trade" then
          if not lname:find("services", 1, true) then
            return id, name
          else
            bestId, bestName = bestId or id, bestName or name
          end
        else
          return id, name
        end
      end
    end
  end

  return bestId, bestName
end

-- Attempt to extract a "target name" from a message.
-- This is intentionally conservative: only returns something if we see an @Name or Name-Realm token.
local function ExtractTargetNameFromMessage(msg)
  if type(msg) ~= "string" then return nil end
  -- @Name-Realm or @Name
  local at = msg:match("@([%a][%a']+[%-]?[%a']*)")
  if at and at ~= "" then return at end

  -- Name-Realm (very rough): starts with a letter, contains '-' somewhere, no spaces
  local nrealm = msg:match("([%a][%w']+%-%w+)")
  if nrealm and nrealm ~= "" then return nrealm end

  return nil
end

local function IsPostBlocked(self, msg, context)
  local target = ExtractTargetNameFromMessage(msg)
  if not target then return false end
  local ok = self:BL_ExecutionGate(target, context or GateCtx("unspecified"))
  return not ok
end

-- Last-line execution gate for posts.
-- Returns true if execution must be blocked.
local function PostBlacklistGate(self, msg, context)
  if IsPostBlocked(self, msg, context or GateCtx("post")) then
    local target = ExtractTargetNameFromMessage(msg)
    self:Debug(
      "Blacklist gate (post): blocked message due to target",
      tostring(target),
      "ctx=",
      (type(context) == "table" and (context.phase or "") or tostring(context or ""))
    )
    return true
  end
  return false
end

local function PurgeBlacklistedFromPostQueue(self)
  state.postQueue = state.postQueue or {}
  if #state.postQueue == 0 then return false end

  local changed = false
  local i = 1
  while i <= #state.postQueue do
    local task = state.postQueue[i]
    local msg = task and task.msg
    if msg and PostBlacklistGate(self, msg, GateCtx("queue")) then
      table.remove(state.postQueue, i)
      changed = true
    else
      i = i + 1
    end
  end

  return changed
end

local function EnqueuePost(channelToken, messageTemplate, reason)
  local cfg = GetCfg()
  if not cfg then return false end

  state.postQueue = state.postQueue or {}

  if #state.postQueue >= (tonumber(cfg.postQueueMax) or 20) then
    GRIP:Debug("Post queue full; skipping enqueue.")
    return false
  end

  if IsBlank(messageTemplate) then
    GRIP:Debug("Post template blank; skipping enqueue:", channelToken, "reason=", reason or "auto")
    return false
  end

  -- NOTE: Posts do not have a single player target in the usual case, so we pass nil.
  local msg = GRIP:ApplyTemplate(messageTemplate, nil)
  if IsBlank(msg) then
    GRIP:Debug("Post resolved blank; skipping enqueue:", channelToken, "reason=", reason or "auto")
    return false
  end

  -- If the message appears to target a specific player, enforce blacklist at enqueue too.
  -- (Execution gate still exists in PostNext.)
  if PostBlacklistGate(GRIP, msg, GateCtx("enqueue", { channel = channelToken, reason = reason or "auto" })) then
    GRIP:Debug("Post enqueue blocked by blacklist gate:", channelToken, "reason=", reason or "auto")
    return false
  end

  state.postQueue[#state.postQueue + 1] = {
    channelToken = channelToken,
    msg = msg,
    queuedAt = GRIP:Now(),
    reason = reason or "auto",
  }
  GRIP:Debug("Post queued:", channelToken, "reason=", reason or "auto", "len=", #msg)
  return true
end

function GRIP:QueuePostCycle(reason)
  local cfg = GetCfg()
  if not cfg or not cfg.postEnabled then return end

  local changed = false
  if EnqueuePost("GENERAL", cfg.postMessageGeneral, reason or "auto") then changed = true end
  if EnqueuePost("TRADE", cfg.postMessageTrade, reason or "auto") then changed = true end

  -- Also purge any now-blocked targets from queue (covers blacklist changes after enqueue).
  if PurgeBlacklistedFromPostQueue(self) then
    changed = true
  end

  if changed then
    self:UpdateUI()
  end
end

function GRIP:StartPostScheduler()
  local cfg = GetCfg()
  if not cfg then return end

  if not cfg.postEnabled then
    self:StopPostScheduler()
    return
  end

  if state.postTicker then return end

  local interval = self:Clamp(tonumber(cfg.postIntervalMinutes) or 15, 1, 180) * 60
  local nextAt = GetTime() + interval

  self:Print(("Post scheduler enabled: every %d min (queues messages; click Post Next to send)."):format(interval / 60))

  state.postTicker = C_Timer.NewTicker(1, function()
    local cfg2 = GetCfg()
    if not cfg2 or not cfg2.postEnabled then
      GRIP:StopPostScheduler()
      return
    end

    interval = GRIP:Clamp(tonumber(cfg2.postIntervalMinutes) or 15, 1, 180) * 60
    if GetTime() >= nextAt then
      GRIP:QueuePostCycle("scheduled")
      nextAt = GetTime() + interval
    end
  end)
end

function GRIP:StopPostScheduler()
  if state.postTicker then
    state.postTicker:Cancel()
    state.postTicker = nil
    self:Print("Post scheduler stopped.")
  end
end

function GRIP:PostNext()
  local cfg = GetCfg()
  if not cfg then
    self:Print("Cannot post: GRIPDB not initialized yet.")
    return
  end

  if InCombatLockdown and InCombatLockdown() then
    self:Print("Cannot post to public channels while in combat.")
    return
  end

  state.postQueue = state.postQueue or {}

  local didChange = false

  -- Purge any now-blocked targeted posts before acting (bad SV /reload safety + live blacklist changes).
  if PurgeBlacklistedFromPostQueue(self) then
    didChange = true
  end

  -- If queue empty, create a one-shot manual cycle
  if #state.postQueue == 0 then
    if EnqueuePost("GENERAL", cfg.postMessageGeneral, "manual") then didChange = true end
    if EnqueuePost("TRADE", cfg.postMessageTrade, "manual") then didChange = true end
  end

  -- Purge again in case manual enqueue created something that is now blocked.
  if PurgeBlacklistedFromPostQueue(self) then
    didChange = true
  end

  if #state.postQueue == 0 then
    self:Print("Post queue is empty.")
    if didChange then self:UpdateUI() end
    return
  end

  local now = GetTime()
  local minInterval = tonumber(cfg.minPostInterval) or 8
  if minInterval < 3 then minInterval = 3 end
  if minInterval > 120 then minInterval = 120 end

  if (now - (state.lastPostSentAt or 0)) < minInterval then
    self:Print(("Please wait %.1fs before posting again."):format(
      minInterval - (now - (state.lastPostSentAt or 0))
    ))
    return
  end

  local task = table.remove(state.postQueue, 1)
  if not task then
    self:Print("Post queue is empty.")
    if didChange then self:UpdateUI() end
    return
  end
  didChange = true

  local token = (task.channelToken or ""):lower()

  local channelId, channelName
  if token == "general" then
    channelId, channelName = GetChannelIdByToken("general")
  elseif token == "trade" then
    channelId, channelName = GetChannelIdByToken("trade")
  else
    self:Print("Unknown channel token: " .. tostring(task.channelToken))
    if didChange then self:UpdateUI() end
    return
  end

  if not channelId then
    self:Print(("Channel not found for '%s'. Are you joined to that channel?"):format(task.channelToken))
    if didChange then self:UpdateUI() end
    return
  end

  if IsBlank(task.msg) then
    self:Print("Post message is blank; skipping.")
    if didChange then self:UpdateUI() end
    return
  end

  -- LAST-LINE DEFENSE: if the message targets a blocked player, never execute the protected call.
  if PostBlacklistGate(self, task.msg, GateCtx("pre-exec", { channel = task.channelToken, channelId = channelId })) then
    self:Print("Post skipped: target is blacklisted.")
    if didChange then self:UpdateUI() end
    return
  end

  state.lastPostSentAt = now
  self:Debug("Post ->", task.channelToken, channelId, task.msg)

  -- Restricted (#hwevent) for chatType "CHANNEL".
  self:SendChatMessageCompat(task.msg, "CHANNEL", nil, channelId)

  self:Print(("Posted to %s: %s"):format(channelName or task.channelToken, task.msg))

  if didChange then
    self:UpdateUI()
  end
end