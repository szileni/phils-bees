local RSGCore = exports['rsg-core']:GetCoreObject()
local activeApiaries = {}
local coordsApiaries = {}
local collecting = false
local beeEffects = {}
local apiaryData = {}
local isWearingBandana = false -- Track bandana status
local lastBeeStingNotify = 0
local function LoadModel(model)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    if not IsModelValid(hash) then return false end
    if not HasModelLoaded(hash) then
        RequestModel(hash)
        local timeout = 0
        while not HasModelLoaded(hash) and timeout < 500 do
            Wait(10)
            timeout = timeout + 1
        end
    end
    return HasModelLoaded(hash)
end

local function LoadAnimDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        local timeout = 0
        while not HasAnimDictLoaded(dict) and timeout < 500 do
            Wait(10)
            timeout = timeout + 1
        end
    end
    return HasAnimDictLoaded(dict)
end

local function FormatTimeRemaining(milliseconds)
    local seconds = math.floor(milliseconds / 1000)
    local minutes = math.floor(seconds / 60)
    local hours = math.floor(minutes / 60)
    
    if hours > 0 then
        return string.format("%d hours, %d minutes", hours, minutes % 60)
    elseif minutes > 0 then
        return string.format("%d minutes, %d seconds", minutes, seconds % 60)
    else
        return string.format("%d seconds", seconds)
    end
end

local function IsValidLocation(x, y, z)
    for _, coords in pairs(coordsApiaries) do
        local dist = #(vector3(x, y, z) - coords)
        if dist < 2.0 then
            return false
        end
    end
    return true
end

local function PlaceApiary()
    local playerPed = PlayerPedId()
    local pos = GetEntityCoords(playerPed)
    local ground, posZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z, true)
    if not ground then 
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = Config.Text.invalid_location
        })
        return 
    end
    
    local offset = 2.0
    local x = pos.x + offset * math.sin(math.rad(-GetEntityHeading(playerPed)))
    local y = pos.y + offset * math.cos(math.rad(-GetEntityHeading(playerPed)))
    
    if not IsValidLocation(x, y, posZ) then
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = Config.Text.invalid_location
        })
        return
    end
    
    local apiaryModel = Config.Apiaries[1]
    if not LoadModel(apiaryModel.model) then 
        return 
    end
    
    if LoadAnimDict(Config.Anim.placingDict) then
        TaskPlayAnim(playerPed, Config.Anim.placingDict, Config.Anim.placingName, 8.0, -1.0, Config.Anim.placingDuration, 0, 0, true, 0, false, 0, false)
        Wait(Config.Anim.placingDuration)
        ClearPedTasks(playerPed)
    end
    
    local entity = CreateObject(apiaryModel.hash, x, y, posZ, true, false, true)
    SetModelAsNoLongerNeeded(apiaryModel.hash)
    
    PlaceObjectOnGroundProperly(entity)
    SetEntityAsMissionEntity(entity, true, true)
    FreezeEntityPosition(entity, true)
    
    local netId = ObjToNet(entity)
    table.insert(activeApiaries, entity)
    table.insert(coordsApiaries, GetEntityCoords(entity))
    
    apiaryData[netId] = {
        materials = false,
        timeStarted = 0,
        isReady = false,
        honeyframePlaced = 0
    }
    
    local entityCoords = GetEntityCoords(entity)
    TriggerServerEvent('rsg-apiary:registerApiary', netId, {
        x = entityCoords.x,
        y = entityCoords.y,
        z = entityCoords.z
    })
    
    return netId
end

local function AddMaterials(entity)
    if collecting then return end
    collecting = true
    
    local playerPed = PlayerPedId()
    local netId = ObjToNet(entity)
    
    if not apiaryData[netId] then
        apiaryData[netId] = {
            materials = false,
            timeStarted = 0,
            isReady = false,
            honeyframePlaced = 0
        }
    end
    
    if apiaryData[netId].materials then
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = Config.Text.not_ready
        })
        collecting = false
        return
    end
    
    if LoadAnimDict(Config.Anim.dict) then
        TaskPlayAnim(playerPed, Config.Anim.dict, Config.Anim.name, 8.0, -1.0, Config.Anim.duration, 0, 0, true, 0, false, 0, false)
        Wait(Config.Anim.duration)
        ClearPedTasks(playerPed)
    end
    
    TriggerServerEvent('rsg-apiary:addMaterials', netId)
    collecting = false
