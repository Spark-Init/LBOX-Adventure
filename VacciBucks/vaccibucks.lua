-- VacciBucks v1.3
-- made this to automate the mvm money glitch
-- equip vaccinator, go in upgrade zone, let the magic happen, repeat
-- press K to force cleanup if something breaks, press L to toggle auto walk

local lastExploitTime = 0
local COOLDOWN_TIME = 0.5
local UPGRADE_DELAY = 0.05
local SEQUENCE_END_COOLDOWN = 1.0
local nextUpgradeTime = 0
local sequenceEndTime = 0
local upgradeQueue = {}
local isExploiting = false
local respawnExpected = false
local currentServer = nil

-- auto walk stuff
local autoWalkEnabled = false
local shouldGuidePlayer = false
local midpoint = nil
local lastMidpoint = nil

local lastToggleTime = 0
local TOGGLE_COOLDOWN = 0.2

-- ui stuff
local UI = {
   x = 20,
   y = 300,
   width = 450,
   height = 115,
   cornerRadius = 4,
   titleFont = draw.CreateFont("Verdana Bold", 22, 800),
   mainFont = draw.CreateFont("Verdana", 16, 400),
   colors = {
       background = {15, 15, 15, 240},
       accent = {65, 185, 255},
       success = {50, 205, 50},
       warning = {255, 165, 0},
       error = {255, 64, 64},
       text = {255, 255, 255},
       textDim = {180, 180, 180}
   },
   notifications = {},
   maxNotifications = 10,
   notificationLifetime = 3,
   notificationHeight = 28,
   notificationSpacing = 4
}

local function CreateNotification(message, type)
   local colors = {
       success = UI.colors.success,
       warning = UI.colors.warning,
       error = UI.colors.error,
       info = UI.colors.accent
   }
   
   local icons = {
       success = "✓",
       warning = "⚠",
       error = "✕",
       info = "ℹ"
   }
   
   return {
       message = message,
       icon = icons[type] or icons.info,
       color = colors[type] or colors.info,
       time = globals.CurTime(),
       alpha = 0,
       targetAlpha = 255
   }
end

local function AddNotification(message, type)
   table.insert(UI.notifications, 1, CreateNotification(message, type))
   if #UI.notifications > UI.maxNotifications then
       table.remove(UI.notifications)
   end
end

-- basic drawing stuff that i might reuse later
local function DrawRoundedRect(x, y, w, h, radius, color)
   draw.Color(
       math.floor(color[1]), 
       math.floor(color[2]), 
       math.floor(color[3]), 
       math.floor(color[4] or 255)
   )
   draw.FilledRect(
       math.floor(x),
       math.floor(y),
       math.floor(x + w),
       math.floor(y + h)
   )
end

local function DrawNotification(notif, x, y)
    -- Dynamically calculate the width based on the message and icon size
    draw.SetFont(UI.mainFont)
    local iconWidth, _ = draw.GetTextSize(notif.icon)
    local messageWidth, _ = draw.GetTextSize(notif.message)
    local width = math.floor(iconWidth + messageWidth + 30)  -- 30 is the space between icon and message
    local height = math.floor(UI.notificationHeight)

    -- Calculate progress for fading effect (between 0 and 1)
    local progress = 1 - ((globals.CurTime() - notif.time) / UI.notificationLifetime)
    local alpha = math.floor(notif.alpha * progress)  -- Fade the alpha based on progress

    -- Draw the dark background with 70% opacity
    draw.Color(0, 0, 0, 178)  -- Black background with 70% opacity
    draw.FilledRect(x, y, x + width, y + height)

    -- Set font for the icon and draw the icon with fading alpha
    draw.SetFont(UI.mainFont)
    draw.Color(notif.color[1], notif.color[2], notif.color[3], alpha)
    draw.Text(math.floor(x + 5), math.floor(y + height / 2 - 7), notif.icon)

    -- Set font for the message and draw the message with fading alpha
    draw.Color(UI.colors.text[1], UI.colors.text[2], UI.colors.text[3], alpha)
    draw.Text(math.floor(x + iconWidth + 15), math.floor(y + height / 2 - 7), notif.message)

    -- Optionally, you could include a progress bar, but only with a faint color (in case you still want to keep the bar):
    if progress > 0 then
        local barWidth = math.floor((width - 2) * progress)
        DrawRoundedRect(
            math.floor(x + 1),
            math.floor(y + height - 2),
            barWidth,
            2,
            1,
            {199, 170, 255, math.floor(alpha * 0.7)}  -- Slight transparency for the bar
        )
    end
end

