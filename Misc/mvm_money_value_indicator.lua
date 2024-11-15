-- shows real and fake money

local espFont = draw.CreateFont("Verdana", 14, 500)

-- money pack values based on model (idk. how to retrieve the actual value)
local moneyTypes = {
    [804] = "Small ($1-3)",
    [805] = "Medium ($5+)",
    [806] = "Big ($25+)"
}

local function drawMvMMoney()
    -- Don't draw if game is minimized or console is open
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then
        return
    end

    draw.SetFont(espFont)
    
    -- Look for money packs
    for i = 1, entities.GetHighestEntityIndex() do
        local money = entities.GetByIndex(i)
        
        -- Check if it's actually money
        if money and money:IsValid() and money:GetClass() == "CCurrencyPack" then
            local pos = money:GetAbsOrigin()
            local screenPos = client.WorldToScreen(pos)
            
            -- Only draw if money is visible on screen
            if screenPos then
                local isFake = money:GetPropBool("m_bDistributed")
                local modelType = money:GetPropInt("m_nModelIndex")
                local value = moneyTypes[modelType] or "???"
                
                -- Draw box
                if isFake then
                    draw.Color(255, 0, 0, 255)  -- Red for fake money
                else
                    draw.Color(0, 255, 0, 255)  -- Green for real money
                end
                draw.FilledRect(screenPos[1] - 10, screenPos[2] - 10, screenPos[1] + 10, screenPos[2] + 10)
                
                -- Draw text
                draw.Color(255, 255, 255, 255)
                local text = string.format("%s\n%s", 
                    isFake and "Fake" or "Real",
                    value)
                
                -- Draw each line of text
                local yOffset = -45
                for line in text:gmatch("[^\n]+") do
                    draw.Text(screenPos[1] - 40, screenPos[2] + yOffset, line)
                    yOffset = yOffset + 15
                end
            end
        end
    end
end

callbacks.Register("Draw", "mvmMoneyESP", drawMvMMoney)

callbacks.Register("Unload", function()
    callbacks.Unregister("Draw", "mvmMoneyESP")
    print("mvm money esp turned off!")
end)

print("mvm money esp loaded. Green = Real money, Red = Fake money")