local RSGCore = exports['rsg-core']:GetCoreObject()


Citizen.CreateThread(function()
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS apiaries (
            id INT AUTO_INCREMENT PRIMARY KEY,
            owner VARCHAR(50) NOT NULL,
            netId INT NOT NULL,
            x FLOAT NOT NULL,
            y FLOAT NOT NULL,
            z FLOAT NOT NULL,
            materials BOOLEAN DEFAULT FALSE,
            timeStarted BIGINT DEFAULT 0,
            isReady BOOLEAN DEFAULT FALSE,
            honeyframePlaced INT DEFAULT 0
        )
    ]], {}, function(rowsChanged)
        
    end)
    
    
    MySQL.Async.fetchAll('SHOW COLUMNS FROM apiaries LIKE "owner"', {}, function(result)
        if not result or #result == 0 then
            MySQL.Async.execute('ALTER TABLE apiaries ADD COLUMN owner VARCHAR(50) NOT NULL AFTER id', {}, function(rowsChanged)
                
            end)
        end
    end)

    
    MySQL.Async.fetchAll('SELECT * FROM apiaries', {}, function(result)
        
        for _, apiary in ipairs(result) do
            if not apiary.x or not apiary.y or not apiary.z then
              
                MySQL.Async.execute('DELETE FROM apiaries WHERE id = ?', {apiary.id})
            else
                
                TriggerClientEvent('rsg-apiary:registerExistingApiary', -1, apiary.id, apiary.netId, {apiary.x, apiary.y, apiary.z})
            end
        end
        
    end)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
   
    
    MySQL.Async.fetchAll('SELECT * FROM apiaries', {}, function(result)
        if not result or #result == 0 then
           
            return
        end
        
        local syncData = {}
        for _, apiary in ipairs(result) do
            if not apiary.x or not apiary.y or not apiary.z then
              
                MySQL.Async.execute('DELETE FROM apiaries WHERE id = ?', {apiary.id})
            else
               
                syncData[apiary.id] = {
                    dbId = apiary.id,
                    netId = apiary.netId,
                    coords = {x = apiary.x, y = apiary.y, z = apiary.z},
                    materials = apiary.materials,
                    timeStarted = apiary.timeStarted,
                    isReady = apiary.isReady,
                    honeyframePlaced = apiary.honeyframePlaced
                }
                TriggerClientEvent('rsg-apiary:registerExistingApiary', -1, apiary.id, apiary.netId, {x = apiary.x, y = apiary.y, z = apiary.z})
            end
        end
        
       
        TriggerClientEvent('rsg-apiary:syncApiaries', -1, syncData)
    end)
end)

RSGCore.Functions.CreateUseableItem(Config.ApiaryItem, function(source)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then 
       
        return 
    end
    if Player.Functions.RemoveItem(Config.ApiaryItem, 1) then
        TriggerClientEvent('rsg-apiary:spawn', source)
    end
end)


RegisterServerEvent('rsg-apiary:registerApiary')
AddEventHandler('rsg-apiary:registerApiary', function(netId, coords)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then
      
        return
    end
    local owner = Player.PlayerData.citizenid or Player.PlayerData.license

    if not netId or not coords or not coords.x or not coords.y or not coords.z then
       
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            title = Config.Text.beekeeper,
            description = 'Failed to register apiary due to invalid data.'
        })
        return
    end

    MySQL.Async.insert('INSERT INTO apiaries (owner, netId, x, y, z, materials, timeStarted, isReady, honeyframePlaced) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {owner, netId, coords.x, coords.y, coords.z, false, 0, false, 0},
        function(insertId)
            if insertId then
               
                TriggerClientEvent('rsg-apiary:registerExistingApiary', -1, insertId, netId, coords)
            else
               
                TriggerClientEvent('ox_lib:notify', src, {
                    type = 'error',
                    title = Config.Text.beekeeper,
                    description = 'Failed to save apiary to database.'
                })
            end
        end
    )
end)