end

local function CheckApiaryStatus(entity)
    local netId = ObjToNet(entity)
    
    if not apiaryData[netId] then
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = 'No data available for this beehive.'
        })
        return
    end
    
    local data = apiaryData[netId]
    local status = "Empty"
    local timeInfo = "Not started"
    local materialsInfo = "No materials added"
    
    if data.materials then
        materialsInfo = string.format("honeyframe: %d/%d", data.honeyframePlaced or Config.Materials[1].amount, Config.Materials[1].amount)
        
        if data.isReady then
            status = "Ready to collect"
            timeInfo = "Honey production complete"
        else
            status = "Producing honey"
            local currentTime = GetGameTimer()
            local elapsedTime = currentTime - data.timeStarted
            local remainingTime = math.max(0, (Config.ProductionTime * 60000) - elapsedTime)
            timeInfo = "Time remaining: " .. FormatTimeRemaining(remainingTime)
        end
    end
    
    lib.registerContext({
        id = 'apiary_status_menu',
        title = 'Beehive Status',
        options = {
            {
                title = 'Status',
                description = status,
                icon = 'fas fa-info-circle'
            },
            {
                title = 'Materials',
                description = materialsInfo,
                icon = 'fas fa-tree'
            },
            {
                title = 'Production Time',
                description = timeInfo,
                icon = 'fas fa-clock'
            }
        }
    })
    
    lib.showContext('apiary_status_menu')
end

local function CollectHoney(entity)
    if collecting then return end
    collecting = true
    
    local playerPed = PlayerPedId()
    local netId = ObjToNet(entity)
    
    if not apiaryData[netId] or not apiaryData[netId].isReady then
        local timeRemaining = 0
        if apiaryData[netId] and apiaryData[netId].timeStarted > 0 then
            local elapsedTime = GetGameTimer() - apiaryData[netId].timeStarted
            timeRemaining = math.ceil((Config.ProductionTime * 60000 - elapsedTime) / 60000)
        end
        
        if timeRemaining > 0 then
            TriggerEvent('ox_lib:notify', {
                type = 'error',
                title = Config.Text.beekeeper,
                description = string.format(Config.Text.time_remaining, timeRemaining)
            })
        else
            TriggerEvent('ox_lib:notify', {
                type = 'error',
                title = Config.Text.beekeeper,
                description = Config.Text.not_ready
            })
        end
        
        collecting = false
        return
    end
    
    if LoadAnimDict(Config.Anim.dict) then
        TaskPlayAnim(playerPed, Config.Anim.dict, Config.Anim.name, 8.0, -1.0, Config.Anim.duration, 0, 0, true, 0, false, 0, false)
        Wait(Config.Anim.duration)
        ClearPedTasks(playerPed)
    end
    
    TriggerServerEvent('rsg-apiary:collectHoney', netId)
    apiaryData[netId].materials = false
    apiaryData[netId].timeStarted = 0
    apiaryData[netId].isReady = false
    apiaryData[netId].honeyframePlaced = 0
    
    collecting = false
end

