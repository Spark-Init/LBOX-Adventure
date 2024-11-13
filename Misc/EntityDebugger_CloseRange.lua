-- EntityDebugger_CloseRange.lua v0.1
-- shows nearby entities and their props
-- mostly useful for finding stuff to break

local debugFont = draw.CreateFont("Verdana", 14, 400, FONTFLAG_OUTLINE)

local function GetEntityInfo(ent)
    if not ent then return "nil" end
    local pos = ent:GetAbsOrigin()
    return string.format("Class: %s, Index: %d, Pos: (%.1f, %.1f, %.1f)", 
        ent:GetClass(), 
        ent:GetIndex(), 
        pos.x, pos.y, pos.z)
end

local function DrawEntityDebug()
    draw.SetFont(debugFont)
    
    local me = entities.GetLocalPlayer()
    if not me then return end
    
    local myPos = me:GetAbsOrigin()
    local searchRadius = 300 
    local y = 200 

    draw.Color(255, 255, 255, 255)
    draw.Text(20, y, "Player Position: " .. tostring(myPos))
    y = y + 20

    draw.Color(0, 255, 0, 255)
    draw.Text(20, y, "Entities within " .. searchRadius .. " units:")
    y = y + 20

    -- find stuff near us
    local foundEntities = {}
    for i = 0, 2048 do 
        local ent = entities.GetByIndex(i)
        if ent then
            local entPos = ent:GetAbsOrigin()
            if entPos then
                local dist = (myPos - entPos):Length()
                if dist <= searchRadius then
                    table.insert(foundEntities, {
                        ent = ent,
                        dist = dist
                    })
                end
            end
        end
    end

    table.sort(foundEntities, function(a, b) return a.dist < b.dist end)

    -- draw all the things we found
    for _, data in ipairs(foundEntities) do
        local ent = data.ent
        local dist = data.dist
        
        local intensity = math.floor(math.max(0, 255 * (1 - dist/searchRadius)))
        draw.Color(intensity, intensity, 255, 255)
        
        draw.Text(20, y, string.format("Distance: %.1f - %s", dist, GetEntityInfo(ent)))
        y = y + 15

        -- props that I am trying to find but well, nope
        local props = {
            "m_iName",
            "m_target",
            "m_targetName",
            "m_iHealth",
            "m_hOwnerEntity",
            "m_iTeamNum",
            "m_nSolidType",
            "m_triggerBloat"
        }

        for _, prop in ipairs(props) do
            local value = ent:GetPropInt(prop) or ent:GetPropFloat(prop) or ent:GetPropString(prop)
            if value and value ~= 0 and value ~= "" then
                draw.Color(200, 200, 200, 255)
                draw.Text(40, y, string.format("  %s: %s", prop, tostring(value)))
                y = y + 15
            end
        end
    end
end

callbacks.Register("Draw", "EntityDebugger", DrawEntityDebug)

client.ChatPrintf("\x01[\x0732CD32Entity Debugger\x01] Loaded! Look at top-left to see nearby stuff")

callbacks.Register("Unload", function()
    client.ChatPrintf("\x01[\x07FF4040Entity Debugger\x01] Cya!")
end)