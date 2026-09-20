local targetVeh = nil
local activeTows = {} -- Stores information about active rope connections
local stuckTimers = {} -- Stores stuck timers for each towing vehicle
local pendingLink = nil -- Stores first vehicle data for /towin link

-- Config
local maxDistance = 12.0
local stuckThreshold = 20000 -- 20 seconds in ms

-- ponytail: height = model min.z + 0.5m (bumper above ground). Upgrade when per-model bumper bones exist.
local function getRearBumperOffset(veh)
    local minDim, _ = GetModelDimensions(GetEntityModel(veh))
    if not minDim then return vector3(0.0, -2.5, 0.5) end
    return vector3(0.0, minDim.y, minDim.z + 0.5)
end

local function getFrontBumperOffset(veh)
    local minDim, maxDim = GetModelDimensions(GetEntityModel(veh))
    if not minDim or not maxDim then return vector3(0.0, 2.5, 0.5) end
    return vector3(0.0, maxDim.y, minDim.z + 0.5)
end

-- Returns true if player ped is closer to the front bumper, false if closer to rear
local function isPlayerNearFront(ped, veh)
    local frontOff = getFrontBumperOffset(veh)
    local rearOff = getRearBumperOffset(veh)
    local frontPos = GetOffsetFromEntityInWorldCoords(veh, frontOff.x, frontOff.y, frontOff.z)
    local rearPos = GetOffsetFromEntityInWorldCoords(veh, rearOff.x, rearOff.y, rearOff.z)
    local pedPos = GetEntityCoords(ped)
    return #(pedPos - frontPos) < #(pedPos - rearPos)
end

local function getBumperOffset(veh, isFront)
    if isFront then return getFrontBumperOffset(veh) end
    return getRearBumperOffset(veh)
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

-- Creates a rope between two vehicles using exact bumper offsets
local function createTowRope(vehA, offA, vehB, offB)
    local posA = GetOffsetFromEntityInWorldCoords(vehA, offA.x, offA.y, offA.z)
    local posB = GetOffsetFromEntityInWorldCoords(vehB, offB.x, offB.y, offB.z)
    local dist = #(posA - posB)

    RopeLoadTextures()
    while not RopeAreTexturesLoaded() do Wait(0) end

    local rope = AddRope(posA.x, posA.y, posA.z, 0.0, 0.0, 0.0, dist, 4, dist, 0.1, 0.5, false, false, true, 1.0, false, 0)
    AttachEntitiesToRope(rope, vehA, vehB, offA.x, offA.y, offA.z, offB.x, offB.y, offB.z, dist, false, false, "", "")
    ActivatePhysics(rope)

    table.insert(activeTows, {
        towVeh = vehA,
        targetVeh = vehB,
        rope = rope
    })
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

                    if dot > 0 then
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
            createTowRope(currentVeh, getRearBumperOffset(currentVeh), targetVeh, getFrontBumperOffset(targetVeh))
            lib.notify({title = 'Towing', description = 'Connection added to towing network.', type = 'success'})
            targetVeh = nil
        else
            lib.notify({title = 'Error', description = 'You must be in a different vehicle.', type = 'error'})
        end

    elseif action == 'link' then
        if currentVeh ~= 0 then
            lib.notify({title = 'Error', description = 'You must be on foot to use link.', type = 'error'})
            return
        end

        local veh = GetClosestVehicleToPed(playerPed)
        if veh == 0 then
            lib.notify({title = 'Error', description = 'No vehicle nearby.', type = 'error'})
            return
        end

        local nearFront = isPlayerNearFront(playerPed, veh)
        local offset = getBumperOffset(veh, nearFront)
        local sideLabel = nearFront and 'front' or 'rear'

        if not pendingLink then
            pendingLink = { veh = veh, offset = offset, side = sideLabel }
            lib.notify({title = 'Towing', description = ('First vehicle linked (%s). Walk to second vehicle and type /towin link.'):format(sideLabel), type = 'inform'})
        else
            if veh == pendingLink.veh then
                lib.notify({title = 'Error', description = 'Pick a different vehicle.', type = 'error'})
                return
            end

            createTowRope(pendingLink.veh, pendingLink.offset, veh, offset)
            lib.notify({title = 'Towing', description = ('Rope connected: %s of vehicle 1 to %s of vehicle 2.'):format(pendingLink.side, sideLabel), type = 'success'})
            pendingLink = nil
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
        else
            pendingLink = nil
            lib.notify({title = 'Towing', description = 'Pending link cancelled.', type = 'inform'})
        end
    end
end, false)

-- ponytail: scope is GTA world — any vehicle within ~20m is "closest". Add distance cap if needed.
function GetClosestVehicleToPed(ped)
    local pedPos = GetEntityCoords(ped)
    local vehicles = GetGamePool('CVehicle')
    local closest, closestDist = 0, 20.0
    for _, veh in ipairs(vehicles) do
        local vehPos = GetEntityCoords(veh)
        local dist = #(pedPos - vehPos)
        if dist < closestDist then
            closest = veh
            closestDist = dist
        end
    end
    return closest
end
