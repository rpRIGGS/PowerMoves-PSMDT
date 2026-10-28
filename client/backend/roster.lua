RegisterNUICallback('getRoster', function(data, cb)
    if not MDTOpen then cb({}) return end
    local rosterList = ps.callback('ps-mdt:server:getRosterList')
    cb(rosterList)
end)

-- Government uses a separate read-only projection; operational roster and
-- personnel mutation callbacks keep their existing authorization guards.
RegisterNUICallback('getGovernmentRoster', function(data, cb)
    local denied = { success = false, error = 'Government roster unavailable', roster = {}, departments = {} }
    if not MDTOpen then cb(denied) return end
    local result = ps.callback(tostring(GetCurrentResourceName()) .. ':server:getGovernmentRoster', {
        department = type(data) == 'table' and data.department or nil,
    })
    cb(result or denied)
end)

RegisterNUICallback('getOfficerTags', function(data, cb)
    if not MDTOpen then cb({}) return end
    local tags = ps.callback('ps-mdt:server:getOfficerTags')
    cb(tags or {})
end)

RegisterNUICallback('updateOfficerCertifications', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    local result = ps.callback('ps-mdt:server:updateOfficerCertifications', data)
    cb(result or { success = false })
end)

RegisterNUICallback('getJobGrades', function(data, cb)
    if not MDTOpen then cb({}) return end
    local result = ps.callback('ps-mdt:server:getJobGrades', data)
    cb(result or {})
end)

RegisterNUICallback('promoteOfficer', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    local result = ps.callback('ps-mdt:server:promoteOfficer', data)
    cb(result or { success = false })
end)

RegisterNUICallback('fireOfficer', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    local result = ps.callback('ps-mdt:server:fireOfficer', data)
    cb(result or { success = false })
end)

RegisterNUICallback('updateOfficerCallsign', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    local result = ps.callback('ps-mdt:server:updateOfficerCallsign', data)
    cb(result or { success = false })
end)
