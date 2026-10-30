local resourceName = tostring(GetCurrentResourceName())
local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
if not ok then QBCore = nil end
 
-- Get player source ID by citizenId
ps.registerCallback(resourceName .. ':server:GetPlayerSourceId', function(source, targetCitizenId)
    if not CheckAuth(source) then return nil end
    if type(targetCitizenId) ~= 'string' or targetCitizenId == '' then return nil end
    if targetCitizenId ~= ps.getIdentifier(source)
        and (not CheckPermission(source, 'roster_manage_officers')
            or not CanManageMdtPersonnel(source, targetCitizenId)) then return nil end
    local targetPlayer = ps.getPlayerByIdentifier(targetCitizenId)
    if not targetPlayer then
        ps.notify(source, 'Citizen seems asleep / missing', 'error')
        return nil
    end
    if not CheckAuth(source) or (targetCitizenId ~= ps.getIdentifier(source)
        and (not CheckPermission(source, 'roster_manage_officers')
            or not CanManageMdtPersonnel(source, targetCitizenId))) then return nil end
    return targetPlayer.source or (targetPlayer.PlayerData and targetPlayer.PlayerData.source)
end)
 
-- Set Callsign
ps.registerCallback(resourceName .. ':server:setCallsign', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if type(payload) ~= 'table' then return { success = false, message = 'Invalid request' } end
    local cid = payload.citizenid or payload.cid
    local newCallsign = payload.callsign or payload.newcallsign
 
    if type(cid) ~= 'string' or not cid:find('%S') or #cid > 64
        or type(newCallsign) ~= 'string' or not newCallsign:match('%S') or #newCallsign > 32 then
        return { success = false, message = 'Missing citizen ID or callsign' }
    end
    if newCallsign:find('%c') then
        return { success = false, message = 'Invalid callsign characters' }
    end
    if cid ~= ps.getIdentifier(src) and
        (not CheckPermission(src, 'roster_manage_officers') or not CanManageMdtPersonnel(src, cid)) then
        return { success = false, message = 'Personnel administration is limited to your department' }
    end
    if not QBCore then return { success = false, message = 'Core framework not available' } end

    -- Reject a callsign already owned by a different profile (UNIQUE index).
    local taken = MySQL.scalar.await(
        'SELECT 1 FROM mdt_profiles WHERE callsign = ? AND citizenid != ? LIMIT 1',
        { newCallsign, cid }
    )
    if taken then
        return { success = false, message = 'Callsign "' .. tostring(newCallsign) .. '" is already in use' }
    end
    if not CheckAuth(src) or (cid ~= ps.getIdentifier(src)
        and (not CheckPermission(src, 'roster_manage_officers')
            or not CanManageMdtPersonnel(src, cid))) then
        return { success = false, message = 'Authorization changed' }
    end

    local Player = QBCore.Functions.GetPlayerByCitizenId(cid)
    if Player then
        if not Player.PlayerData or not Player.PlayerData.source then
            return { success = false, message = 'Officer session unavailable' }
        end
        Player.Functions.SetMetaData('callsign', newCallsign)
        TriggerClientEvent(resourceName .. ':client:updateCallsign', Player.PlayerData.source, newCallsign)
 
        local saved = MySQL.update.await('UPDATE mdt_profiles SET callsign = ? WHERE citizenid = ?', { newCallsign, cid })
        if saved == nil then
            return { success = false, message = 'Failed to save callsign profile' }
        end
 
        if ps.auditLog then
            ps.auditLog(src, 'callsign_changed', 'officer', cid, { callsign = newCallsign })
        end
 
        return { success = true, message = 'Callsign updated to ' .. newCallsign }
    end
    return { success = false, message = 'Player must be online to update callsign' }
end)
 
