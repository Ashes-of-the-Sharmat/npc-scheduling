local config = {
    ["dralosa athren"] = {
        [6]  = {
            cell = "-3, -2",
            posX = -18651,
            posY = -14572,
            posZ = 198, 
            final = {
                kind = "ANIMATION",
                model = "va_sitting.nif",
                animGroup = "idle3"
            }
        },
        [9] = {
            cell = "Balmora, Dralosa Athren's House",
            posX = 300,
            posY = 75,
            posZ = 128
        },
        [11]  = {
            cell = "-3, -2",
            posX = -18651,
            posY = -14572,
            posZ = 198, 
            final = {
                kind = "ANIMATION",
                model = "va_sitting.nif",
                animGroup = "idle3"
            }
        },
        [13] = {
            cell = "Balmora, Dralosa Athren's House",
            posX = 300,
            posY = 75,
            posZ = 128
        },
        [18]  = {
            cell = "-3, -2",
            posX = -18651,
            posY = -14572,
            posZ = 198, 
            final = {
                kind = "ANIMATION",
                model = "va_sitting.nif",
                animGroup = "idle3"
            }
        },
        [21] = {
            cell = "Balmora, Dralosa Athren's House",
            posX = 300,
            posY = 75,
            posZ = 128
        },
        [1]  = {
            cell = "-3, -2",
            posX = -18651,
            posY = -14572,
            posZ = 198, 
            final = {
                kind = "ANIMATION",
                model = "va_sitting.nif",
                animGroup = "idle3"
            }
        },
        [3] = {
            cell = "Balmora, Dralosa Athren's House",
            posX = 300,
            posY = 75,
            posZ = 128
        }
    },
    ["karlirah"] = {
        [6]  = {
            cell = "-3, -2",
            posX = -18651,
            posY = -14572,
            posZ = 198
        },
        [9] = {
            cell = "Balmora, Karlirah's House",
            posX = 215,
            posY = 20,
            posZ = 28
        },
        [11]  = {
            cell = "-3, -2",
            posX = -18651,
            posY = -14572,
            posZ = 198
        },
        [13] = {
            cell = "Balmora, Karlirah's House",
            posX = 215,
            posY = 20,
            posZ = 28
        },
        [18]  = {
            cell = "-3, -2",
            posX = -18651,
            posY = -14572,
            posZ = 198
        },
        [21] = {
            cell = "Balmora, Karlirah's House",
            posX = 215,
            posY = 20,
            posZ = 28
        },
        [1]  = {
            cell = "-3, -2",
            posX = -18651,
            posY = -14572,
            posZ = 198
        },
        [3] = {
            cell = "Balmora, Karlirah's House",
            posX = 215,
            posY = 20,
            posZ = 28
        }
    }
}

local debugMode = true
local timerId
local transitions = {}
local moving = {}
local finished = {}
local maxDistanceToLocation = 128

local function logMessage(message)
    local level = debugMode == true and 3 or 0
    tes3mp.LogMessage(level, "[AotS_NpcScheduling] " .. message)
end

local function getDistance(sPosX, sPosY, sPosZ, rPosX, rPosY, rPosZ)
    return math.sqrt((sPosX - rPosX)^2 + (sPosY - rPosY)^2 + (sPosZ - rPosZ)^2)
end

local function findCurrentScheduleEntry(refId)
    if config[refId] then
        local hour = WorldInstance.data.time.hour
        local targetHour
        
        for i = 23, 0, -1 do
            if config[refId][i] then
                if i <= hour then
                    return i
                elseif targetHour == nil then
                    targetHour = i
                end
            end
        end

        return targetHour
    end
end

local function getTargetTable(refId, targetHour)
    if config[refId][targetHour].random then
        local randomCount = #config[refId][targetHour].random
        local count = WorldInstance.data.time.daysPassed

        return config[refId][targetHour].random[math.fmod(count, randomCount) + 1] -- Not actually random in any way, but it will give a good effect
    else
        return config[refId][targetHour]
    end
end