local function AddMessage(text, color)
   local typeMap = {
       [table.concat(UI.colors.success)] = "success",
       [table.concat(UI.colors.warning)] = "warning",
       [table.concat(UI.colors.error)] = "error",
       [table.concat(UI.colors.accent)] = "info"
   }
   
   local type = typeMap[table.concat(color)] or "info"
   AddNotification(text, type)
end

-- make sure not to go into a server with fucked up variables
local function CheckServerChange()
    local serverIP = engine.GetServerIP()
    if serverIP ~= currentServer then
        -- reset everything
        isExploiting = false
        upgradeQueue = {}
        respawnExpected = false
        sequenceEndTime = 0
        nextUpgradeTime = 0
        shouldGuidePlayer = false
        
        -- dont show on initial load
        if currentServer ~= nil and serverIP then
            AddNotification("Connected to new server - Reset state", "info")
        end
        
        currentServer = serverIP
    end
end

-- auto walk functions
local function ComputeMove(userCmd, a, b)
    local diff = (b - a)
    if diff:Length() == 0 then return Vector3(0, 0, 0) end
 
    local x = diff.x
    local y = diff.y
    local vSilent = Vector3(x, y, 0)
 
    local ang = vSilent:Angles()
    local cPitch, cYaw, cRoll = userCmd:GetViewAngles()
    local yaw = math.rad(ang.y - cYaw)
    local pitch = math.rad(ang.x - cPitch)
    local move = Vector3(math.cos(yaw) * 450, -math.sin(yaw) * 450, -math.cos(pitch) * 450)
 
    return move
 end
 
 local function WalkTo(userCmd, me, destination)
    local myPos = me:GetAbsOrigin()
    local result = ComputeMove(userCmd, myPos, destination)
    
    userCmd:SetForwardMove(result.x)
    userCmd:SetSideMove(result.y)
 end

local function FindUpgradeStations(me)
    local myPos = me:GetAbsOrigin()
    local upgradeSigns = {}
    
    for i = 0, entities.GetHighestEntityIndex() do
        local entity = entities.GetByIndex(i)
        if entity and entity:GetClass() == "CDynamicProp" then
            local modelName = models.GetModelName(entity:GetModel())
            if modelName == "models/props_mvm/mvm_upgrade_sign.mdl" then
                local entityPos = entity:GetAbsOrigin()
                if entityPos then
                    local entityDistance = vector.Length(vector.Subtract(entityPos, myPos))
                    if entityDistance < 5000 then
                        table.insert(upgradeSigns, {pos = entityPos, distance = entityDistance})
                    end
                end
            end
        end
    end
 
    if #upgradeSigns >= 2 then
        table.sort(upgradeSigns, function(a, b) return a.distance < b.distance end)
        
        local pos1 = upgradeSigns[1].pos
        local closestDistance = math.huge
        local pos2
 
        for i = 2, #upgradeSigns do
            local pos = upgradeSigns[i].pos
            local distance = vector.Length(vector.Subtract(pos, pos1))
            if distance < closestDistance then
                closestDistance = distance
                pos2 = pos
            end
        end
 
        if pos2 then
            return Vector3(
                (pos1.x + pos2.x) / 2,
                (pos1.y + pos2.y) / 2,
                (pos1.z + pos2.z) / 2
            )
        end
    end
    return nil
 end
 
 callbacks.Register("CreateMove", function(cmd)
    CheckServerChange()
    local me = entities.GetLocalPlayer()
    if not me then return end
    
    if autoWalkEnabled and shouldGuidePlayer then
        local newMidpoint = FindUpgradeStations(me)
        if newMidpoint then
            midpoint = newMidpoint
            if not lastMidpoint or 
               lastMidpoint.x ~= midpoint.x or 
               lastMidpoint.y ~= midpoint.y or 
               lastMidpoint.z ~= midpoint.z then
                AddNotification("Walking to upgrade station", "info")
                lastMidpoint = Vector3(midpoint.x, midpoint.y, midpoint.z)
            end
            WalkTo(cmd, me, midpoint)
        end
    end
    
    -- reset lastmidpoint when AW is disabled
    if not autoWalkEnabled or not shouldGuidePlayer then
        lastMidpoint = nil
    end
end)

-- main exploit stuff
local function SendMvMUpgrade(itemslot, upgrade, count)
   local kv = string.format([["MVM_Upgrade" { "Upgrade" { "itemslot" "%d" "Upgrade" "%d" "count" "%d" } }]], 
       itemslot, upgrade, count)
   return engine.SendKeyValues(kv)
end

local function ForceCleanup()
   engine.SendKeyValues('"MvM_UpgradesDone" { "num_upgrades" "0" }')
   isExploiting = false
   upgradeQueue = {}
   respawnExpected = false
   AddNotification("Cleaned up upgrade state", "warning")
end