local function ManageBeeEffect(entity, coords)
    local entityHandle = entity
    local group = Config.BeeParticle.group
    local name = Config.BeeParticle.name

    if not Citizen.InvokeNative(0x65BB72F29138F5D6, GetHashKey(group)) then
        Citizen.InvokeNative(0xF2B2353BBC0D4E8F, GetHashKey(group))
        local counter = 0
        while not Citizen.InvokeNative(0x65BB72F29138F5D6, GetHashKey(group)) and counter <= 300 do
            Wait(0)
            counter = counter + 1
        end
    end

    if Citizen.InvokeNative(0x65BB72F29138F5D6, GetHashKey(group)) then
        Citizen.InvokeNative(0xA10DB07FC234DD12, group)
        local effectId = Citizen.InvokeNative(0xBA32867E86125D3A, name, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
        beeEffects[entityHandle] = effectId
    else
        print('Failed to load bee particle dictionary!')
    end
end

local function StopBeeEffect(entity)
    local entityHandle = entity
    if beeEffects[entityHandle] then
        if Citizen.InvokeNative(0x9DD5AFF561E88F2A, beeEffects[entityHandle]) then
            Citizen.InvokeNative(0x459598F579C98929, beeEffects[entityHandle], false)
        end
        beeEffects[entityHandle] = nil
    end
end

local function PickupApiary(entity)
    if collecting then return end
    collecting = true
    
    local playerPed = PlayerPedId()
    local netId = ObjToNet(entity)
    
    if LoadAnimDict(Config.Anim.placingDict) then
        TaskPlayAnim(playerPed, Config.Anim.placingDict, Config.Anim.placingName, 8.0, -1.0, Config.Anim.placingDuration, 0, 0, true, 0, false, 0, false)
        Wait(Config.Anim.placingDuration)
        ClearPedTasks(playerPed)
    end
    
    TriggerServerEvent('rsg-apiary:pickup', netId)
    
    for i, ent in ipairs(activeApiaries) do
        if ent == entity then
            table.remove(activeApiaries, i)
            table.remove(coordsApiaries, i)
            break
        end
    end
    
    StopBeeEffect(entity)
    apiaryData[netId] = nil
    
    collecting = false
end

local function SetupTarget()
    exports.ox_target:addModel(Config.Apiaries[1].hash, {
        {
            name = 'add_materials_apiary',
            icon = 'fas fa-box',
            label = Config.Text.add_materials,
            distance = Config.InteractDistance,
            onSelect = function(data)
                local netId = ObjToNet(data.entity)
                if not apiaryData[netId] or not apiaryData[netId].materials then
                    AddMaterials(data.entity)
                end
            end,
            canInteract = function(entity)
                local netId = ObjToNet(entity)
                return (not apiaryData[netId] or not apiaryData[netId].materials) and not IsPedOnMount(PlayerPedId()) and not IsPedInAnyVehicle(PlayerPedId())
            end
        },
        {
            name = 'collect_apiary',
            icon = 'fas fa-hand-holding',
            label = Config.Text.collect,
            distance = Config.InteractDistance,
            onSelect = function(data)
                local netId = ObjToNet(data.entity)
                if apiaryData[netId] and apiaryData[netId].isReady then
                    CollectHoney(data.entity)
                end
            end,
            canInteract = function(entity)
                local netId = ObjToNet(entity)
                return apiaryData[netId] and apiaryData[netId].isReady and not IsPedOnMount(PlayerPedId()) and not IsPedInAnyVehicle(PlayerPedId())
            end
        },
        {
            name = 'check_apiary_status',
            icon = 'fas fa-search',
            label = Config.Text.check_status,
            distance = Config.InteractDistance,
            onSelect = function(data)
                CheckApiaryStatus(data.entity)
            end,
            canInteract = function()
                return not IsPedOnMount(PlayerPedId()) and not IsPedInAnyVehicle(PlayerPedId())
            end
        },
        {
            name = 'pickup_apiary',
            icon = 'fas fa-hand-paper',
            label = 'Pick Up Beehive',
            distance = Config.InteractDistance,
            onSelect = function(data)
                PickupApiary(data.entity)
            end,
            canInteract = function(entity)
                local netId = ObjToNet(entity)
                return (not apiaryData[netId] or not apiaryData[netId].materials) and not IsPedOnMount(PlayerPedId()) and not IsPedInAnyVehicle(PlayerPedId())
            end
        }
    })
end


RegisterNetEvent('bandanaStatusChanged')
AddEventHandler('bandanaStatusChanged', function(status)
    isWearingBandana = status
end)

Citizen.CreateThread(function()
    while true do
        Wait(10000) 
        local currentTime = GetGameTimer()
        
        for netId, data in pairs(apiaryData) do
            if data.materials and data.timeStarted > 0 and not data.isReady then
                local elapsedTime = currentTime - data.timeStarted
                if elapsedTime >= (Config.ProductionTime * 60000) then 
                    apiaryData[netId].isReady = true
                end
            end
        end
    end
end)

Citizen.CreateThread(function()
    local lastBeeStingNotify = 0 
    local lastDamageTime = 0 
    
    while true do
        Wait(1000) 
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local currentTime = GetGameTimer()
        
        
        for _, entity in pairs(activeApiaries) do
            if DoesEntityExist(entity) then
                local coords = GetEntityCoords(entity)
                local dist = #(playerCoords - coords)
                
                if dist <= Config.BeeDistance then
                    if not beeEffects[entity] then
                        ManageBeeEffect(entity, coords)
                    end
                    
                    if not isWearingBandana and not IsPedOnMount(playerPed) and not IsPedInAnyVehicle(playerPed) then
                        if currentTime - lastDamageTime >= Config.BeeDamageInterval then
                            local health = GetEntityHealth(playerPed)
                            local newHealth = math.max(0, health - Config.BeeDamageAmount)
                            SetEntityHealth(playerPed, newHealth)
                            lastDamageTime = currentTime
                            
                           
                            if currentTime - lastBeeStingNotify >= 10000 then
                                TriggerEvent('ox_lib:notify', {
                                    type = 'warning',
                                    title = Config.Text.beekeeper,
                                    description = Config.Text.bee_sting
                                })
                                lastBeeStingNotify = currentTime
                            end
                        end
                    end
                else
                    StopBeeEffect(entity)
                end
            end
        end
    end
end)

RegisterNetEvent('rsg-apiary:pickupSuccess')
AddEventHandler('rsg-apiary:pickupSuccess', function(netId)
    local entity = NetToObj(netId)
    if DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteObject(entity)
        TriggerEvent('ox_lib:notify', {
            type = 'success',
            title = Config.Text.beekeeper,
            description = 'You picked up a beehive'
        })
    end
end)

RegisterNetEvent('rsg-apiary:registerExistingApiary')
AddEventHandler('rsg-apiary:registerExistingApiary', function(netId, coords)
    print("Received existing apiary with netId: " .. netId)
    
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(entity) then
        local model = Config.Apiaries[1].model
        local hash = GetHashKey(model)
        
        if not HasModelLoaded(hash) then
            RequestModel(hash)
            local timeout = 0
            while not HasModelLoaded(hash) and timeout < 500 do
                Wait(10)
                timeout = timeout + 1
            end
        end
        
        entity = CreateObject(hash, coords[1], coords[2], coords[3], false, false, true)
        SetEntityAsMissionEntity(entity, true, true)
        FreezeEntityPosition(entity, true)
        
        table.insert(activeApiaries, entity)
        table.insert(coordsApiaries, vector3(coords[1], coords[2], coords[3]))
    else
        local alreadyTracked = false
        for _, existingEntity in ipairs(activeApiaries) do
            if existingEntity == entity then
                alreadyTracked = true
                break
            end
        end
        
        if not alreadyTracked then
            table.insert(activeApiaries, entity)
            table.insert(coordsApiaries, GetEntityCoords(entity))
        end
    end
end)

RegisterNetEvent('rsg-apiary:spawn')
AddEventHandler('rsg-apiary:spawn', function()
    if #activeApiaries < Config.MaxApiaries then
        PlaceApiary()
    else
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = 'You can only have ' .. Config.MaxApiaries .. ' apiaries at once.'
        })
    end
