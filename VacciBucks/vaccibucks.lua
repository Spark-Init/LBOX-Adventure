-- VacciBucks v1.8 By Spark
-- Automation for MvM money glitch
-- Equip Vaccinator for Medic, after joining the game walk in the upgrade zone - or press L to toggle auto walk - and let the ✨ magic ✨ happen

-- Press [ L ] to toggle Auto Walk
-- Press [ K ] to Force Cleanup if something breaks

local config = {
    autoWalkEnabled = false,
    watermarkX = 10,
    watermarkY = 10,
    moneyThreshold = 5000,
    changeClassEnabled = false,
    targetClass = "sniper"
}

local needToLeaveZone = false
local leaveZoneStartPos = nil
local leaveZoneTime = 0
local hasTriedClassChange = false
local pendingRetry = false
local lastRetryTime = 0
local RETRY_COOLDOWN = 5.0
local thresholdNotificationShown = false
local lastExploitTime = 0
local lastCleanupTime = 0
local lastVaccWarning = false
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
local shouldGuidePlayer = false
local midpoint = nil

local lastToggleTime = 0
local TOGGLE_COOLDOWN = 0.2

local function SaveConfig(filename, config)
    local file = io.open(filename, "w")
    if not file then return false end
    
    for key, value in pairs(config) do
        file:write(tostring(key) .. "=" .. tostring(value) .. "\n")
    end
    
    file:close()
    return true
end

local function LoadConfig(filename)
    local file = io.open(filename, "r")
    if not file then return nil end
    
    local config = {}
    for line in file:lines() do
        local key, value = line:match("^(.-)=(.+)$")
        if key and value then
            if value == "true" then value = true
            elseif value == "false" then value = false
            elseif tonumber(value) then value = tonumber(value)
            end
            config[key] = value
        end
    end
    
    file:close()
    return config
end

local loadedConfig = LoadConfig("vaccibucks_config.txt")
if loadedConfig then
    for k, v in pairs(loadedConfig) do
        config[k] = v
    end
end