local function ProcessExploitQueue()
    local currentTime = globals.CurTime()
    
    if sequenceEndTime > 0 and currentTime < sequenceEndTime then return end
    sequenceEndTime = 0
  
    if #upgradeQueue == 0 then
        if isExploiting then
            engine.SendKeyValues('"MvM_UpgradesDone" { "num_upgrades" "0" }')
            AddNotification("Sequence completed!", "success")
            isExploiting = false
            respawnExpected = true
            shouldGuidePlayer = false
            
            sequenceEndTime = currentTime + SEQUENCE_END_COOLDOWN
            nextUpgradeTime = currentTime + SEQUENCE_END_COOLDOWN
            upgradeQueue = {{type = "cleanup"}}
        end
        return
    end
  
    local currentAction = upgradeQueue[1]
    if currentAction.type == "respec" then
        respawnExpected = true
    end
  
    if currentTime < nextUpgradeTime then return end
  
    local action = table.remove(upgradeQueue, 1)
    
    if action.type == "cleanup" then
        ForceCleanup()
        return
    end
  
    if action.type == "begin" then
        engine.SendKeyValues('"MvM_UpgradesBegin" {}')
    elseif action.type == "upgrade" then
        SendMvMUpgrade(action.slot, action.id, action.count)
    elseif action.type == "respec" then
        engine.SendKeyValues('"MVM_Respec" {}')
    elseif action.type == "end" then
        engine.SendKeyValues('"MvM_UpgradesDone" { "num_upgrades" "' .. action.count .. '" }')
    end
    
    nextUpgradeTime = currentTime + UPGRADE_DELAY
  end

local function HasVaccinator(player)
   if not player then return false end
   
   local secondaryWeapon = player:GetEntityForLoadoutSlot(LOADOUT_POSITION_SECONDARY)
   if not secondaryWeapon then return false end
   
   -- check if it's a vacc (item index 998)
   local weaponId = secondaryWeapon:GetPropInt("m_iItemDefinitionIndex")
   return weaponId == 998
end

local function TriggerMoneyExploit()
   local currentTime = globals.CurTime()
   
   if isExploiting then
       AddNotification("Sequence already in progress!", "error")
       return
   end
   
   if currentTime - lastExploitTime < COOLDOWN_TIME then return end
   if sequenceEndTime > 0 and currentTime < sequenceEndTime then return end

   local me = entities.GetLocalPlayer()
   if not me then 
       AddNotification("Local player not found!", "error")
       return 
   end

   if me:GetPropInt('m_bInUpgradeZone') ~= 1 then 
       AddNotification("Must be in upgrade zone!", "error")
       return 
   end

   if not me:IsAlive() then
       AddNotification("Must be alive to use!", "error")
       return
   end

   lastExploitTime = currentTime
   isExploiting = true
   AddNotification("Starting sequence...", "success")
   
   upgradeQueue = {
       {type = "begin"},
       {type = "upgrade", slot = 1, id = 19, count = 1},
       {type = "upgrade", slot = 1, id = 19, count = 1},
       {type = "end", count = 2},
       {type = "begin"},
       {type = "upgrade", slot = 1, id = 19, count = -1},
       {type = "upgrade", slot = 1, id = 19, count = -1},
       {type = "end", count = -2},
       {type = "begin"},
       {type = "upgrade", slot = 1, id = 19, count = 1},
       {type = "upgrade", slot = 1, id = 19, count = 1},
       {type = "end", count = 2},
       {type = "begin"},
       {type = "respec"},
       {type = "end", count = 0}
   }
   
   nextUpgradeTime = currentTime + UPGRADE_DELAY
end

