-- Stage 5 records desk: server-authorized review via existing ox_lib UI.
local resourceName = tostring(GetCurrentResourceName())

local function notice(message, kind)
    lib.notify({title = 'Records Office', description = message, type = kind or 'inform'})
end

local function chooseDecision(item)
    local options = {
        {label = 'Mark Under Review', value = 'under_review'},
        {label = 'Deny Request', value = 'denied'},
        {label = 'Approve and publish public response', value = 'approved'},
    }
    local choice = lib.inputDialog('Request ' .. tostring(item.request_number or item.id), {
        {type = 'select', label = 'Decision', options = options, required = true},
        {type = 'textarea', label = 'Reason', required = true},
    })
    if not choice then return end
    local response
    if choice[1] == 'approved' then
        response = ps.callback(resourceName .. ':server:publishPublicRecordsResponse', {
            id = item.id, response = choice[2]
        })
    else
        response = ps.callback(resourceName .. ':server:reviewPublicRecordsRequest', {
            id = item.id, action = choice[1], reason = choice[2]
        })
    end
    notice(response and response.success and 'Decision recorded' or
        (response and response.error or 'Decision failed'),
        response and response.success and 'success' or 'error')
end

RegisterCommand('recordsdesk', function()
    local result = ps.callback(resourceName .. ':server:getPublicRecordsOfficeQueue')
    if not result or not result.success then
        notice(result and result.error or 'Access denied', 'error')
        return
    end
    local options = {}
    for _, item in ipairs(result.requests or {}) do
        options[#options + 1] = {
            title = tostring(item.request_number or item.id) .. ' — ' .. tostring(item.subject or ''),
            description = 'Status: ' .. tostring(item.status or ''),
            disabled = item.status ~= 'submitted' and item.status ~= 'under_review',
            onSelect = function() chooseDecision(item) end,
        }
    end
    if #options == 0 then
        notice('No requests currently in this agency queue')
        return
    end
    lib.registerContext({id = 'psmdt_records_office', title = 'Agency Records Office', options = options})
    lib.showContext('psmdt_records_office')
end, false)
