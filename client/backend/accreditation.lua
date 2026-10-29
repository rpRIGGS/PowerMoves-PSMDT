local resourceName = tostring(GetCurrentResourceName())

RegisterNUICallback('getMyAccreditations', function(_, cb)
    if not MDTOpen then cb({}) return end
    cb(ps.callback(resourceName .. ':server:getMyAccreditations') or {})
end)

RegisterNUICallback('getPersonnelAccreditations', function(data, cb)
    if not MDTOpen or type(data) ~= 'table' or type(data.citizenid) ~= 'string' then
        cb({}) return
    end
    cb(ps.callback(resourceName .. ':server:getPersonnelAccreditations', data.citizenid) or {})
end)

RegisterNUICallback('issueAccreditation', function(data, cb)
    if not MDTOpen or type(data) ~= 'table' then
        cb({success = false}) return
    end
    cb(ps.callback(resourceName .. ':server:issueAccreditation', data) or {success = false})
end)

-- Read-only issuing-office audit; scope and authorization are enforced by server.
RegisterNUICallback('getIssuedAccreditations', function(data, cb)
    if not MDTOpen then cb({}) return end
    local page = type(data) == 'table' and tonumber(data.page) or 1
    cb(ps.callback(resourceName .. ':server:getIssuedAccreditations', page) or {})
end)