ps.registerCallback(resourceName .. ':server:getCallsign', function(source, payload)
    if not CheckAuth(source) then return { callsign = '' } end
    local cid = type(payload) == 'table' and (payload.citizenid or payload.cid) or nil
    if type(cid) ~= 'string' or cid == '' then return { callsign = '' } end
    if cid ~= ps.getIdentifier(source)
        and (not CheckPermission(source, 'roster_manage_officers')
            or not CanManageMdtPersonnel(source, cid)) then
        return { callsign = '' }
    end
 
    if not QBCore then return { success = false, message = 'Core framework not available' } end
    local Player = QBCore.Functions.GetPlayerByCitizenId(cid)
    if Player then
        return { callsign = tostring((Player.PlayerData.metadata or {}).callsign or '') }
    end
    local row = MySQL.single.await('SELECT callsign FROM mdt_profiles WHERE citizenid = ?', { cid })
    if not CheckAuth(source) or (cid ~= ps.getIdentifier(source)
        and (not CheckPermission(source, 'roster_manage_officers')
            or not CanManageMdtPersonnel(source, cid))) then return { callsign = '' } end
    return { callsign = tostring(row and row.callsign or '') }
end)
 
-- Set Radio Frequency
ps.registerCallback(resourceName .. ':server:setRadio', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
 
    if type(payload) ~= 'table' then return { success = false, message = 'Invalid request' } end
    local cid = payload.citizenid or payload.cid
    local newRadio = payload.radio or payload.newradio
 
    if type(cid) ~= 'string' or not cid:find('%S') or #cid > 64
        or (type(newRadio) ~= 'number' and type(newRadio) ~= 'string')
        or not tonumber(newRadio) or tonumber(newRadio) <= 0
        or tonumber(newRadio) == math.huge or tonumber(newRadio) ~= tonumber(newRadio) then
        return { success = false, message = 'Missing citizen ID or radio frequency' }
    end
    -- Radio changes for another employee require actual departmental
    -- personnel authority; simply having MDT access is insufficient.
    if cid ~= ps.getIdentifier(src) and
        (not CheckPermission(src, 'roster_manage_officers')
            or not CanManageMdtPersonnel(src, cid)) then
        return { success = false, message = 'Personnel administration is limited to your department' }
    end
 
    if not QBCore then return { success = false, message = 'Core framework not available' } end
    local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(cid)
    if not targetPlayer then
        return { success = false, message = 'Officer must be online' }
    end
 
    local targetSource = targetPlayer.PlayerData.source
 
    if not targetPlayer.Functions or not targetPlayer.Functions.GetItemByName then
        return { success = false, message = 'Officer inventory unavailable' }
    end
    local radio = targetPlayer.Functions.GetItemByName('radio')
    if not radio then
        return { success = false, message = targetPlayer.PlayerData.charinfo.firstname .. ' does not have a radio!' }
    end
 
    if not CheckAuth(src) or (cid ~= ps.getIdentifier(src)
        and (not CheckPermission(src, 'roster_manage_officers')
            or not CanManageMdtPersonnel(src, cid))) then
        return { success = false, message = 'Authorization changed' }
    end
    TriggerClientEvent(resourceName .. ':client:setRadio', targetSource, tonumber(newRadio))
    return { success = true, message = 'Radio set to ' .. newRadio }
end)
 
-- Get Unit Location (GPS to officer)
ps.registerCallback(resourceName .. ':server:getUnitLocation', function(source, cid)
    if not CheckAuth(source) then return {} end
    if type(cid) ~= 'string' or cid == '' then return {} end
    if cid ~= ps.getIdentifier(source)
        and (not CheckPermission(source, 'roster_manage_officers')
            or not CanManageMdtPersonnel(source, cid)) then return {} end
 
    if not QBCore then return {} end
    local Player = QBCore.Functions.GetPlayerByCitizenId(cid)
    if Player then
        if not CheckAuth(source) or (cid ~= ps.getIdentifier(source)
            and (not CheckPermission(source, 'roster_manage_officers')
                or not CanManageMdtPersonnel(source, cid))) then return {} end
        local ped = GetPlayerPed(Player.PlayerData.source)
        if not ped or ped == 0 or not DoesEntityExist(ped) then return {} end
        local coords = GetEntityCoords(ped)
        return { x = coords.x, y = coords.y, z = coords.z }
    end
 
    return {}
end)
