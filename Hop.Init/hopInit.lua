local UI = {
    mainFont = draw.CreateFont("Verdana", 16, 400),
    titleFont = draw.CreateFont("Verdana", 20, 800),
    velocityFont = draw.CreateFont("Verdana", 30, 800),
    colors = {
        background = {15, 15, 15, 240},
        accent = {65, 185, 255, 255},
        success = {50, 205, 50, 255},
        warning = {255, 165, 0, 255},
        error = {255, 64, 64, 255},
        text = {255, 255, 255, 255},
        textDim = {180, 180, 180, 255},
        velocity = {255, 255, 255, 255}
    },
    window = {
        width = 300,
        height = 200,
        padding = 20,
        margin = 50
    }
}

local bhopEnabled,targetSuccessRate,lastActionTime=true,100,0
local blockJumpUntil,wasOnGround,perfectJumpCount,isBlocked,shouldBlockOnLand=0,false,0,false,false
local safetyEnabled=true
local BLOCK_DURATION,MAX_PERFECT_JUMPS,TOGGLE_DELAY=1,10,0.1

local function resetState() perfectJumpCount,isBlocked,blockJumpUntil,shouldBlockOnLand=0,false,0,false end

local function isPlayerValid(p) return p and p:IsAlive() end

local function onCreateMove(cmd)
    local p=entities.GetLocalPlayer()
    if not isPlayerValid(p) then return end
    local t=globals.TickCount()
    if not input.IsButtonDown(KEY_SPACE) or not bhopEnabled then resetState() return end
    local g=(p:GetPropInt("m_fFlags")&FL_ONGROUND)==1
    if shouldBlockOnLand and g then isBlocked,blockJumpUntil,shouldBlockOnLand,perfectJumpCount=true,t+BLOCK_DURATION,false,0 cmd.buttons=cmd.buttons&~IN_JUMP return end
    if isBlocked then cmd.buttons=cmd.buttons&~IN_JUMP if t>=blockJumpUntil then isBlocked,blockJumpUntil=false,0 end return end
    if not g then cmd.buttons=cmd.buttons&~IN_JUMP wasOnGround=false return end
    if t<blockJumpUntil then wasOnGround=true return end
    if not wasOnGround then
        if engine.RandomInt(1,100)<=targetSuccessRate then
            if safetyEnabled and perfectJumpCount>=MAX_PERFECT_JUMPS-1 then shouldBlockOnLand=true cmd.buttons=cmd.buttons&~IN_JUMP return end
            cmd.buttons=cmd.buttons|IN_JUMP perfectJumpCount=perfectJumpCount+1
        else shouldBlockOnLand=true cmd.buttons=cmd.buttons&~IN_JUMP perfectJumpCount=0 end
    end
    wasOnGround=true
end

local function drawUI()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then return end
    local w,h=draw.GetScreenSize()
    local bw,bh=UI.window.width,UI.window.height
    local bx,by=math.floor(w-bw-UI.window.margin),math.floor(h/2-bh/2)
    draw.SetFont(UI.mainFont)
    if not safetyEnabled then draw.Color(table.unpack(UI.colors.error)) draw.Text(bx+UI.window.padding,by-20,"!Warning: Unsafe Mode!") end
    draw.Color(table.unpack(UI.colors.background))
    draw.FilledRect(bx,by,bx+bw,by+bh)
    draw.Color(table.unpack(UI.colors.accent))
    draw.OutlinedRect(bx,by,bx+bw,by+bh)
    draw.SetFont(UI.titleFont)
    draw.Color(table.unpack(UI.colors.accent))
    local tw=draw.GetTextSize("HOP.INIT")
    draw.Text(math.floor(bx+(bw-tw)/2),by+UI.window.padding,"HOP.INIT")
    draw.SetFont(UI.mainFont)
    local y=by+UI.window.padding*2.2
    local sw=draw.GetTextSize("Status: ")
    draw.Color(table.unpack(UI.colors.text))
    draw.Text(bx+UI.window.padding,y,"Status: ")
    draw.Color(table.unpack(not bhopEnabled and UI.colors.error or isBlocked and UI.colors.error or shouldBlockOnLand and UI.colors.warning or UI.colors.success))
    draw.Text(bx+UI.window.padding+sw,y,not bhopEnabled and"DISABLED"or isBlocked and"BLOCKED"or shouldBlockOnLand and"BLOCK ON LAND"or"ENABLED")
    draw.Color(table.unpack(UI.colors.text))
    draw.Text(bx+UI.window.padding,y+25,"Success Rate: "..targetSuccessRate.."%")
    draw.Color(table.unpack(perfectJumpCount>=7 and UI.colors.warning or perfectJumpCount>=4 and UI.colors.success or UI.colors.text))
    draw.Text(bx+UI.window.padding,y+50,string.format("Perfect Jumps: %d/%d",perfectJumpCount,MAX_PERFECT_JUMPS))
    draw.Color(table.unpack(UI.colors.text))
    local velText="Current Velocity: "
    local velWidth=draw.GetTextSize(velText)
    draw.Text(bx+UI.window.padding,y+75,velText)
    local p=entities.GetLocalPlayer()
    draw.Text(bx+UI.window.padding+velWidth,y+75,isPlayerValid(p) and tostring(math.floor(math.sqrt((p:EstimateAbsVelocity()).x^2+(p:EstimateAbsVelocity()).y^2))) or "0")
    draw.Color(table.unpack(UI.colors.textDim))
    draw.Text(bx+UI.window.padding,y+95,"P - Toggle On/Off")
    draw.Text(bx+UI.window.padding,y+115,"L - Toggle Safety")
    draw.Text(bx+UI.window.padding,y+135,"UP/DOWN - Adjust Success Rate")
end

local function handleKeys()
    local t=globals.RealTime()
    if t-lastActionTime<TOGGLE_DELAY then return end
    if input.IsButtonPressed(KEY_P) then bhopEnabled=not bhopEnabled resetState() lastActionTime=t
    elseif input.IsButtonPressed(KEY_L) then safetyEnabled=not safetyEnabled resetState() lastActionTime=t
    elseif input.IsButtonPressed(KEY_UP) then targetSuccessRate=math.min(targetSuccessRate+5,100) lastActionTime=t
    elseif input.IsButtonPressed(KEY_DOWN) then targetSuccessRate=math.max(targetSuccessRate-5,0) lastActionTime=t end
end

callbacks.Register("CreateMove","bhop_script",onCreateMove)
callbacks.Register("Draw","bhop_ui",drawUI)
callbacks.Register("CreateMove","bhop_keys",handleKeys)