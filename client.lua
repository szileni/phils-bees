local RSGCore = exports['rsg-core']:GetCoreObject()
local activeApiaries = {} 
local collecting = false
local beeEffects = {}
local isWearingBandana = false
local lastBeeStingNotify = 0

local function LoadModel(model)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    if not IsModelValid(hash) then 
        
        return false 
    end
    if not HasModelLoaded(hash) then
        RequestModel(hash)
        local timeout = 0
        while not HasModelLoaded(hash) and timeout < 1000 do
            Wait(1)
            timeout = timeout + 1
        end
        if not HasModelLoaded(hash) then
            
            return false
        end
    end
    
    return true
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
    
    
    local coords = {x = x, y = y, z = posZ}
    TriggerServerEvent('rsg-apiary:checkLocation', coords)
    
    
    local validLocation = nil
    local timeout = 0
    local responseHandler = nil
    
    responseHandler = function(isValid)
        validLocation = isValid
        RemoveEventHandler('rsg-apiary:locationResponse', responseHandler)
    end
    
    RegisterNetEvent('rsg-apiary:locationResponse')
    AddEventHandler('rsg-apiary:locationResponse', responseHandler)
    
    while validLocation == nil and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end
    
    if not validLocation then
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = Config.Text.invalid_location
        })
        return
    end
    
    local apiaryModel = Config.Apiaries[1]
    local model = apiaryModel.model
    if not LoadModel(model) then 
        model = 'p_campfire01x' 
        if not LoadModel(model) then
            TriggerEvent('ox_lib:notify', {
                type = 'error',
                title = Config.Text.beekeeper,
                description = 'Failed to load apiary model and fallback model.'
            })
            return 
        end
       
    end
    
    if LoadAnimDict(Config.Anim.placingDict) then
        TaskPlayAnim(playerPed, Config.Anim.placingDict, Config.Anim.placingName, 8.0, -1.0, Config.Anim.placingDuration, 0, 0, true, 0, false, 0, false)
        Wait(Config.Anim.placingDuration)
        ClearPedTasks(playerPed)
    end
    
    local entity = CreateObject(GetHashKey(model), x, y, posZ, true, false, true)
    if not DoesEntityExist(entity) then
       
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = 'Failed to create apiary.'
        })
        return
    end
    
    SetModelAsNoLongerNeeded(GetHashKey(model))
    PlaceObjectOnGroundProperly(entity)
    SetEntityAsMissionEntity(entity, true, true)
    FreezeEntityPosition(entity, true)
    
    local netId = ObjToNet(entity)
    if not netId then
        print('Error: Failed to get netId for apiary entity with model ' .. model)
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = 'Failed to network apiary.'
        })
        DeleteObject(entity)
        return
    end
    
    
    table.insert(activeApiaries, {entity = entity, netId = netId, dbId = nil}) 
    
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
    local dbId = nil
    
    
    for _, apiary in ipairs(activeApiaries) do
        if apiary.netId == netId then
            dbId = apiary.dbId
            break
        end
    end
    
    if not dbId then
        print('Error: No dbId found for netId ' .. tostring(netId))
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = 'Apiary data not found.'
        })
        collecting = false
        return
    end
    
    if not LoadAnimDict(Config.Anim.dict) then
        print('Error: Failed to load animation dictionary: ' .. tostring(Config.Anim.dict))
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = 'Failed to load animation.'
        })
        collecting = false
        return
    end
    
    TaskPlayAnim(playerPed, Config.Anim.dict, Config.Anim.name, 8.0, -1.0, Config.Anim.duration, 0, 0, true, 0, false, 0, false)
    Wait(Config.Anim.duration)
    ClearPedTasks(playerPed)
    
    TriggerServerEvent('rsg-apiary:addMaterials', dbId)
    collecting = false
end

local function CheckApiaryStatus(entity)
    local netId = ObjToNet(entity)
    local dbId = nil
    
    for _, apiary in ipairs(activeApiaries) do
        if apiary.netId == netId then
            dbId = apiary.dbId
            break
        end
    end
    
    if not dbId then
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = 'No data available for this beehive.'
        })
        return
    end
    
    
    TriggerServerEvent('rsg-apiary:getStatus', dbId)
end