local function findLoadDoorToCell(cellDescription, otherCellDescription, destX, destY, destZ)
    local possibleDoors = {}
    local otherCellIsExterior = string.match(otherCellDescription, patterns.exteriorCell)
    local cellRecord = dataFilesLoader.getCellRecord(cellDescription)
    if cellRecord ~= nil then
        for refNum, reference in pairs(cellRecord.references) do
            if reference.door_destination_coords ~= nil then
                if (reference.door_destination_cell == otherCellDescription) or (otherCellIsExterior and reference.door_destination_cell == nil) then
                    table.insert(possibleDoors, refNum)
                end
            end
        end
    end

    if #possibleDoors == 0 then
        return nil
    elseif #possibleDoors == 1 then
        return possibleDoors[1]
    else
        local bestMatch
        local bestDist

        for _, refNum in ipairs(possibleDoors) do
            -- big distance calculation to find which door brings you closest to the destination
            local distance = getDistance(cellRecord.references[refNum].door_destination_coords[1], cellRecord.references[refNum].door_destination_coords[2], cellRecord.references[refNum].door_destination_coords[3], destX, destY, destZ)

            if bestMatch == nil then
                bestMatch = refNum
                bestDist = distance
            else
                if distance < bestDist then
                    bestMatch = refNum
                    bestDist = distance
                end
            end
        end

        return bestMatch
    end
end

local function getDoorDestinationCoordinates(cellDescription, refNum)
    local cellRecord = dataFilesLoader.getCellRecord(cellDescription)

    if cellRecord.references[refNum].door_destination_coords == nil then return nil end

    return {cellRecord.references[refNum].door_destination_coords[1], cellRecord.references[refNum].door_destination_coords[2], cellRecord.references[refNum].door_destination_coords[3], cellRecord.references[refNum].door_destination_coords[6]}
end

local function getDoorSound(cellDescription, refNum)
    local cellRecord = dataFilesLoader.getCellRecord(cellDescription)

    if cellRecord.references[refNum] == nil then return nil end

    local refId = cellRecord.references[refNum].id
    local doorRecord = dataFilesLoader.getRecord(refId, "Door")

    if doorRecord then
        return {doorRecord.open_sound, doorRecord.close_sound}
    end
end

local function playSoundFromObject(pid, cellDescription, uniqueIndex, soundId)
    if not LoadedCells[cellDescription] then return end
    local object = LoadedCells[cellDescription].data.objectData[uniqueIndex]
    if not object then return end

    tes3mp.ClearObjectList()
    tes3mp.SetObjectListPid(pid)
    tes3mp.SetObjectListCell(cellDescription)
    local splitIndex = uniqueIndex:split("-")
    tes3mp.SetObjectRefNum(splitIndex[1])
    tes3mp.SetObjectMpNum(splitIndex[2])
    tes3mp.SetObjectRefId(object.refId)
    tes3mp.SetObjectSound(soundId, 1, 1)
    tes3mp.AddObject()

    tes3mp.SendObjectSound()
end

local function findDoorMarkerNearestToDoor(cellDescription, refNum) -- cell and refnum should correspond to the load door
    logMessage("findDoorMarkerNearestToDoor firing...")
    local originalCellRecord = dataFilesLoader.getCellRecord(cellDescription)
    local reference = originalCellRecord.references[refNum]

    local cellSize = 8192
    local otherCellDescription = reference.door_destination_cell or ( math.floor(reference.door_destination_coords[1] / cellSize) .. ", " .. math.floor(reference.door_destination_coords[2] / cellSize) )
    local otherCellRecord = dataFilesLoader.getCellRecord(otherCellDescription)
    logMessage("Starting door cell = " .. cellDescription)
    logMessage("Marker door cell = " .. otherCellDescription)
    local possibleDoors = {}
    if otherCellRecord then
        for otherRefNum, otherReference in pairs(otherCellRecord.references) do
            if otherReference.door_destination_coords ~= nil then
                if (otherReference.door_destination_cell == cellDescription) or (string.match(cellDescription, patterns.exteriorCell) and otherReference.door_destination_cell == nil) then
                    table.insert(possibleDoors, otherRefNum)
                end
            end
        end

        local bestMatch
        local bestDist

        if #possibleDoors == 0 then
            return nil
        else
            for _, otherRefNum in ipairs(possibleDoors) do
                -- big distance calculation to find which door brings you closest to the destination
                local distance = getDistance(otherCellRecord.references[otherRefNum].door_destination_coords[1], otherCellRecord.references[otherRefNum].door_destination_coords[2], otherCellRecord.references[otherRefNum].door_destination_coords[3], reference.translation[1], reference.translation[2], reference.translation[3])

                if bestMatch == nil then
                    bestMatch = otherRefNum
                    bestDist = distance
                else
                    if distance < bestDist then
                        bestMatch = otherRefNum
                        bestDist = distance
                    end
                end
            end
        end
        logMessage("Target marker coordinates are " .. otherCellRecord.references[bestMatch].door_destination_coords[1] .. ", " .. otherCellRecord.references[bestMatch].door_destination_coords[2] .. ", " .. otherCellRecord.references[bestMatch].door_destination_coords[3])
        return {otherCellRecord.references[bestMatch].door_destination_coords[1], otherCellRecord.references[bestMatch].door_destination_coords[2], otherCellRecord.references[bestMatch].door_destination_coords[3]}
    end
