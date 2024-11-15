local function OnKeyValues(kv)
    local kvString = kv:Get()
    if kvString:find("MVM_Upgrade") then
        print("Raw upgrade data:", kvString)
        
        local slot = kvString:match('itemslot" "(%d+)"')
        local upgrade = kvString:match('Upgrade" "(%d+)"')
        local count = kvString:match('count" "(%d+)"')
        
        if slot and upgrade and count then
            print(string.format("Slot: %s, Upgrade ID: %s, Count: %s", slot, upgrade, count))
        end
    end
end

callbacks.Register("ServerCmdKeyValues", "debug_upgrades", OnKeyValues)