local function CollectHoney(entity)
    if collecting then return end
    collecting = true
    
    local playerPed = PlayerPedId()
    local netId = ObjToNet(entity)
    local dbId = nil
    
    for _, apiary in ipairs(activeApiaries) do
        if apiary.netId == netId then
            dbId = apiary.dbId
            break
        end
    end
    
    if not dbId then
        print('Error: No dbId found for netId ' .. tostring(netId))
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = 'No data available for this beehive.'
        })
        collecting = false
        return
    end
    
    if not LoadAnimDict(Config.Anim.dict) then
        print('Error: Failed to load animation dictionary: ' .. tostring(Config.Anim.dict))
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = 'Failed to load animation.'
        })
        collecting = false
        return
    end
    
    TaskPlayAnim(playerPed, Config.Anim.dict, Config.Anim.name, 8.0, -1.0, Config.Anim.duration, 0, 0, true, 0, false, 0, false)
    Wait(Config.Anim.duration)
    ClearPedTasks(playerPed)
    
    TriggerServerEvent('rsg-apiary:collectHoney', dbId)
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
    local dbId = nil
    
    for _, apiary in ipairs(activeApiaries) do
        if apiary.netId == netId then
            dbId = apiary.dbId
            break
        end
    end
    
    if not dbId then
        
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = 'No data available for this beehive.'
        })
        collecting = false
        return
    end
    
    if LoadAnimDict(Config.Anim.placingDict) then
        TaskPlayAnim(playerPed, Config.Anim.placingDict, Config.Anim.placingName, 8.0, -1.0, Config.Anim.placingDuration, 0, 0, true, 0, false, 0, false)
        Wait(Config.Anim.placingDuration)
        ClearPedTasks(playerPed)
    end
    
    TriggerServerEvent('rsg-apiary:pickup', dbId)
    collecting = false
end

local function SetupTarget()
    local model = Config.Apiaries[1].model
    local hash = GetHashKey(model)
    if not LoadModel(model) then
        model = 'p_campfire01x' -- Fallback model
        hash = GetHashKey(model)
        if not LoadModel(model) then
            
            return
        end
       
    end
    
    exports.ox_target:addModel(hash, {
        {
            name = 'add_materials_apiary',
            icon = 'fas fa-box',
            label = Config.Text.add_materials,
            distance = Config.InteractDistance,
            onSelect = function(data)
                AddMaterials(data.entity)
            end,
            canInteract = function(entity)
                return not IsPedOnMount(PlayerPedId()) and not IsPedInAnyVehicle(PlayerPedId())
            end
        },
        {
            name = 'collect_apiary',
            icon = 'fas fa-hand-holding',
            label = Config.Text.collect,
            distance = Config.InteractDistance,
            onSelect = function(data)
                CollectHoney(data.entity)
            end,
            canInteract = function(entity)
                return not IsPedOnMount(PlayerPedId()) and not IsPedInAnyVehicle(PlayerPedId())
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
                return not IsPedOnMount(PlayerPedId()) and not IsPedInAnyVehicle(PlayerPedId())
            end
        }
    })
end

RegisterNetEvent('bandanaStatusChanged')
AddEventHandler('bandanaStatusChanged', function(status)
    isWearingBandana = status
end)


Citizen.CreateThread(function()
    local lastDamageTime = 0 
    
    while true do
        Wait(1000) 
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local currentTime = GetGameTimer()
        
        for _, apiary in pairs(activeApiaries) do
            if DoesEntityExist(apiary.entity) then
                local coords = GetEntityCoords(apiary.entity)
                local dist = #(playerCoords - coords)
                
                if dist <= Config.BeeDistance then
                    if not beeEffects[apiary.entity] then
                        ManageBeeEffect(apiary.entity, coords)
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
                    StopBeeEffect(apiary.entity)
                end
            end
        end
    end
end)


RegisterNetEvent('rsg-apiary:pickupSuccess')
AddEventHandler('rsg-apiary:pickupSuccess', function(dbId)
    for i, apiary in ipairs(activeApiaries) do
        if apiary.dbId == dbId then
            if DoesEntityExist(apiary.entity) then
                SetEntityAsMissionEntity(apiary.entity, true, true)
                DeleteObject(apiary.entity)
                StopBeeEffect(apiary.entity)
            end
            table.remove(activeApiaries, i)
            TriggerEvent('ox_lib:notify', {
                type = 'success',
                title = Config.Text.beekeeper,
                description = 'You picked up a beehive'
            })
            break
        end
    end
end)

RegisterNetEvent('rsg-apiary:registerExistingApiary')
AddEventHandler('rsg-apiary:registerExistingApiary', function(dbId, netId, coords)
   
    if not dbId or not coords or not coords.x or not coords.y or not coords.z then
        
        return
    end
    
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(entity) then
        local model = Config.Apiaries[1].model
        print('Loading model: ' .. model)
        if not LoadModel(model) then
            model = 'p_campfire01x'
            
            if not LoadModel(model) then
                
                TriggerEvent('ox_lib:notify', {
                    type = 'error',
                    title = Config.Text.beekeeper,
                    description = 'Failed to load apiary model.'
                })
                return
            end
        end
        
        entity = CreateObject(GetHashKey(model), coords.x, coords.y, coords.z, true, false, true)
        if not DoesEntityExist(entity) then
            
            return
        end
        SetEntityAsMissionEntity(entity, true, true)
        PlaceObjectOnGroundProperly(entity)
        FreezeEntityPosition(entity, true)
        netId = ObjToNet(entity)
        if not netId then
            
            DeleteObject(entity)
            return
        end
       
    end
    
    local alreadyTracked = false
    for i, apiary in ipairs(activeApiaries) do
        if apiary.dbId == dbId then
          
            alreadyTracked = true
            break
        elseif apiary.netId == netId then
            
            activeApiaries[i].dbId = dbId
            alreadyTracked = true
            break
        end
    end
    
    if not alreadyTracked then
       
        table.insert(activeApiaries, {entity = entity, netId = netId, dbId = dbId})
    end
   
end)