end

local function atFinalDestination(cellDescription, refNum, targetTable) -- if an NPC has reached their scheduled destination
    logMessage("atFinalDestination firing for refNum " .. refNum .. " in cell " .. cellDescription)

    if targetTable.posX == nil or targetTable.posY == nil or targetTable.posZ == nil then return true end -- Future proof an idea and also avoiding problems with malformed data
    local objectData = LoadedCells[cellDescription].data.objectData[refNum]
    if cellDescription == targetTable.cell or targetTable.cell == nil then
        if LoadedCells[cellDescription]:GetVisitorCount() > 0 then
            LoadedCells[cellDescription]:SaveActorPositions()
        end
        if objectData.location == nil then  logMessage("atFinalDestination aborting due to missing location data") return end
        if getDistance(targetTable.posX, targetTable.posY, targetTable.posZ, objectData.location.posX, objectData.location.posY, objectData.location.posZ) < maxDistanceToLocation then
            transitions[LoadedCells[cellDescription].data.objectData[refNum].refId] = nil
            return true
        end
    end    
    return false
end

local function isFinished(refId, hour) -- separate from atFinalDestination so the measurement in that function doesn't need to be done more than once; this allows for wandering NPCs etc.
    if finished[hour] and tableHelper.containsValue(finished[hour], refId) then
        return true
    else -- hour has updated; clear the refId from the list
        for hourIndex, list in pairs(finished) do
            tableHelper.removeValue(list, refId)
        end
        return false
    end
end

local function atTempDestination(cellDescription, refNum)
    local refId = LoadedCells[cellDescription].data.objectData[refNum].refId
    if transitions[refId] then
        if LoadedCells[cellDescription]:GetVisitorCount() > 0 then
            LoadedCells[cellDescription]:SaveActorPositions()
        else return true
        end
        local objectData = LoadedCells[cellDescription].data.objectData[refNum]
        if objectData.location == nil then return logMessage("atTempDestination aborting to to missing information data") end
        if getDistance(transitions[refId].posX, transitions[refId].posY, transitions[refId].posZ, objectData.location.posX, objectData.location.posY, objectData.location.posZ) < maxDistanceToLocation then
            return true
        end
    end
    return false
end

local function applySpecialMovement(cellDescription, uniqueIndex, special)
    if special and LoadedCells[cellDescription] and LoadedCells[cellDescription].data.objectData[uniqueIndex] then
        local refId = LoadedCells[cellDescription].data.objectData[uniqueIndex].refId
        if special == "SNEAK" and LoadedCells[cellDescription]:GetVisitorCount() > 0 then
            logicHandler.RunConsoleCommandOnObject(LoadedCells[cellDescription]:GetAuthority(), refId .. "->ForceSneak", cellDescription, uniqueIndex, true)
        elseif special == "RUN" and LoadedCells[cellDescription]:GetVisitorCount() > 0 then
            logicHandler.RunConsoleCommandOnObject(LoadedCells[cellDescription]:GetAuthority(), refId .. "->ForceRun", cellDescription, uniqueIndex, true)
        elseif special == "JUMP" and LoadedCells[cellDescription]:GetVisitorCount() > 0 then -- Will there ever be a use for this? Probably not
            logicHandler.RunConsoleCommandOnObject(LoadedCells[cellDescription]:GetAuthority(), refId .. "->ForceMoveJump", cellDescription, uniqueIndex, true)
        elseif special == "LEVITATE" then
            -- TODO make a 5 pt levitate CE custom spell
        end
    end
end

local function clearSpecialMovement(cellDescription, uniqueIndex)
    -- TODO make a custom script to clear all movement modifiers
end

local function safelySetActorAI(cellDescription, actorUniqueIndex, action, targetPid, targetUniqueIndex, posX, posY, posZ, distance, duration, shouldRepeat)
    if LoadedCells[cellDescription]:GetVisitorCount() > 0 then
        logicHandler.SetAIForActor(LoadedCells[cellDescription], actorUniqueIndex, action, targetPid, targetUniqueIndex, posX, posY, posZ, distance, duration, shouldRepeat)
    else
        local aiData = dataTableBuilder.BuildAIData(targetPid, targetUniqueIndex, action, posX, posY, posZ, distance, duration, shouldRepeat)
        LoadedCells[cellDescription].data.objectData[actorUniqueIndex].ai = aiData
        tableHelper.insertValueIfMissing(LoadedCells[cellDescription].data.packets.ai, actorUniqueIndex)
    end