callbacks.Register("Draw", function()
    local offsetX, offsetY = 10, 10  -- Offsets for the box position
    local paddingX, paddingY = 10, 5  -- Padding around the text
    local baseText = "VacciBucks"
    local cleanupText = " [K] Cleanup"
    local autoWalkText = " [L] Autowalk"
    local enabledText = " (Enabled)"
    local exploitingText = " (Active)"  -- Text to show if exploiting is active

    -- Dynamically adjust the text based on the status
    local finalAutoWalkText = autoWalkEnabled and (autoWalkText .. enabledText) or autoWalkText
    local finalBaseText = isExploiting and (baseText .. exploitingText) or baseText

    -- Concatenate the full message
    local fullText = finalBaseText .. cleanupText .. finalAutoWalkText

    -- Set the font and calculate text size
    draw.SetFont(UI.mainFont)
    local textWidth, textHeight = draw.GetTextSize(fullText)

    -- Calculate the dimensions of the box
    local barWidth = textWidth + (paddingX * 2)
    local barHeight = textHeight + (paddingY * 2)
    local barX = offsetX
    local barY = offsetY

    -- Draw the dark background with 70% opacity
    draw.Color(0, 0, 0, 178)  -- RGBA with 70% opacity
    draw.FilledRect(barX, barY, barX + barWidth, barY + barHeight)

    -- Draw the top border
    draw.Color(199, 170, 255, 255)  -- Purple for the top border
    draw.FilledRect(barX, barY, barX + barWidth, barY + 2)

    -- Draw the base text
    draw.Color(UI.colors.text[1], UI.colors.text[2], UI.colors.text[3], 255)
    draw.Text(barX + paddingX, barY + paddingY, finalBaseText)

    -- Draw the cleanup text
    local baseTextWidth, _ = draw.GetTextSize(finalBaseText)
    draw.Color(UI.colors.textDim[1], UI.colors.textDim[2], UI.colors.textDim[3], 255)
    draw.Text(barX + paddingX + baseTextWidth, barY + paddingY, cleanupText)

    -- Draw the Autowalk text
    local cleanupTextWidth, _ = draw.GetTextSize(cleanupText)
    draw.Text(barX + paddingX + baseTextWidth + cleanupTextWidth, barY + paddingY, autoWalkText)

    -- If Autowalk is enabled, draw the green "Enabled" text
    if autoWalkEnabled then
        local autoWalkTextWidth, _ = draw.GetTextSize(autoWalkText)
        draw.Color(0, 255, 0, 255)  -- Green for "Enabled"
        draw.Text(barX + paddingX + baseTextWidth + cleanupTextWidth + autoWalkTextWidth, barY + paddingY, enabledText)
    end

    local currentTime = globals.CurTime()
   
   for i = #UI.notifications, 1, -1 do
       local notif = UI.notifications[i]
       local age = currentTime - notif.time
       
       if age < 0.2 then
           notif.alpha = math.min(notif.alpha + 25, 255)
       elseif age > UI.notificationLifetime - 0.3 then
           notif.alpha = math.max(notif.alpha - 25, 0)
       end
       
       if age >= UI.notificationLifetime then
           table.remove(UI.notifications, i)
       else
           DrawNotification(notif, barX, barY + barHeight + 10 + (i - 1) * (UI.notificationHeight + UI.notificationSpacing))
       end
   end
end)

callbacks.Register("CreateMove", function(cmd)
    -- toggleinput with debounce
    local currentTime = globals.CurTime()
    if input.IsButtonPressed(KEY_L) and (currentTime - lastToggleTime > TOGGLE_COOLDOWN) then
        autoWalkEnabled = not autoWalkEnabled
        AddNotification("Auto Walk " .. (autoWalkEnabled and "Enabled" or "Disabled"), "info")
        lastToggleTime = currentTime
    end
 
    local me = entities.GetLocalPlayer()
    if not me then return end
    
    -- dbg
    if autoWalkEnabled then
        local inZone = me:GetPropInt('m_bInUpgradeZone') == 1
        local hasVacc = HasVaccinator(me)
        local isExpl = isExploiting
        
        -- upd guidance states
        if not inZone and hasVacc and not isExpl then
            local newMidpoint = FindUpgradeStations(me)
            if newMidpoint then
                midpoint = newMidpoint
                if not shouldGuidePlayer then
                    shouldGuidePlayer = true
                    AddNotification("Found upgrade station at: " .. tostring(midpoint.x) .. ", " .. tostring(midpoint.y) .. ", " .. tostring(midpoint.z), "info")
                end
            else
                if shouldGuidePlayer then
                    AddNotification("Lost sight of upgrade station!", "warning")
                end
                shouldGuidePlayer = false
            end
        else
            if shouldGuidePlayer then
                AddNotification("Stopped guidance - reached zone or started exploit", "info")
            end
            shouldGuidePlayer = false
        end
    
        if shouldGuidePlayer and midpoint then
            WalkTo(cmd, me, midpoint)
        end
    end
    
    -- exploit logic
    if me:GetPropInt('m_bInUpgradeZone') == 1 and HasVaccinator(me) and not isExploiting then
        TriggerMoneyExploit()
    end
    
    if isExploiting and me:GetPropInt('m_bInUpgradeZone') ~= 1 and not respawnExpected then
        ForceCleanup()
        AddNotification("Sequence cancelled - left zone!", "error")
        return
    end
    
    if respawnExpected and me:GetPropInt('m_bInUpgradeZone') == 1 then
        respawnExpected = false
    end
    
    if isExploiting and not me:IsAlive() and not respawnExpected then
        ForceCleanup()
        AddNotification("Sequence interrupted!", "error")
        return
    end
    
    if isExploiting then
        ProcessExploitQueue()
    end
end)
 
callbacks.Register("Unload", function()
    ForceCleanup()
end)

AddNotification("VacciBucks loaded! [K] for cleanup, [L] for auto walk", "info")
