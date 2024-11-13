-- EntityDebugger_LookingAt.lua v0.1
-- shows info about whatever you're looking at
-- might be useful for something idk

local floor = math.floor
local format = string.format

-- lazy font creation
local fonts = {
    title = draw.CreateFont("Verdana Bold", 24, 800, FONTFLAG_OUTLINE),
    info = draw.CreateFont("Verdana", 20, 400, FONTFLAG_OUTLINE)
}

-- colors i might change later
local colors = {
    red = {220, 60, 40, 255},
    white = {255, 255, 255, 255},
    blue = {100, 200, 255, 255},
    yellow = {255, 200, 0, 255},
    bg = {0, 0, 0, 180}
}

local function DrawEntityInfo(entity, distance)
    local w, h = draw.GetScreenSize()
    
    -- get all the info we care about
    local class = entity:GetClass() or "???"
    local index = entity:GetIndex() or 0
    local pos = entity:GetAbsOrigin()
    local hp = entity.GetHealth and entity:GetHealth() or "N/A"
    local maxhp = entity.GetMaxHealth and entity:GetMaxHealth() or "N/A"
    local team = entity.GetTeamNumber and entity:GetTeamNumber() or "N/A"
    
    -- box stuff
    local width = 400
    local height = 220
    local x = floor(w/2 - width/2)
    local y = floor(h/2 + 50)
    
    -- background
    draw.Color(table.unpack(colors.bg))
    draw.FilledRect(x, y, x + width, y + height)
    
    -- title
    draw.SetFont(fonts.title)
    draw.Color(table.unpack(colors.red))
    local title = "Entity Information"
    local titlew = draw.GetTextSize(title)
    draw.Text(floor(x + width/2 - titlew/2), floor(y + 20), title)
    
    -- all the info
    draw.SetFont(fonts.info)
    local ypos = floor(y + 50)
    
    local info = {
        {"Class", class},
        {"Index", index},
        {"HP", format("%s / %s", hp, maxhp)},
        {"Team", team},
        {"Pos", format("%.0f, %.0f, %.0f", pos.x, pos.y, pos.z)},
        {"Dist", format("%.0f units", distance)}
    }
    
    for i = 1, #info do
        draw.Color(table.unpack(colors.blue))
        draw.Text(floor(x + 20), floor(ypos), info[i][1] .. ":")
        
        draw.Color(table.unpack(colors.white))
        draw.Text(floor(x + 140), floor(ypos), tostring(info[i][2]))
        
        ypos = ypos + 25
    end
    
    -- crosshair thing
    draw.Color(table.unpack(colors.yellow))
    local cx, cy = floor(w/2), floor(h/2)
    draw.Line(cx - 5, cy, cx + 5, cy)
    draw.Line(cx, cy - 5, cx, cy + 5)
end

local function GetClosestEntity()
    local me = entities.GetLocalPlayer()
    if not me then return end
    
    local myPos = me:GetAbsOrigin() + me:GetPropVector("localdata", "m_vecViewOffset[0]")
    local closest = { ent = nil, dist = 1000 }
    
    for i = 1, entities.GetHighestEntityIndex() do
        local ent = entities.GetByIndex(i)
        if ent and ent:IsValid() and not ent:IsDormant() and ent:GetIndex() > 0 then
            local pos = ent:GetAbsOrigin()
            local onscreen = client.WorldToScreen(pos)
            
            if onscreen then
                local sw, sh = draw.GetScreenSize()
                local dx = onscreen[1] - sw/2
                local dy = onscreen[2] - sh/2
                local screendist = math.sqrt(dx*dx + dy*dy)
                
                if screendist < 100 then
                    local dist = (pos - myPos):Length()
                    if dist < closest.dist then
                        closest.dist = dist
                        closest.ent = ent
                    end
                end
            end
        end
    end
    
    return closest.ent, closest.dist
end

callbacks.Register("Draw", "entity_info", function()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then return end
    
    local ent, dist = GetClosestEntity()
    if ent then DrawEntityInfo(ent, dist) end
end)