end

local function moveNpcBetweenCells(cellDescription, uniqueIndex, newCellDescription, newX, newY, newZ, newRotZ)
    local temporaryLoadedCells = {}
    local cell = LoadedCells[cellDescription]
    if cell == nil then
        logicHandler.LoadCell(cellDescription)
        table.insert(temporaryLoadedCells, cellDescription)
    end

    logMessage("running moveNpcBetweenCells for uniqueIndex " .. uniqueIndex .. " from cell " .. cellDescription .. " to cell " .. newCellDescription)

    if newCellDescription ~= cell.description then
        -- If the new cell is not loaded, load it temporarily
        if LoadedCells[newCellDescription] == nil then
            logicHandler.LoadCell(newCellDescription)
            table.insert(temporaryLoadedCells, newCellDescription)
        end

        local newCell = LoadedCells[newCellDescription]

        -- Only proceed if this Actor is actually supposed to exist in this cell
        if cell.data.objectData[uniqueIndex] ~= nil then
            logMessage("moveNpcBetweenCells BP 1")
            -- Was this actor spawned in the old cell, instead of being a pre-existing actor?
            -- If so, delete it entirely from the old cell and make it get spawned in the new cell
            if tableHelper.containsValue(cell.data.packets.spawn, uniqueIndex) == true then
                logMessage("moveNpcBetweenCells BP 2a")
                -- If this object is based on a generated record, move its record link
                -- to the new cell
                local refId = cell.data.objectData[uniqueIndex].refId

                if logicHandler.IsGeneratedRecord(refId) then

                    local recordStore = logicHandler.GetRecordStoreByRecordId(refId)

                    if recordStore ~= nil then
                        newCell:AddLinkToRecord(recordStore.storeType, refId, uniqueIndex)
                        cell:RemoveLinkToRecord(recordStore.storeType, refId, uniqueIndex)
                    end

                    -- Send this generated record to every visitor in the new cell
                    for _, visitorPid in pairs(newCell.visitors) do
                        recordStore:LoadGeneratedRecords(visitorPid, recordStore.data.generatedRecords, { refId })
                    end
                end

                -- This actor won't exist at all for players who have not loaded the actor's original
                -- cell and were not online when it was first spawned, so send all of its details to them
                for _, player in pairs(Players) do
                    if tableHelper.containsValue(cell.visitors, player.pid) then
                        cell:LoadActorPackets(player.pid, cell.data.objectData, { uniqueIndex })
                    end
                end

                cell:MoveObjectData(uniqueIndex, newCell)

            -- Was this actor moved to the old cell from another cell?
            elseif tableHelper.containsValue(cell.data.packets.cellChangeFrom, uniqueIndex) == true then
                logMessage("moveNpcBetweenCells BP 2b")
                local originalCellDescription = cell.data.objectData[uniqueIndex].cellChangeFrom

                -- Is the new cell actually this actor's original cell?
                -- If so, move its data back and remove all of its cell change data
                if originalCellDescription == newCellDescription then
                    logMessage("moveNpcBetweenCells BP 3a")
                    cell:MoveObjectData(uniqueIndex, newCell)

                    tableHelper.removeValue(newCell.data.packets.cellChangeTo, uniqueIndex)
                    tableHelper.removeValue(newCell.data.packets.cellChangeFrom, uniqueIndex)
                    --tableHelper.removeValue(cell.data.packets.cellChangeFrom, uniqueIndex)

                    newCell.data.objectData[uniqueIndex].cellChangeTo = nil
                    newCell.data.objectData[uniqueIndex].cellChangeFrom = nil



                -- Otherwise, move its data to the new cell, delete it from the old cell, and update its
                -- information in its original cell
                else
                    logMessage("moveNpcBetweenCells BP 3b")
                    cell:MoveObjectData(uniqueIndex, newCell)

                    -- If the original cell is not loaded, load it temporarily
                    if LoadedCells[originalCellDescription] == nil then
                        logicHandler.LoadCell(originalCellDescription)
                        table.insert(temporaryLoadedCells, originalCellDescription)
                    end

                    local originalCell = LoadedCells[originalCellDescription]

                    if originalCell.data.objectData[uniqueIndex] ~= nil then
                        originalCell.data.objectData[uniqueIndex].cellChangeTo = newCellDescription
                    end
                end

            -- Otherwise, simply move this actor's data to the new cell and mark it as being moved there
            -- in its old cell, as long as it's not supposed to already be in the new cell
            elseif cell.data.objectData[uniqueIndex].cellChangeTo ~= newCellDescription then
                logMessage("moveNpcBetweenCells BP 2c")
                cell:MoveObjectData(uniqueIndex, newCell)

                table.insert(cell.data.packets.cellChangeTo, uniqueIndex)

                if cell.data.objectData[uniqueIndex] == nil then
                    cell.data.objectData[uniqueIndex] = {}
                end

                cell.data.objectData[uniqueIndex].cellChangeTo = newCellDescription

                table.insert(newCell.data.packets.cellChangeFrom, uniqueIndex)

                newCell.data.objectData[uniqueIndex].cellChangeFrom = cell.description

                if newCell.data.customVariables == nil then newCell.data.customVariables = {} end
                if newCell.data.customVariables.npcScheduling == nil then newCell.data.customVariables.npcScheduling = {} end
                tableHelper.insertValueIfMissing(newCell.data.customVariables.npcScheduling, cell.description)
            end

            if newCell.data.objectData[uniqueIndex] ~= nil then
                newCell.data.objectData[uniqueIndex].location = {
                    posX = newX,
                    posY = newY,
                    posZ = newZ,
                    rotX = 0,
                    rotY = 0,
                    rotZ = newRotZ or 0
                }
            end

            for pid, player in pairs(Players) do
                -- basically copied verbatim from LoadActorCellChanges
                local actorCount = 0
                tes3mp.ClearActorList()
                tes3mp.SetActorListPid(pid)
                tes3mp.SetActorListCell(cellDescription)
        
                local splitIndex = uniqueIndex:split("-")
                tes3mp.SetActorRefNum(splitIndex[1])
                tes3mp.SetActorMpNum(splitIndex[2])
        
                tes3mp.SetActorCell(newCellDescription)
        
                local location = LoadedCells[newCellDescription].data.objectData[uniqueIndex].location
        
                tes3mp.SetActorPosition(location.posX, location.posY, location.posZ)
                tes3mp.SetActorRotation(location.rotX, location.rotY, location.rotZ)
        
                tes3mp.AddActor()
        
                actorCount = actorCount + 1
        
                if actorCount > 0 then
                    tes3mp.SendActorCellChange()
                end
        
                for _, description in ipairs(temporaryLoadedCells) do
                    LoadedCells[description]:LoadActorCellChanges(pid, LoadedCells[description].data.objectData)
                end
            end
        end
    else
        -- npc in same cell, jsut different location
        -- This shouldn't be used, but it's here for safety
        -- And it seems it doesn't work properly anyway because the NPC vanishes
        cell.data.objectData[uniqueIndex].location = {
            posX = newX,
            posY = newY,
            posZ = newZ,
            rotX = 0,
            rotY = 0,
            rotZ = newRotZ or 0
        }
        for pid, player in pairs(Players) do
            cell:LoadActorPositions(pid, cell.data.objectData, {uniqueIndex})
        end
    end

    for _, description in ipairs(temporaryLoadedCells) do
        logicHandler.UnloadCell(description)
    end

    for i, entry in ipairs(moving) do
        if entry[2] == uniqueIndex then
            moving[i] = nil
        end
    end
    tableHelper.cleanNils(moving)