RegisterNetEvent('rsg-apiary:spawn')
AddEventHandler('rsg-apiary:spawn', function()
    
    TriggerServerEvent('rsg-apiary:getPlayerApiaryCount')
end)

RegisterNetEvent('rsg-apiary:playerApiaryCount')
AddEventHandler('rsg-apiary:playerApiaryCount', function(count)
    if count < Config.MaxApiaries then
        PlaceApiary()
    else
        TriggerEvent('ox_lib:notify', {
            type = 'error',
            title = Config.Text.beekeeper,
            description = 'You can only have ' .. Config.MaxApiaries .. ' apiaries at once.'
        })
    end
end)

RegisterNetEvent('rsg-apiary:locationResponse')
AddEventHandler('rsg-apiary:locationResponse', function(isValid)
    
end)

RegisterNetEvent('rsg-apiary:materialAdded')
AddEventHandler('rsg-apiary:materialAdded', function(dbId, honeyframeAmount, timeStarted)
   
end)

RegisterNetEvent('rsg-apiary:statusResponse')
AddEventHandler('rsg-apiary:statusResponse', function(dbId, apiaryData)
    local status = "Empty"
    local timeInfo = "Not started"
    local materialsInfo = "No materials added"
    
    if apiaryData.materials then
        materialsInfo = string.format("honeyframe: %d/%d", apiaryData.honeyframePlaced or Config.Materials[1].amount, Config.Materials[1].amount)
        
        if apiaryData.isReady then
            status = "Ready to collect"
            timeInfo = "Honey production complete"
        else
            status = "Producing honey"
            local currentTime = GetGameTimer()
			local elapsedTime = currentTime - apiaryData.timeStarted
			local remainingTime = apiaryData.remainingTime or 0
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
end)

RegisterNetEvent('rsg-apiary:syncApiaries')
AddEventHandler('rsg-apiary:syncApiaries', function(serverApiaryData)
    for dbId, data in pairs(serverApiaryData) do
        if not data or not data.netId or not data.coords or not data.coords.x or not data.coords.y or not data.coords.z then
            
            return
        end
        
        local exists = false
        for _, apiary in ipairs(activeApiaries) do
            if apiary.dbId == dbId then
                exists = true
                break
            end
        end
        
        if not exists then
            local entity = NetworkGetEntityFromNetworkId(data.netId)
            if not DoesEntityExist(entity) then
                local model = Config.Apiaries[1].model
                if not LoadModel(model) then
                    model = 'p_campfire01x' 
                    if not LoadModel(model) then
                       
                        TriggerEvent('ox_lib:notify', {
                            type = 'error',
                            title = Config.Text.beekeeper,
                            description = 'Failed to load apiary model.'
                        })
                        return
                    end
                   
                end
                
                entity = CreateObject(GetHashKey(model), data.coords.x, data.coords.y, data.coords.z, true, false, true)
                if not DoesEntityExist(entity) then
                    
                    return
                end
                SetEntityAsMissionEntity(entity, true, true)
                PlaceObjectOnGroundProperly(entity)
                FreezeEntityPosition(entity, true)
                data.netId = ObjToNet(entity)
                if not data.netId then
                    
                    DeleteObject(entity)
                    return
                end
            end
            
            table.insert(activeApiaries, {entity = entity, netId = data.netId, dbId = dbId})
           
        end
    end
end)

RegisterNetEvent('rsg-apiary:delete')
AddEventHandler('rsg-apiary:delete', function(dbId)
    for i, apiary in ipairs(activeApiaries) do
        if apiary.dbId == dbId then
            if DoesEntityExist(apiary.entity) then
                SetEntityAsMissionEntity(apiary.entity, true, true)
                DeleteObject(apiary.entity)
                StopBeeEffect(apiary.entity)
            end
            table.remove(activeApiaries, i)
            break
        end
    end
end)

RegisterNetEvent('rsg-apiary:honeyCollected')
AddEventHandler('rsg-apiary:honeyCollected', function(dbId)
   
end)


Citizen.CreateThread(function()
    Wait(2000)
    SetupTarget()
    TriggerServerEvent('rsg-apiary:requestSync')
end)


AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for i = 1, #activeApiaries do
        local apiary = activeApiaries[i]
        if DoesEntityExist(apiary.entity) then
            SetEntityAsMissionEntity(apiary.entity, false)
            FreezeEntityPosition(apiary.entity, false)
            DeleteObject(apiary.entity)
            StopBeeEffect(apiary.entity)
        end
    end
    activeApiaries = {}
end)
