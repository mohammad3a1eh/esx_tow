local targetVeh = nil
local activeTows = {} -- Stores information about active rope connections
local stuckTimers = {} -- Stores stuck timers for each towing vehicle

-- Config
local maxDistance = 12.0
local stuckThreshold = 20000 -- 20 seconds in ms

-- Helper to find if a vehicle is part of any tow connection
local function getTowConnection(veh)
    for i, tow in ipairs(activeTows) do
        if tow.towVeh == veh or tow.targetVeh == veh then
            return tow, i
        end
    end
    return nil, nil
end

local function breakBumperOnSnap(tow)
    if not DoesEntityExist(tow.targetVeh) or not DoesEntityExist(tow.towVeh) then return end
    if not IsVehicleBumperBrokenOff(tow.targetVeh, true) then
        SetVehicleBumperBrokenOff(tow.targetVeh, true, true)
    elseif not IsVehicleBumperBrokenOff(tow.towVeh, false) then
        SetVehicleBumperBrokenOff(tow.towVeh, false, true)
    end
end

local function endTowConnection(index, snapped)
    local tow = activeTows[index]
    if tow then
        if tow.rope then
            DeleteRope(tow.rope)
        end
        stuckTimers[tow.towVeh] = nil
        table.remove(activeTows, index)
        if snapped then
            breakBumperOnSnap(tow)
        else
            lib.notify({title = 'Towing', description = 'Towing connection ended.', type = 'inform'})
        end
    end
end

CreateThread(function()
    while true do
        local wait = 1000
        if #activeTows > 0 then
            wait = 0
            for i = #activeTows, 1, -1 do
                local tow = activeTows[i]
                if DoesEntityExist(tow.towVeh) and DoesEntityExist(tow.targetVeh) then
                    local towPos = GetEntityCoords(tow.towVeh)
                    local targetPos = GetEntityCoords(tow.targetVeh)
                    local dist = #(towPos - targetPos)

                    -- 1. Wrong Direction Check (Towed vehicle ahead of towing vehicle)
                    local towForward = GetEntityForwardVector(tow.towVeh)
                    local relVec = targetPos - towPos
                    local dot = towForward.x * relVec.x + towForward.y * relVec.y + towForward.z * relVec.z

                    if dot > 0 then -- Target is in front of the towing vehicle relative to its forward vector
                         endTowConnection(i, true)
                         lib.notify({title = 'Towing', description = 'Rope snapped! Towed vehicle moved ahead.', type = 'error'})
                         goto continue
                    end

                    -- 2. Distance Check
                    if dist > maxDistance + 3.0 then
                        endTowConnection(i, true)
                        lib.notify({title = 'Towing', description = 'Rope snapped! Distance too great.', type = 'error'})
                        goto continue
                    end

                    -- 3. Stuck Logic
                    if GetVehicleThrottleOffset(tow.towVeh) > 0.1 and GetEntitySpeed(tow.towVeh) < 0.5 then
                        stuckTimers[tow.towVeh] = (stuckTimers[tow.towVeh] or 0) + GetFrameTime() * 1000
                        if stuckTimers[tow.towVeh] >= stuckThreshold then
                            endTowConnection(i, true)
                            lib.notify({title = 'Towing', description = 'Rope snapped! Vehicles were stuck.', type = 'error'})
                            goto continue
                        end
                    else
                        stuckTimers[tow.towVeh] = 0
                    end
                else
                    endTowConnection(i)
                end
                ::continue::
            end
        end
        Wait(wait)
    end
end)

RegisterCommand('towin', function(source, args, raw)
    local action = args[1]
    local playerPed = PlayerPedId()
    local currentVeh = GetVehiclePedIsIn(playerPed, false)

    if action == 'start' then
        if currentVeh ~= 0 then
            targetVeh = currentVeh
            lib.notify({title = 'Towing', description = 'Vehicle selected to be towed.', type = 'inform'})
        else
            lib.notify({title = 'Error', description = 'You must be inside a vehicle.', type = 'error'})
        end

    elseif action == 'add' then
        if not targetVeh or not DoesEntityExist(targetVeh) then
            lib.notify({title = 'Error', description = 'No vehicle selected to be towed. Use /towin start.', type = 'error'})
            return
        end

        if currentVeh ~= 0 and currentVeh ~= targetVeh then
            local towVeh = currentVeh
            local towPos = GetWorldPositionOfEntityBone(towVeh, GetEntityBoneIndexByName(towVeh, "boot")) -- Rear
            if towPos == vector3(0,0,0) then towPos = GetEntityCoords(towVeh) end
            
            local targetPos = GetWorldPositionOfEntityBone(targetVeh, GetEntityBoneIndexByName(targetVeh, "engine")) -- Front
            if targetPos == vector3(0,0,0) then targetPos = GetEntityCoords(targetVeh) end

            local dist = #(towPos - targetPos)

            RopeLoadTextures()
            while not RopeAreTexturesLoaded() do Wait(0) end

            local rope = AddRope(towPos.x, towPos.y, towPos.z, 0.0, 0.0, 0.0, dist, 4, dist, 0.1, 0.5, false, false, true, 1.0, false, 0)
            -- Attach Rear of towVeh to Front of targetVeh
            AttachEntitiesToRope(rope, towVeh, targetVeh, 0.0, -1.0, 0.0, 0.0, 1.0, 0.0, dist, false, false, "boot", "engine")
            ActivatePhysics(rope)
            
            table.insert(activeTows, {
                towVeh = towVeh,
                targetVeh = targetVeh,
                rope = rope
            })

            lib.notify({title = 'Towing', description = 'Connection added to towing network.', type = 'success'})
            targetVeh = nil -- Reset target after adding to allow multiple /towin add calls from a single start
        else
            lib.notify({title = 'Error', description = 'You must be in a different vehicle.', type = 'error'})
        end

    elseif action == 'end' then
        if currentVeh ~= 0 then
            local found = false
            for i = #activeTows, 1, -1 do
                if activeTows[i].towVeh == currentVeh or activeTows[i].targetVeh == currentVeh then
                    endTowConnection(i)
                    found = true
                end
            end
            if not found then
                lib.notify({title = 'Error', description = 'Vehicle is not part of a tow connection.', type = 'error'})
            end
        end
    end
end, false)
