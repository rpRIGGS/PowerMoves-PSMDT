-- Stage 5: the physical qb-target counter opens the existing PSMDT NUI.
-- All records-office reads/writes are server-authorized. No slash commands or
-- separate ox_lib staff menus are used.
local resourceName = tostring(GetCurrentResourceName())
local officeOpenRequest = 0
local officeNuiAcknowledged = false

RegisterNUICallback('recordsOfficeReady', function(_, cb)
    if not MDTOpen then cb({success = false}) return end
    officeNuiAcknowledged = true
    cb({success = true})
end)

RegisterNUICallback('canUsePublicRecordsOffice', function(_, cb)
    if not MDTOpen then cb({success = false}) return end
    local result = ps.callback(resourceName .. ':server:canUsePublicRecordsOffice')
    cb(result or {success = false})
end)

RegisterNUICallback('getPublicRecordsOfficeQueue', function(data, cb)
    if not MDTOpen then cb({success = false, error = 'MDT is closed'}) return end
    local result = ps.callback(resourceName .. ':server:getPublicRecordsOfficeQueue', data or {})
    cb(result or {success = false, error = 'Records office unavailable'})
end)

RegisterNUICallback('getPublicRecordRequestAudit', function(data, cb)
    if not MDTOpen then cb({success = false, error = 'MDT is closed'}) return end
    local result = ps.callback(resourceName .. ':server:getPublicRecordRequestAudit',
        data and data.id)
    cb(result or {success = false, error = 'Decision history unavailable'})
end)

RegisterNUICallback('reviewPublicRecordsRequest', function(data, cb)
    if not MDTOpen then cb({success = false, error = 'MDT is closed'}) return end
    local result = ps.callback(resourceName .. ':server:reviewPublicRecordsRequest', data or {})
    cb(result or {success = false, error = 'Review unavailable'})
end)

RegisterNUICallback('publishPublicRecordsResponse', function(data, cb)
    if not MDTOpen then cb({success = false, error = 'MDT is closed'}) return end
    local result = ps.callback(resourceName .. ':server:publishPublicRecordsResponse', data or {})
    cb(result or {success = false, error = 'Publication unavailable'})
end)

RegisterNetEvent('ps-mdt:client:openRecordsOffice', function()
    -- Refuse before opening the tablet; the same entitlement is rechecked for
    -- every NUI callback and every server-side request.
    local result = ps.callback(resourceName .. ':server:getPublicRecordsOfficeQueue')
    if not result or not result.success then
        ps.notify((result and result.error) or 'Records office access denied', 'error')
        return
    end
    if not MDTOpen then OpenMDT() end
    if not MDTOpen then return end

    -- MDTOpen is not proof that the NUI listener has mounted. Retry until
    -- the Svelte MDT acknowledges this opening; never fall back to a command.
    officeOpenRequest = officeOpenRequest + 1
    local requestId = officeOpenRequest
    officeNuiAcknowledged = false
    CreateThread(function()
        for _ = 1, 25 do
            if requestId ~= officeOpenRequest or not MDTOpen then return end
            if officeNuiAcknowledged then return end
            SendNUI('openRecordsOffice', {})
            Wait(200)
        end
        if requestId == officeOpenRequest and MDTOpen and not officeNuiAcknowledged then
            ps.notify('Records Office interface did not acknowledge opening', 'error')
        end
    end)
end)
