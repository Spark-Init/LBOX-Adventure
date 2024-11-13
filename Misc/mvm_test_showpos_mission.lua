-- mvm_test_showpos_mission.lua v1.0
-- prints your position and current mvm wave
-- useful for finding coordinates and tracking waves

local lastMission = nil
local lastPosition = Vector3(0,0,0)
local lastWave = 0

local function OnCreateMove()
    local me = entities.GetLocalPlayer()
    if not me then return end
   
    -- track position changes
    local pos = me:GetAbsOrigin()
    if pos:Length() > 0 and (pos - lastPosition):Length() > 5 then
        lastPosition = pos
        print(string.format("Pos: %.2f, %.2f, %.2f", pos.x, pos.y, pos.z))
    end

    -- mvm stuff
    if gamerules.IsMvM() then
        for i = 1, entities.GetHighestEntityIndex() do
            local ent = entities.GetByIndex(i)
            if ent and ent:GetClass() == "CTFObjectiveResource" then
                local mission = ent:GetPropString("m_iszMvMPopfileName")
                local wave = ent:GetPropInt("m_nMannVsMachineWaveCount")
                local maxWaves = ent:GetPropInt("m_nMannVsMachineMaxWaveCount")
                
                if mission and mission ~= lastMission then
                    lastMission = mission
                    print("Mission: " .. mission)
                end

                if wave and wave ~= lastWave then
                    lastWave = wave
                    print(string.format("Wave %d/%d", wave, maxWaves))
                end
                
                break -- found what we need
            end
        end
    end
end

callbacks.Register("CreateMove", "mission_monitor", OnCreateMove)