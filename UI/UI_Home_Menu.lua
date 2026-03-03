-- GRIP: UI Home Page — Context Menu
-- Right-click context menu for Potential list rows (MenuUtil).

local ADDON_NAME, GRIP = ...

local type, pcall = type, pcall

-- WoW API
local InCombatLockdown = InCombatLockdown

local HasDB = function() return GRIP:HomeHasDB() end

function GRIP:ShowRowMenu(home, anchor, name)
  if type(name) ~= "string" or name == "" then return end
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end

  MenuUtil.CreateContextMenu(anchor, function(owner, rootDescription)
    rootDescription:CreateTitle(name)

    -- Blacklist action (perm)
    local alreadyBL = GRIP:IsCurrentlyBlacklisted(name)
    local blBtn = rootDescription:CreateButton(
      alreadyBL and "Blacklist\226\128\166 (already blacklisted)" or "Blacklist\226\128\166",
      function()
        if not HasDB() then return end
        GRIP:PromptBlacklistAdd(name)
      end
    )
    blBtn:SetEnabled(not alreadyBL)

    -- Invite to Guild
    local inCombat = (InCombatLockdown and InCombatLockdown()) and true or false
    local canInvite = (not inCombat) and (C_GuildInfo and C_GuildInfo.Invite or GuildInvite) ~= nil
    local invBtn = rootDescription:CreateButton(
      inCombat and "Invite to Guild (disabled in combat)" or "Invite to Guild",
      function()
        if not HasDB() then return end
        if InCombatLockdown and InCombatLockdown() then
          GRIP:Print("Cannot invite in combat.")
          return
        end
        if (C_GuildInfo and C_GuildInfo.Invite) or GuildInvite then
          local okGate, why = false, "missing-gate"
          if GRIP and type(GRIP.BL_ExecutionGate) == "function" then
            okGate, why = GRIP:BL_ExecutionGate(name, { op = "ui_menu_invite", src = "home" })
          end
          if not okGate then
            GRIP:Print(("Invite blocked (%s): %s"):format(tostring(why or "blocked"), name))
            return
          end
          GRIP:Debug("UI: Menu invite " .. name)
          pcall(function() GRIP:SafeGuildInvite(name) end)
        end
      end
    )
    invBtn:SetEnabled(canInvite)
  end)
end