end

local function onCellChangeUpdate(cellDescription, refNum)
    local cell = LoadedCells[cellDescription]
    if cell.data.objectData[refNum] and not cell.data.objectData[refNum].deathState and tonumber(refNum:split("-")[1]) > 0 then
        local refId = cell.data.objectData[refNum].refId
        local targetHour = findCurrentScheduleEntry(refId)

        if isFinished(refId, targetHour) then
            -- play animations
        elseif transitions[refId] then
            -- run console command for special movement
        end
    end
end

local function updateNpc(cellDescription, refNum)
    logMessage("--updateNpc BP 1")
    if tonumber(refNum:split("-")[1]) > 0 then -- use only plugin placed actors
        local tempLoad
        if LoadedCells[cellDescription] == nil then
            logicHandler.LoadCell(cellDescription)
            tempLoad = true
        end
        local cell = LoadedCells[cellDescription]

        if cell.data.objectData[refNum] and not cell.data.objectData[refNum].deathState then
            local refId = cell.data.objectData[refNum].refId
            
            if config[refId] == nil then
                if tempLoad == true then logicHandler.UnloadCell(cellDescription) end
                return
            end
            logMessage("--updateNpc BP 1.5")

            local targetHour = findCurrentScheduleEntry(refId)
            logMessage("--targetHour is " .. tostring(targetHour) )
            if targetHour ~= nil then
                local targetTable = getTargetTable(refId, targetHour)
                if not isFinished(refId, targetHour) then
                    if not atFinalDestination(cellDescription, refNum, targetTable) then
                        logMessage("--updateNpc BP 2a")
                        if atTempDestination(cellDescription, refNum) then -- NPC has paused near load door; should be moved to new cell and AItravel to final destination
                            logMessage("--updateNpc BP 3a")
                            local newCellDescription = targetTable.cell
                            local newCell = LoadedCells[newCellDescription]
                            local useTempLoad
                            if newCell == nil then
                                logicHandler.LoadCell(newCellDescription)
                                useTempLoad = true
                            end

                            if transitions[refId].openSound then
                                for _, pid in ipairs(LoadedCells[cellDescription].visitors) do
                                    playSoundFromObject(pid, cellDescription, refNum, transitions[refId].openSound)
                                end
                            end

                            moveNpcBetweenCells(cellDescription, refNum, newCellDescription, transitions[refId].destX, transitions[refId].destY, transitions[refId].destZ, transitions[refId].destRotZ)
                            safelySetActorAI(newCellDescription, refNum, enumerations.ai.TRAVEL, nil, nil, targetTable.posX, targetTable.posY, targetTable.posZ)

                            if transitions[refId].openSound then
                                for _, pid in ipairs(LoadedCells[newCellDescription].visitors) do
                                    playSoundFromObject(pid, newCellDescription, refNum, transitions[refId].closeSound or transitions[refId].openSound)
                                end
                            end

                            transitions[refId] = nil

                            for i, entry in ipairs(moving) do
                                if entry[2] == refNum then
                                    moving[i] = nil
                                end
                            end
                            tableHelper.cleanNils(moving)

                            if useTempLoad then
                                logicHandler.UnloadCell(newCellDescription)
                            end
                        else -- If in the same cell, just move to final destination; if not, set temporary destination near load door and move to that; if a load door can't be found, just teleport npc to target
                            local newCellDescription = targetTable.cell
                            if LoadedCells[cellDescription]:GetVisitorCount() > 0 then
                                if transitions[refId] == nil then -- swap this logic wtih the getvisitorcount line
                                    logMessage("--updateNpc BP 3b")
                                    if ( string.match(newCellDescription, patterns.exteriorCell) and LoadedCells[cellDescription].isExterior ) or cellDescription == targetTable.cell then
                                        logicHandler.SetAIForActor(cell, refNum, enumerations.ai.TRAVEL, nil, nil, targetTable.posX, targetTable.posY, targetTable.posZ)
                                    else -- create a temporary destination oh boy
                                        -- add automatic teleporting for NPCs in a cell without players in it  

                                        local targetDoorRefNum = findLoadDoorToCell(cellDescription, newCellDescription, targetTable.posX, targetTable.posY, targetTable.posZ) -- to do: rework recursively to allow travel through multiple cells, returning a list of cellDescriptions and refNums; put below bits in a loop
                                        if targetDoorRefNum then
                                            logMessage("--updateNpc BP 4a")
                                            local targetX, targetY, targetZ = unpack(findDoorMarkerNearestToDoor(cellDescription, targetDoorRefNum))
                                            local destX, destY, destZ, destRotZ = unpack(getDoorDestinationCoordinates(cellDescription, targetDoorRefNum))
                                            local openSound, closeSound = unpack(getDoorSound(cellDescription, targetDoorRefNum))

                                            if targetX == nil or destX == nil then
                                                logMessage("Marker coordinates could not be found!")
                                                moveNpcBetweenCells(cellDescription, refNum, newCellDescription, targetTable.posX, targetTable.posY, targetTable.posZ)
                                            else

                                                transitions[refId] = {}
                                                transitions[refId].posX = targetX
                                                transitions[refId].posY = targetY
                                                transitions[refId].posZ = targetZ
                                                transitions[refId].openSound = openSound
                                                transitions[refId].closeSound = closeSound
                                                transitions[refId].destX = destX
                                                transitions[refId].destY = destY
                                                transitions[refId].destZ = destZ - 40
                                                transitions[refId].destRotZ = - math.rad(destRotZ)

                                                tableHelper.insertValueIfMissing(moving, {cellDescription, refNum})

                                                logicHandler.SetAIForActor(cell, refNum, enumerations.ai.TRAVEL, nil, nil, targetX, targetY, targetZ)
                                            end
                                        
                                        else -- no valid load door can be found, so just teleport npc to destination
                                            logMessage("--updateNpc BP 4b")
                                            moveNpcBetweenCells(cellDescription, refNum, newCellDescription, targetTable.posX, targetTable.posY, targetTable.posZ)
                                        end
                                    end
                                end
                            else -- Here add logic for transitions from a cell without players
                                if ( string.match(newCellDescription, patterns.exteriorCell) and LoadedCells[cellDescription].isExterior ) or cellDescription == targetTable.cell then
                                    logMessage("--updateNpc BP 5a")
                                    local aiData = dataTableBuilder.BuildAIData(nil, nil, enumerations.ai.TRAVEL, targetTable.posX, targetTable.posY, targetTable.posZ, nil, nil, nil)

                                    LoadedCells[newCellDescription].data.objectData[refNum].ai = aiData
                                    tableHelper.insertValueIfMissing(LoadedCells[newCellDescription].data.packets.ai, refNum)
                                else
                                    logMessage("--updateNpc BP 5b")
                                    local targetDoorRefNum = findLoadDoorToCell(cellDescription, newCellDescription, targetTable.posX, targetTable.posY, targetTable.posZ) -- also set this up for recursion
                                    transitions[refId] = nil
                                    if targetDoorRefNum then
                                        local destX, destY, destZ, destRotZ = unpack(getDoorDestinationCoordinates(cellDescription, targetDoorRefNum))
                                        local useTempLoad
                                        if LoadedCells[newCellDescription] == nil then
                                            logicHandler.LoadCell(newCellDescription)
                                            useTempLoad = true
                                        end
                                        moveNpcBetweenCells(cellDescription, refNum, newCellDescription, destX, destY, destZ - 40, destRotZ)
                                        safelySetActorAI(newCellDescription, refNum, enumerations.ai.TRAVEL, nil, nil, targetTable.posX, targetTable.posY, targetTable.posZ)
                                        if useTempLoad then
                                            logicHandler.UnloadCell(newCellDescription)
                                        end
                                    else
                                        moveNpcBetweenCells(cellDescription, refNum, newCellDescription, targetTable.posX, targetTable.posY, targetTable.posZ)
                                    end
                                end

                                
                            end
                        end
                    else
                        logMessage("--updateNpc BP 2b (finished)")
                        if finished[targetHour] == nil then
                            finished[targetHour] = {}
                        end 
                        tableHelper.insertValueIfMissing(finished[targetHour], refId)

                        tableHelper.removeValue(moving, {cellDescription, refNum})
                        tableHelper.cleanNils(moving)

                        if targetTable.final then
                            if targetTable.final.kind == "WANDER" then
                                safelySetActorAI(cellDescription, refNum, enumerations.ai.WANDER, nil, nil, nil, nil, nil, targetTable.final.distance or 1024, 1)
                            elseif targetTable.final.kind == "ANIMATION" and targetTable.final.animGroup then
                                tes3mp.ClearRecords()
                                if dataFilesLoader.getRecord(refId, "Npc") then
                                    tes3mp.SetRecordType(enumerations.recordType.NPC)
                                elseif dataFilesLoader.getRecord(refId, "Creature") then -- Useful if you want to play an animation on a biped creature
                                    tes3mp.SetRecordType(enumerations.recordType.CREATURE)
                                end
                                tes3mp.SetRecordId(refId)
                                tes3mp.SetRecordBaseId(refId)
                                tes3mp.SetRecordModel(targetTable.final.model)
                                tes3mp.AddRecord()
                                tes3mp.SendRecordDynamic(next(Players), true)
                                
                                if targetTable.final.posX or targetTable.final.posY or targetTable.final.posZ or targetTable.final.rotZ then
                                    LoadedCells[cellDescription].data.objectData[refNum].location = {
                                        posX = targetTable.final.posX,
                                        posY = targetTable.final.posY,
                                        posZ = targetTable.final.posZ,
                                        rotX = 0,
                                        rotY = 0,
                                        rotZ = targetTable.final.rotZ or 0
                                    }
                                    for _, pid in ipairs(LoadedCells[cellDescription].visitors) do
                                        LoadedCells[cellDescription]:LoadActorPositions(pid, LoadedCells[cellDescription].data.objectData, {refNum})
                                    end
                                end

                                safelySetActorAI(cellDescription, refNum, enumerations.ai.WANDER, nil, nil, nil, nil, nil, 0, 24)
                               
                                -- run animation for all players currently in cell, then add a cell change handler to load this stuff for players entering a cell
                                if LoadedCells[cellDescription]:GetAuthority() then
                                    logicHandler.RunConsoleCommandOnObject(LoadedCells[cellDescription]:GetAuthority(), refId .. "-> setHello 0", cellDescription, refNum, true)
                                    logicHandler.RunConsoleCommandOnObject(LoadedCells[cellDescription]:GetAuthority(), refId .. "-> playgroup " .. targetTable.final.animGroup .. " 1", cellDescription, refNum, true)
                                end

                            end
                        end
                    end
                end
            end
        end
        if tempLoad == true then logicHandler.UnloadCell(cellDescription) end
    end
