-- VacciBucks v1.2
-- made this to automate the mvm money glitch
-- equip vaccinator, go in upgrade zone, let the magic happen, repeat
-- press K to force cleanup if something breaks

local lastExploitTime = 0
local COOLDOWN_TIME = 0.5
local UPGRADE_DELAY = 0.05
local SEQUENCE_END_COOLDOWN = 1.0
local nextUpgradeTime = 0
local sequenceEndTime = 0
local upgradeQueue = {}
local isExploiting = false
local respawnExpected = false

-- ui stuff
local UI = {
    x = 20,
    y = 300,
    width = 300,
    height = 150,
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
    maxNotifications = 3,
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
    local width = math.floor(UI.width - 20)
    local height = math.floor(UI.notificationHeight)
    
    DrawRoundedRect(x, y, width, height, UI.cornerRadius, 
        {25, 25, 25, math.floor(notif.alpha * 0.95)})
    
    draw.SetFont(UI.mainFont)
    draw.Color(notif.color[1], notif.color[2], notif.color[3], math.floor(notif.alpha))
    draw.Text(math.floor(x + 10), math.floor(y + height/2 - 7), notif.icon)
    
    draw.Color(UI.colors.text[1], UI.colors.text[2], UI.colors.text[3], math.floor(notif.alpha))
    draw.Text(math.floor(x + 30), math.floor(y + height/2 - 7), notif.message)
    
    local progress = 1 - ((globals.CurTime() - notif.time) / UI.notificationLifetime)
    if progress > 0 then
        local barWidth = math.floor((width - 2) * progress)
        DrawRoundedRect(
            math.floor(x + 1),
            math.floor(y + height - 2),
            barWidth,
            2,
            1,
            {notif.color[1], notif.color[2], notif.color[3], math.floor(notif.alpha * 0.7)}
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
            
            sequenceEndTime = currentTime + SEQUENCE_END_COOLDOWN
            nextUpgradeTime = currentTime + SEQUENCE_END_COOLDOWN
            upgradeQueue = {{type = "cleanup"}}
        end
        return
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
    local currentTime = globals.CurTime()
    local notifY = math.floor(UI.y + UI.height + 10)
    
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
            DrawNotification(notif, math.floor(UI.x + 10), notifY)
            notifY = math.floor(notifY + UI.notificationHeight + UI.notificationSpacing)
        end
    end
    
    draw.SetFont(UI.titleFont)
    draw.Color(UI.colors.accent[1], UI.colors.accent[2], UI.colors.accent[3], 255)
    draw.Text(math.floor(UI.x + 15), math.floor(UI.y + 15), "VacciBucks")
    
    draw.SetFont(UI.mainFont)
    local statusText = isExploiting and "ACTIVE" or "IDLE"
    local statusColor = isExploiting and UI.colors.success or UI.colors.textDim
    draw.Color(statusColor[1], statusColor[2], statusColor[3], 255)
    draw.Text(math.floor(UI.x + 15), math.floor(UI.y + 45), "Status: " .. statusText)
    
    draw.Color(UI.colors.textDim[1], UI.colors.textDim[2], UI.colors.textDim[3], 255)
    draw.Text(math.floor(UI.x + 15), math.floor(UI.y + 70), "Press [K] to cleanup")
end)

callbacks.Register("CreateMove", function()
    local me = entities.GetLocalPlayer()
    if not me then return end
    
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

callbacks.Register("CreateMove", function()
    if input.IsButtonPressed(KEY_K) then
        ForceCleanup()
    end
end)

AddNotification("VacciBucks loaded! [K] for cleanup", "info")