end)

RegisterNetEvent('rsg-apiary:materialAdded')
AddEventHandler('rsg-apiary:materialAdded', function(netId, honeyframeAmount)
    if not apiaryData[netId] then
        apiaryData[netId] = {
            materials = false,
            timeStarted = 0,
            isReady = false,
            honeyframePlaced = 0
        }
    end
    
    apiaryData[netId].materials = true
    apiaryData[netId].timeStarted = GetGameTimer()
    apiaryData[netId].isReady = false
    apiaryData[netId].honeyframePlaced = honeyframeAmount
end)

RegisterNetEvent('rsg-apiary:syncApiaries')
AddEventHandler('rsg-apiary:syncApiaries', function(serverApiaryData)
    for netId, data in pairs(serverApiaryData) do
        if data.timeStarted > 0 then
            local serverElapsedSeconds = os.time() - data.timeStarted
            local clientTimeStarted = GetGameTimer() - (serverElapsedSeconds * 1000)
            
            apiaryData[netId] = {
                materials = data.materials,
                timeStarted = clientTimeStarted,
                isReady = data.isReady,
                honeyframePlaced = data.honeyframePlaced
            }
        else
            apiaryData[netId] = data
        end
    end
end)

RegisterNetEvent('rsg-apiary:delete')
AddEventHandler('rsg-apiary:delete', function(netId)
    local entity = NetToObj(netId)
    if DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteObject(entity)
        
        for i, ent in ipairs(activeApiaries) do
            if ent == entity then
                table.remove(activeApiaries, i)
                table.remove(coordsApiaries, i)
                break
            end
        end
        
        apiaryData[netId] = nil
    end
end)

Citizen.CreateThread(function()
    Wait(2000)
    SetupTarget()
    TriggerServerEvent('rsg-apiary:requestSync')
end)