-- ui stuff
local UI = {
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
local function DrawRect(x, y, w, h, color)
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
    if notif.alpha <= 1 then return end
    
    draw.SetFont(UI.mainFont)
    local iconWidth, _ = draw.GetTextSize(notif.icon)
    local messageWidth, _ = draw.GetTextSize(notif.message)
    local width = math.floor(iconWidth + messageWidth + 30)
    local height = math.floor(UI.notificationHeight)

    local progress = 1 - ((globals.CurTime() - notif.time) / UI.notificationLifetime)
    local alpha = math.floor(notif.alpha * progress)

    draw.Color(0, 0, 0, 178)
    draw.FilledRect(x, y, x + width, y + height)

    draw.Color(notif.color[1], notif.color[2], notif.color[3], alpha)
    draw.Text(math.floor(x + 5), math.floor(y + height / 2 - 7), notif.icon)

    draw.Color(UI.colors.text[1], UI.colors.text[2], UI.colors.text[3], alpha)
    draw.Text(math.floor(x + iconWidth + 15), math.floor(y + height / 2 - 7), notif.message)

    if progress > 0 then
        DrawRect(
            math.floor(x + 1),
            math.floor(y + height - 2),
            math.floor((width - 2) * progress),
            2,
            {199, 170, 255, math.floor(alpha * 0.7)}
        )
    end
end

-- make sure not to go into a server with fucked up variables
local function CheckServerChange()
    local serverIP = engine.GetServerIP()
    local me = entities.GetLocalPlayer()
    
    if serverIP ~= currentServer or not me then
        local oldServer = currentServer
        currentServer = serverIP
        
        isExploiting = false
        upgradeQueue = {}
        respawnExpected = false
        sequenceEndTime = 0
        nextUpgradeTime = 0
        shouldGuidePlayer = false
        thresholdNotificationShown = false
        hasTriedClassChange = false
        
        autoWalkEnabled = config.autoWalkEnabled
        lastToggleTime = 0
        lastVaccWarning = false
        
        if oldServer ~= nil and serverIP then
            AddNotification("Connected to new server - Reset state", "info")
        end
    end
end

local function IsGameInputAllowed()
    return not engine.Con_IsVisible() 
           and not engine.IsGameUIVisible() 
           and not engine.IsChatOpen()
end

local function IsMoneyThresholdReached()
    local me = entities.GetLocalPlayer()
    if not me then return false end
    
    local currency = me:GetPropInt("m_nCurrency")
    if not currency then return false end
    
    return currency >= config.moneyThreshold
end

local function IsMvMWaveActive()
    if not gamerules.IsMvM() then return false end
    local roundState = gamerules.GetRoundState()
    return roundState == 4
end

local function onStringCmd(cmd)
    local command = cmd:Get()
    
    local args = {}
    for word in string.gmatch(command:lower(), "%S+") do
        table.insert(args, word)
    end
    
    if args[1] == "vb_set_threshold" then
        local threshold = tonumber(args[2])
        
        if threshold then
            if threshold > 0 then
                config.moneyThreshold = threshold
                SaveConfig("vaccibucks_config.txt", config)
                AddNotification("Money threshold set to $" .. threshold, "success")
            else
                AddNotification("Threshold must be greater than 0", "error")
            end
        else
            AddNotification("Invalid threshold value", "error")
        end
        
        cmd:Set("")
        return false
    elseif args[1] == "vb_set_class" then
        local validClasses = {
            ["scout"] = true,
            ["soldier"] = true,
            ["pyro"] = true,
            ["demoman"] = true,
            ["heavy"] = true,
            ["engineer"] = true,
            ["medic"] = true,
            ["sniper"] = true,
            ["spy"] = true
        }
        
        if args[2] == "off" then
            config.changeClassEnabled = false
            SaveConfig("vaccibucks_config.txt", config)
            AddNotification("Auto class change disabled", "success")
        elseif validClasses[args[2]] then
            config.changeClassEnabled = true
            config.targetClass = args[2]
            SaveConfig("vaccibucks_config.txt", config)
            AddNotification("Will change to " .. args[2] .. " after threshold", "success")
        else
            AddNotification("Invalid class name", "error")
        end
        
        cmd:Set("")
        return false
    end
end

callbacks.Register("SendStringCmd", "threshold_command", onStringCmd)

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
 
    if IsMvMWaveActive() then
        if autoWalkEnabled then
            autoWalkEnabled = false
            config.autoWalkEnabled = false
            AddNotification("Auto walk disabled - Wave active", "warning")
        end
        shouldGuidePlayer = false
 
        -- handle class change when wave is active
        if config.changeClassEnabled and not hasTriedClassChange and currentTime - lastRetryTime > RETRY_COOLDOWN then
            AddNotification("Wave active - Reconnecting to change class...", "warning")
            pendingRetry = true
            lastRetryTime = currentTime
            hasTriedClassChange = true
            client.Command("retry", true)
        end
        return
    end
 
    if IsMoneyThresholdReached() then
     if not thresholdNotificationShown then
         AddNotification("Money threshold ($" .. config.moneyThreshold .. ") reached!", "warning")
         autoWalkEnabled = false
         config.autoWalkEnabled = false
         thresholdNotificationShown = true
         
         if config.changeClassEnabled and not hasTriedClassChange then
             local me = entities.GetLocalPlayer()
             if me then
                 if me:GetPropInt('m_bInUpgradeZone') == 1 then
                     leaveZoneStartPos = me:GetAbsOrigin()
                     needToLeaveZone = true
                     AddNotification("Moving out of upgrade zone...", "info")
                 else
                     client.Command("joinclass " .. config.targetClass, true)
                     hasTriedClassChange = true
                     AddNotification("Changed class to " .. config.targetClass, "success")
                 end
             end
         end
     end
     return
    end

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

local watermarkX = config.watermarkX 
local watermarkY = config.watermarkY
local isDragging = false 
local dragOffsetX, dragOffsetY = 0, 0

callbacks.Register("Draw", function()
    if engine.IsGameUIVisible() or
       engine.Con_IsVisible() or
       not engine.GetServerIP() or
       not entities.GetLocalPlayer() then
        return
    end
    CheckServerChange()
    local paddingX, paddingY = 10, 5
    local baseText = "VacciBucks"
    local cleanupText = " [K] Cleanup"
    local autoWalkText = " [L] Autowalk"
    local enabledText = " (Enabled)"
    local exploitingText = " (Active)"
    local thresholdText = " [$" .. config.moneyThreshold .. "]"

    local finalAutoWalkText = autoWalkEnabled and (autoWalkText .. enabledText) or autoWalkText
    local finalBaseText = isExploiting and (baseText .. exploitingText) or baseText
    local fullText = finalBaseText .. thresholdText .. cleanupText .. finalAutoWalkText

    draw.SetFont(UI.mainFont)
    local baseTextWidth, _ = draw.GetTextSize(finalBaseText)
    local thresholdWidth, _ = draw.GetTextSize(thresholdText)
    local baseAndThresholdWidth = baseTextWidth + thresholdWidth
    local cleanupTextWidth, _ = draw.GetTextSize(cleanupText)
    local autoWalkTextWidth, _ = draw.GetTextSize(autoWalkText)

    local textWidth, textHeight = draw.GetTextSize(fullText)
    local barWidth = textWidth + (paddingX * 2)
    local barHeight = textHeight + (paddingY * 2)

    local mouse = {
        x = input.GetMousePos()[1],
        y = input.GetMousePos()[2]
    }

    local screenWidth, screenHeight = draw.GetScreenSize()

    if input.IsButtonDown(MOUSE_LEFT) then
        if isDragging then
            watermarkX = mouse.x - dragOffsetX
            watermarkY = mouse.y - dragOffsetY

            config.watermarkX = watermarkX
            config.watermarkY = watermarkY
            SaveConfig("vaccibucks_config.txt", config)

            if watermarkX < 0 then
                watermarkX = 0
            elseif watermarkX + barWidth > screenWidth then
                watermarkX = screenWidth - barWidth
            end

            if watermarkY < 0 then
                watermarkY = 0
            elseif watermarkY + barHeight > screenHeight then
                watermarkY = screenHeight - barHeight
            end
        else
            if mouse.x >= watermarkX and mouse.x <= (watermarkX + barWidth) and
            mouse.y >= watermarkY and mouse.y <= (watermarkY + barHeight) then
                isDragging = true
                dragOffsetX = mouse.x - watermarkX
                dragOffsetY = mouse.y - watermarkY
            end
        end
    else
        isDragging = false
    end

    -- bg
    draw.Color(0, 0, 0, 178)
    draw.FilledRect(watermarkX, watermarkY, watermarkX + barWidth, watermarkY + barHeight)

    -- top bar
    draw.Color(199, 170, 255, 255)
    draw.FilledRect(watermarkX, watermarkY, watermarkX + barWidth, watermarkY + 2)

    -- base text
    draw.Color(UI.colors.text[1], UI.colors.text[2], UI.colors.text[3], 255)
    draw.Text(watermarkX + paddingX, watermarkY + paddingY, finalBaseText)

    -- threshold text
    draw.Color(UI.colors.success[1], UI.colors.success[2], UI.colors.success[3], 255)
    draw.Text(watermarkX + paddingX + baseTextWidth, watermarkY + paddingY, thresholdText)

    -- cleanup text
    draw.Color(UI.colors.textDim[1], UI.colors.textDim[2], UI.colors.textDim[3], 255)
    draw.Text(watermarkX + paddingX + baseAndThresholdWidth, watermarkY + paddingY, cleanupText)

    -- autowalk text
    draw.Text(watermarkX + paddingX + baseAndThresholdWidth + cleanupTextWidth, watermarkY + paddingY, autoWalkText)

    -- enabled text if autowalk is on
    if autoWalkEnabled then
        draw.Color(0, 255, 0, 255)
        draw.Text(watermarkX + paddingX + baseAndThresholdWidth + cleanupTextWidth + autoWalkTextWidth, watermarkY + paddingY, enabledText)
    end

    -- notifications
    local currentTime = globals.CurTime()
    local totalNotificationHeight = (#UI.notifications * (UI.notificationHeight + UI.notificationSpacing))
    local remainingSpaceBelow = screenHeight - (watermarkY + barHeight)
    local remainingSpaceAbove = watermarkY

    local notificationY
    if remainingSpaceBelow >= totalNotificationHeight then
        notificationY = watermarkY + barHeight + 10
    else
        notificationY = watermarkY - totalNotificationHeight - 10
    end

    for i = #UI.notifications, 1, -1 do
        local notif = UI.notifications[i]
        local age = currentTime - notif.time

        if age < 0.2 then
            notif.alpha = math.min(notif.alpha + 25, 255)
        elseif age > UI.notificationLifetime - 0.3 then
            notif.alpha = math.max(notif.alpha - 25, 0)
        end

        if age >= UI.notificationLifetime and notif.alpha <= 0 then
            table.remove(UI.notifications, i)
        elseif notif.alpha >= 55 then
            DrawNotification(notif, watermarkX, notificationY + (i - 1) * (UI.notificationHeight + UI.notificationSpacing))
        end
    end
end)

callbacks.Register("CreateMove", function(cmd)
    local currentTime = globals.CurTime()
    CheckServerChange()
    local me = entities.GetLocalPlayer()
    
    if me and thresholdNotificationShown and config.changeClassEnabled and not hasTriedClassChange then
        if me:GetPropInt('m_bInUpgradeZone') ~= 1 then
            client.Command("joinclass " .. config.targetClass, true) 
            hasTriedClassChange = true
            AddNotification("Changed class to " .. config.targetClass, "success")
        end
    end
    if not me then return end

    if needToLeaveZone then
        if me:GetPropInt('m_bInUpgradeZone') == 1 then
            if leaveZoneStartPos then
                local viewAngles = engine.GetViewAngles()
                local moveDir = viewAngles:Forward() * -1
                
                cmd:SetForwardMove(-450)
                local targetAngle = EulerAngles(0, viewAngles.y, 0)
                cmd:SetViewAngles(targetAngle.x, targetAngle.y, targetAngle.z)
            end
        else
            if leaveZoneTime == 0 then
                leaveZoneTime = currentTime
                AddNotification("Waiting before class change...", "info")
            end
            
            if currentTime - leaveZoneTime >= 0.5 then
                client.Command("joinclass " .. config.targetClass, true)
                hasTriedClassChange = true
                needToLeaveZone = false
                leaveZoneStartPos = nil
                leaveZoneTime = 0
                AddNotification("Changed class to " .. config.targetClass, "success")
            end
        end
    end

    if pendingRetry then
        if entities.GetLocalPlayer() then
            pendingRetry = false
            client.Command("joinclass " .. config.targetClass, true)
            AddNotification("Changed class to " .. config.targetClass, "success")
        end
        return
    end
    
    if input.IsButtonPressed(KEY_L) and (currentTime - lastToggleTime > TOGGLE_COOLDOWN) 
    and IsGameInputAllowed() then
        config.autoWalkEnabled = not config.autoWalkEnabled
        lastVaccWarning = false
        thresholdNotificationShown = false
        AddNotification("Auto Walk " .. (config.autoWalkEnabled and "Enabled" or "Disabled"), "info")
        lastToggleTime = currentTime
    end
    
    if input.IsButtonPressed(KEY_K) and (currentTime - lastCleanupTime > TOGGLE_COOLDOWN)
    and IsGameInputAllowed() then
        ForceCleanup()
        lastCleanupTime = currentTime
    end
    
    if config.autoWalkEnabled then
        local inZone = me:GetPropInt('m_bInUpgradeZone') == 1
        local hasVacc = HasVaccinator(me)
        
        if IsMoneyThresholdReached() then
            if not thresholdNotificationShown then
                AddNotification("Money threshold ($" .. config.moneyThreshold .. ") reached!", "warning")
                config.autoWalkEnabled = false
                thresholdNotificationShown = true
                
                if config.changeClassEnabled and not hasTriedClassChange then
                    if inZone then
                        leaveZoneStartPos = me:GetAbsOrigin()
                        needToLeaveZone = true
                        AddNotification("Moving out of upgrade zone...", "info")
                    else
                        client.Command("joinclass " .. config.targetClass, true)
                        hasTriedClassChange = true
                        AddNotification("Changed class to " .. config.targetClass, "success")
                    end
                end
            end
            return
        end
        
        if not hasVacc and not lastVaccWarning then
            AddNotification("Secondary weapon is not the Vaccinator!", "error")
            lastVaccWarning = true
        elseif hasVacc then
            lastVaccWarning = false
        end

        local isExpl = isExploiting
        
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
    SaveConfig("vaccibucks_config.txt", config)
end)

AddNotification("VacciBucks loaded! [K] for cleanup, [L] for auto walk", "info")