end

local function updateCellNpcs(cellDescription)
    for _, refNum in ipairs(LoadedCells[cellDescription].data.packets.actorList) do
        logMessage("-updating NPC " .. refNum .. " in cell " .. cellDescription)
        updateNpc(cellDescription, refNum)
    end

    local temporaryLoadedCells = {}
    
    for _, refNum in ipairs(LoadedCells[cellDescription].data.packets.cellChangeTo) do
        if not LoadedCells[LoadedCells[cellDescription].data.packets.cellChangeTo] then -- don't update the NPC twice if they are in two loaded cells
            logMessage("-updating NPC " .. refNum .. " in cell " .. cellDescription .. " (has moved to another cell)")
            if cellReset and cellReset.TryResetCell then -- Compatibility with atkana's cell reset; don't want to cause duplicated NPCs
                cellReset.TryResetCell(LoadedCells[cellDescription].data.objectData[refNum].cellChangeTo)
            end
            if LoadedCells[LoadedCells[cellDescription].data.objectData[refNum].cellChangeTo] == nil then
                logicHandler.LoadCell(cellDescription)
                table.insert(temporaryLoadedCells, LoadedCells[cellDescription].data.objectData[refNum].cellChangeTo)
            end

            updateNpc(LoadedCells[cellDescription].data.objectData[refNum].cellChangeTo, refNum)

        end
    end

    if LoadedCells[cellDescription].data.customVariables and LoadedCells[cellDescription].data.customVariables.npcScheduling then
        for _, newCellDescription in ipairs(LoadedCells[cellDescription].data.customVariables.npcScheduling) do
            if not LoadedCells[newCellDescription] then
                if cellReset and cellReset.TryResetCell then -- Compatibility with atkana's cell reset; don't want to cause duplicated NPCs
                    cellReset.TryResetCell(newCellDescription)
                end
                if LoadedCells[newCellDescription] == nil then
                    logicHandler.LoadCell(newCellDescription)
                    table.insert(temporaryLoadedCells, newCellDescription)
                end
                for _, refNum in ipairs(LoadedCells[newCellDescription].data.packets.actorList) do
                    logMessage("-updating NPC " .. refNum .. " in cell " .. newCellDescription)
                    updateNpc(newCellDescription, refNum)
                end
                
            end
        end
    end

    for _, description in ipairs(temporaryLoadedCells) do
        logicHandler.UnloadCell(description)
    end