RegisterServerEvent('rsg-apiary:addMaterials')
AddEventHandler('rsg-apiary:addMaterials', function(dbId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then 
        
        return 
    end

    
    MySQL.Async.fetchAll('SELECT * FROM apiaries WHERE id = ?', {dbId}, function(result)
        if not result or #result == 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                title = Config.Text.beekeeper,
                description = 'Apiary does not exist.'
            })
            return
        end

        local apiary = result[1]
        if apiary.materials then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                title = Config.Text.beekeeper,
                description = 'Materials already added to this apiary.'
            })
            return
        end

        local hasMaterials = true
        local honeyframeAmount = 0
        for _, material in ipairs(Config.Materials) do
            local item = Player.Functions.GetItemByName(material.item)
            if not item or item.amount < material.amount then
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

        local currentTime = os.time() * 1000 
        MySQL.Async.execute('UPDATE apiaries SET materials = ?, timeStarted = ?, isReady = ?, honeyframePlaced = ? WHERE id = ?',
            {true, currentTime, false, honeyframeAmount, dbId},
            function(rowsChanged)
                if rowsChanged > 0 then
                   
                    TriggerClientEvent('rsg-apiary:materialAdded', src, dbId, honeyframeAmount, currentTime)
                    TriggerClientEvent('ox_lib:notify', src, {
                        type = 'success',
                        title = Config.Text.beekeeper,
                        description = Config.Text.materials_added
                    })

                    
                    Citizen.CreateThread(function()
                        Citizen.Wait(Config.ProductionTime * 60 * 1000)
                        MySQL.Async.execute('UPDATE apiaries SET isReady = ? WHERE id = ?', {true, dbId})
                       
                    end)
                else
                   
                end
            end
        )
    end)
end)


RegisterServerEvent('rsg-apiary:collectHoney')
AddEventHandler('rsg-apiary:collectHoney', function(dbId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then 
        
        return 
    end

    
    MySQL.Async.fetchAll('SELECT * FROM apiaries WHERE id = ?', {dbId}, function(result)
        if not result or #result == 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                title = Config.Text.beekeeper,
                description = 'Apiary does not exist.'
            })
            return
        end

        local apiary = result[1]
        if not apiary.isReady then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                title = Config.Text.beekeeper,
                description = Config.Text.not_ready
            })
            return
        end

       
        MySQL.Async.execute('UPDATE apiaries SET materials = ?, timeStarted = ?, isReady = ?, honeyframePlaced = ? WHERE id = ?',
            {false, 0, false, 0, dbId}, function(rowsChanged)
                if rowsChanged > 0 then
                    
                    math.randomseed(os.time() + dbId)
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
                        TriggerClientEvent('rsg-apiary:honeyCollected', src, dbId)
                    else
                        TriggerClientEvent('ox_lib:notify', src, {
                            type = 'error',
                            title = Config.Text.beekeeper,
                            description = Config.Text.empty
                        })
                    end
                else
                    
                end
            end
        )
    end)
end)


RegisterServerEvent('rsg-apiary:pickup')
AddEventHandler('rsg-apiary:pickup', function(dbId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then 
       
        return 
    end

   
    MySQL.Async.fetchAll('SELECT * FROM apiaries WHERE id = ?', {dbId}, function(result)
        if not result or #result == 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                title = Config.Text.beekeeper,
                description = "You don't own this beehive or it doesn't exist anymore"
            })
            return
        end

        local apiary = result[1]
        local owner = Player.PlayerData.citizenid or Player.PlayerData.license
        if apiary.owner ~= owner then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                title = Config.Text.beekeeper,
                description = "You don't own this beehive"
            })
            return
        end

        if apiary.materials then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                title = Config.Text.beekeeper,
                description = 'You cannot pick up a beehive that has materials or is producing honey'
            })
            return
        end

        
        MySQL.Async.execute('DELETE FROM apiaries WHERE id = ?', {dbId}, function(rowsChanged)
            if rowsChanged > 0 then
                Player.Functions.AddItem(Config.ApiaryItem, 1)
                TriggerClientEvent('rsg-apiary:delete', -1, dbId)
                TriggerClientEvent('rsg-apiary:pickupSuccess', src, dbId)
               
            else
                
            end
        end)
    end)
