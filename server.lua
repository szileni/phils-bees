local RSGCore = exports['rsg-core']:GetCoreObject()
local apiaries = {}




RSGCore.Functions.CreateUseableItem(Config.ApiaryItem, function(source)
    local Player = RSGCore.Functions.GetPlayer(source)
    if Player.Functions.RemoveItem(Config.ApiaryItem, 1) then
        TriggerClientEvent('rsg-apiary:spawn', source)
    end
end)


RegisterServerEvent('rsg-apiary:registerApiary')
AddEventHandler('rsg-apiary:registerApiary', function(netId)
    local src = source
    apiaries[netId] = {
        owner = src,
        materials = false,
        timeStarted = 0,
        isReady = false,
        honeyframePlaced = 0
    }
end)


RegisterServerEvent('rsg-apiary:addMaterials')
AddEventHandler('rsg-apiary:addMaterials', function(netId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    local hasMaterials = true
    local honeyframeAmount = 0
    
    
    for _, material in ipairs(Config.Materials) do
        if Player.Functions.GetItemByName(material.item) == nil or 
           Player.Functions.GetItemByName(material.item).amount < material.amount then
            hasMaterials = false
            break
        end
        
        if material.item == 'honeyframe' then
            honeyframeAmount = material.amount
        end
    end
    
    if not hasMaterials then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            title = Config.Text.beekeeper,
            description = Config.Text.no_materials
        })
        return
    end
    
    
    for _, material in ipairs(Config.Materials) do
        Player.Functions.RemoveItem(material.item, material.amount)
    end
    
    
    apiaries[netId] = {
        owner = src,
        materials = true,
        timeStarted = os.time(),
        isReady = false,
        honeyframePlaced = honeyframeAmount
    }
    
  
    TriggerClientEvent('rsg-apiary:materialAdded', src, netId, honeyframeAmount)
    
    TriggerClientEvent('ox_lib:notify', src, {
        type = 'success',
        title = Config.Text.beekeeper,
        description = Config.Text.materials_added
    })
    
    
    Citizen.CreateThread(function()
        Citizen.Wait(Config.ProductionTime * 60 * 1000) 
        if apiaries[netId] then
            apiaries[netId].isReady = true
        end
    end)
end)


RegisterServerEvent('rsg-apiary:collectHoney')
AddEventHandler('rsg-apiary:collectHoney', function(netId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not apiaries[netId] or not apiaries[netId].isReady then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            title = Config.Text.beekeeper,
            description = Config.Text.not_ready
        })
        return
    end
    
 
    apiaries[netId].materials = false
    apiaries[netId].timeStarted = 0
    apiaries[netId].isReady = false
    apiaries[netId].honeyframePlaced = 0
    
    
    math.randomseed(os.time() + netId)
    local totalChance = 0
    for _, reward in ipairs(Config.Rewards) do
        totalChance = totalChance + reward.chance
    end
    
    local roll = math.random(1, totalChance)
    local currentChance = 0
    local selectedReward = nil
    
    for _, reward in ipairs(Config.Rewards) do
        currentChance = currentChance + reward.chance
        if roll <= currentChance then
            selectedReward = reward
            break
        end
    end
    
    
    if selectedReward then
        local amount = selectedReward.amount or math.random(selectedReward.min, selectedReward.max)
        Player.Functions.AddItem(selectedReward.item, amount)
        
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'success',
            title = Config.Text.beekeeper,
            description = Config.Text.collected
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            title = Config.Text.beekeeper,
            description = Config.Text.empty
        })
    end
end)
RegisterServerEvent('rsg-apiary:pickup')
AddEventHandler('rsg-apiary:pickup', function(netId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    
    if apiaries[netId] and apiaries[netId].owner == src then
        
        if not apiaries[netId].materials then
           
            Player.Functions.AddItem(Config.ApiaryItem, 1)
            
            
            apiaries[netId] = nil
            
           
            TriggerClientEvent('rsg-apiary:delete', -1, netId)
            
           
            TriggerClientEvent('rsg-apiary:pickupSuccess', src, netId)
        else
            
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                title = Config.Text.beekeeper,
                description = 'You cannot pick up a beehive that has materials or is producing honey'
            })
        end
    else
        
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            title = Config.Text.beekeeper,
            description = "You don't own this beehive or it doesn't exist anymore"
        })
    end
end)

RegisterServerEvent('rsg-apiary:requestSync')
AddEventHandler('rsg-apiary:requestSync', function()
    local src = source
    TriggerClientEvent('rsg-apiary:syncApiaries', src, apiaries)
end)


AddEventHandler('playerDropped', function()
    local src = source
    
    for netId, data in pairs(apiaries) do
        if data.owner == src then
            TriggerClientEvent('rsg-apiary:delete', -1, netId)
            apiaries[netId] = nil
        end
    end
end)


Citizen.CreateThread(function()
    while true do
        Citizen.Wait(300000) 
    end
end)