end

local function onCellLoadHandler(eventStatus, pid, cellDescription)
    if Players[pid]:IsLoggedIn() then
        local cell = LoadedCells[cellDescription]
        if cell.data.loadState.hasFullActorList then -- check to make sure the cell knows what actors are in it; if it doesn't, wait and handle this stuff when it does
            logMessage("running updateCellNpcs called by onCellLoadHandler")
            updateCellNpcs(cellDescription)
        end
    end
end

local function onActorListHandler(eventStatus, pid, cellDescription, _)
    if Players[pid]:IsLoggedIn() then
        logMessage("running updateCellNpcs called by onActorListHandler")
        LoadedCells[cellDescription]:SaveActorPositions()
        updateCellNpcs(cellDescription)
    end
end

local function onGameHourHandler(eventStatus)
    for cellDescription, cell in pairs(LoadedCells) do
        updateCellNpcs(cellDescription)
    end
end

customEventHooks.registerHandler("OnCellLoad", onCellLoadHandler)
customEventHooks.registerHandler("OnActorList", onActorListHandler)
customEventHooks.registerHandler("AotS_OnGameHour", onGameHourHandler)

function NPC_Scheduling_Timer()
    for i, data in ipairs(moving) do
        if LoadedCells[data[1]] then
            logMessage("updating moving npc " .. data[2] .. " in cell " .. data[1])
            updateNpc(data[1], data[2])
        end
    end
    tes3mp.RestartTimer(timerId, time.seconds(3))
end

customEventHooks.registerHandler("OnServerPostInit", function()




    timerId = tes3mp.CreateTimer("NPC_Scheduling_Timer", time.seconds(3))
    tes3mp.StartTimer(timerId)
end)

customEventHooks.registerHandler("OnActorDeath", function(eventStatus, pid, cellDescription, actors)
    for uniqueIndex, actor in pairs(actors) do
        tableHelper.removeValue(moving, {cellDescription, uniqueIndex})
        tableHelper.cleanNils(moving)
    end
end)