end)


RegisterServerEvent('rsg-apiary:getStatus')
AddEventHandler('rsg-apiary:getStatus', function(dbId)
    local src = source
    MySQL.Async.fetchAll('SELECT * FROM apiaries WHERE id = ?', {dbId}, function(result)
        if result and #result > 0 then
            local apiary = result[1]
            
            
            local currentTime = os.time() * 1000
            local elapsedTime = currentTime - apiary.timeStarted
            local remainingTime = math.max(0, (Config.ProductionTime * 60000) - elapsedTime)
            apiary.remainingTime = remainingTime
            
            TriggerClientEvent('rsg-apiary:statusResponse', src, dbId, apiary)
        else
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                title = Config.Text.beekeeper,
                description = 'Apiary data not found.'
            })
        end
    end)
end)


RegisterServerEvent('rsg-apiary:requestSync')
AddEventHandler('rsg-apiary:requestSync', function()
    local src = source
    MySQL.Async.fetchAll('SELECT * FROM apiaries', {}, function(result)
        local syncData = {}
        for _, apiary in ipairs(result) do
            if apiary.x and apiary.y and apiary.z then
                syncData[apiary.id] = {
                    dbId = apiary.id,
                    netId = apiary.netId,
                    coords = {x = apiary.x, y = apiary.y, z = apiary.z},
                    materials = apiary.materials,
                    timeStarted = apiary.timeStarted,
                    isReady = apiary.isReady,
                    honeyframePlaced = apiary.honeyframePlaced
                }
            end
        end
        TriggerClientEvent('rsg-apiary:syncApiaries', src, syncData)
    end)
end)


RegisterServerEvent('rsg-apiary:checkLocation')
AddEventHandler('rsg-apiary:checkLocation', function(coords)
    local src = source
    MySQL.Async.fetchAll('SELECT x, y, z FROM apiaries', {}, function(result)
        local isValid = true
        for _, apiary in ipairs(result) do
            local dist = #(vector3(coords.x, coords.y, coords.z) - vector3(apiary.x, apiary.y, apiary.z))
            if dist < 2.0 then
                isValid = false
                break
            end
        end
        TriggerClientEvent('rsg-apiary:locationResponse', src, isValid)
    end)
end)

-- Get player's apiary count
RegisterServerEvent('rsg-apiary:getPlayerApiaryCount')
AddEventHandler('rsg-apiary:getPlayerApiaryCount', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then 
        
        return 
    end
    local owner = Player.PlayerData.citizenid or Player.PlayerData.license
    
    MySQL.Async.fetchAll('SELECT COUNT(*) as count FROM apiaries WHERE owner = ?', {owner}, function(result)
        local count = result and result[1] and result[1].count or 0
        TriggerClientEvent('rsg-apiary:playerApiaryCount', src, count)
    end)
end)


Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000) -- Check every minute
        
       
        local currentTime = os.time() * 1000
        MySQL.Async.fetchAll('SELECT id, timeStarted FROM apiaries WHERE materials = ? AND isReady = ?', {true, false}, function(result)
            for _, apiary in ipairs(result) do
                local elapsedTime = currentTime - apiary.timeStarted
                if elapsedTime >= (Config.ProductionTime * 60 * 1000) then
                    MySQL.Async.execute('UPDATE apiaries SET isReady = ? WHERE id = ?', {true, apiary.id}, function(rowsChanged)
                        if rowsChanged > 0 then
                           
                        end
                    end)
                end
            end
        end)
    end
end)


Citizen.CreateThread(function()
    while true do
        Citizen.Wait(300000) 
        
        
        MySQL.Async.fetchAll('SELECT * FROM apiaries', {}, function(result)
            print('Database contains ' .. #result .. ' apiaries.')
        end)
    end
end)
