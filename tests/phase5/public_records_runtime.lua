-- Stage 5: run real production callback code against a transaction/identity mock.
-- No database, FiveM world, or user resources are modified.
local callbacks = {}
local actor = {cid = 'OFFICER-A', job = 'lspd', duty = true, atDesk = true}
local requests = {
    [1] = {id=1, agency='lspd', status='submitted', applicant_citizenid='CIV-A'},
    [2] = {id=2, agency='bcso', status='submitted', applicant_citizenid='CIV-B'},
    [3] = {id=3, agency='lspd', status='under_review', applicant_citizenid='CIV-A'},
    [4] = {id=4, agency='lspd', status='under_review', applicant_citizenid='CIV-A'},
}
local responses, audits = {}, {}
local forceAuditFailure, forceResponseFailure = false, false
local transferDuringLockedRead = false

local function snapshot()
    local states, reply, count = {}, {}, #audits
    for id, row in pairs(requests) do states[id] = row.status end
    for id, row in pairs(responses) do reply[id] = row end
    return states, reply, count
end
local function revert(states, reply, count)
    for id, status in pairs(states) do requests[id].status = status end
    responses = reply
    while #audits > count do table.remove(audits) end
end

local function query(sql, params)
    if sql:find('FOR UPDATE', 1, true) then
        local row = requests[params[1]]
        if not row or row.agency ~= params[2] then return {} end
        if transferDuringLockedRead then
            actor.job='bcso'
            transferDuringLockedRead=false
        end
        return {{status=row.status, applicant_citizenid=row.applicant_citizenid}}
    end
    if sql:find('UPDATE mdt_public_record_requests', 1, true) then
        local approved = sql:find("status = 'approved'", 1, true) ~= nil
        local newStatus = approved and 'approved' or params[1]
        local id = approved and params[1] or params[2]
        local job = approved and params[2] or params[3]
        local previous = approved and 'under_review' or params[4]
        local row = requests[id]
        if not row or row.agency ~= job or row.status ~= previous then
            return {affectedRows=0}
        end
        row.status = newStatus
        return {affectedRows=1}
    end
    if sql:find('INSERT INTO mdt_public_record_responses', 1, true) then
        if forceResponseFailure or responses[params[1]] then return {affectedRows=0} end
        responses[params[1]] = {agency=params[2], recipient=params[3], body=params[4]}
        return {affectedRows=1, insertId=params[1]}
    end
    if sql:find('INSERT INTO mdt_public_record_request_audit', 1, true) then
        if forceAuditFailure then return {affectedRows=0} end
        audits[#audits+1] = {request_id=params[1], action=params[4] or 'approved'}
        return {affectedRows=1, insertId=#audits}
    end
    error('Unexpected transactional SQL: '..sql)
end

local env = setmetatable({
    GetCurrentResourceName = function() return 'ps-mdt' end,
    Config = {PublicServices = {RecordsOfficers = {lspd={['OFFICER-A']=true}, bcso={['OFFICER-B']=true}}}},
    CheckAuth = function() return actor.duty end,
    PublicServiceDeskAllows = function(_, job, service)
        return actor.atDesk and job == actor.job and service == 'records_office'
    end,
    ps = {
        registerCallback = function(name, fn) callbacks[name]=fn end,
        getIdentifier = function() return actor.cid end,
        getJobName = function() return actor.job end,
    },
    MySQL = {
        query = {await = function(sql, params)
            if sql:find('FROM mdt_public_record_request_audit a',1,true) then
                assert(sql:find('r.agency = ?',1,true), 'Audit must be request-employer scoped')
                local requested=requests[params[1]]
                if not requested or requested.agency~=params[2] then return {} end
                local selectedAudits={}
                for _, record in ipairs(audits) do
                    if record.request_id==params[1] then
                        selectedAudits[#selectedAudits+1]=record
                    end
                end
                return selectedAudits
            end
            assert(sql:find('WHERE agency = ?',1,true), 'Queue must be employer scoped')
            local result = {}
            for _,row in pairs(requests) do
                if row.agency == params[1] then result[#result+1] = row end
            end
            return result
        end},
        startTransaction = function(callback)
            local state, reply, count = snapshot()
            local ok, result = pcall(callback, query)
            if not ok or result == false then
                revert(state, reply, count)
                return false
            end
            return true
        end,
    }
}, {__index=_G})
assert(loadfile('server/backend/public_records_review.lua', 't', env))()
local function call(name, data)
    return assert(callbacks['ps-mdt:server:'..name], name)(1, data)
end

assert(call('getPublicRecordsOfficeQueue').success)
assert(call('reviewPublicRecordsRequest',{id=1,action='under_review',reason='Review started'}).success)
assert(requests[1].status=='under_review' and #audits==1)
assert(#call('getPublicRecordRequestAudit',1).entries==1, 'Own agency may view its audit')
assert(not call('reviewPublicRecordsRequest',{id=1,action='under_review',reason='Duplicate'}).success)
assert(#audits==1, 'Duplicate transition must not audit')

assert(call('publishPublicRecordsResponse',{id=1,response='Publicly releasable answer'}).success)
assert(requests[1].status=='approved' and responses[1].recipient=='CIV-A' and #audits==2)
assert(not call('publishPublicRecordsResponse',{id=1,response='Overwrite attempt'}).success)
assert(responses[1].body=='Publicly releasable answer' and #audits==2)

assert(not call('reviewPublicRecordsRequest',{id=2,action='under_review',reason='Cross-agency'}).success)
actor.job='bcso'; actor.cid='OFFICER-B'
assert(call('getPublicRecordsOfficeQueue').success)
assert(#call('getPublicRecordRequestAudit',1).entries==0, 'Cross-agency audit must be hidden')
assert(not call('reviewPublicRecordsRequest',{id=1,action='denied',reason='Cross-agency'}).success)
actor.job='lspd'; actor.cid='OFFICER-A'
actor.duty=false
assert(not call('getPublicRecordsOfficeQueue').success)
actor.duty=true;actor.atDesk=false
assert(not call('publishPublicRecordsResponse',{id=3,response='Offsite'}).success)
actor.atDesk=true

transferDuringLockedRead=true
assert(not call('publishPublicRecordsResponse',{id=4,response='Must fail after transfer'}).success)
assert(requests[4].status=='under_review' and responses[4]==nil,
    'Employer transfer during row lock must not release anything')
actor.job='lspd'
forceAuditFailure=true
assert(not call('reviewPublicRecordsRequest',{id=3,action='denied',reason='Deny'}).success)
assert(requests[3].status=='under_review' and #audits==2, 'Audit failure must roll back status')
assert(not call('publishPublicRecordsResponse',{id=3,response='Public response'}).success)
assert(requests[3].status=='under_review' and responses[3]==nil, 'Audit failure must roll back release')
forceAuditFailure=false
forceResponseFailure=true
assert(not call('publishPublicRecordsResponse',{id=3,response='Public response'}).success)
assert(requests[3].status=='under_review' and responses[3]==nil)
forceResponseFailure=false
assert(call('reviewPublicRecordsRequest',{id=3,action='denied',reason='Not eligible'}).success)
assert(requests[3].status=='denied' and responses[3] ~= nil and #audits==3)
assert(responses[3].recipient=='CIV-A' and responses[3].body=='Not eligible',
    'Denial explanation must be recipient-bound')

-- An oxmysql installation without the checked transaction API must not
-- mutate any records or silently fall back to an unchecked batch.
local originalTx = env.MySQL.startTransaction
env.MySQL.startTransaction = nil
local beforeAudits = #audits
local beforeStatus = requests[4].status
assert(not call('reviewPublicRecordsRequest',{id=4,action='denied',reason='Outdated database driver'}).success)
assert(not call('publishPublicRecordsResponse',{id=4,response='No uncontrolled release'}).success)
assert(requests[4].status == beforeStatus and responses[4] == nil and #audits == beforeAudits,
    'Missing oxmysql transaction API must fail closed without writes')
-- Simulate pre-v2.12 oxmysql: arbitrary missing keys resolve to functions
-- through the MySQL metatable, but they are not safe transaction methods.
setmetatable(env.MySQL, {
    __index=function(_, key)
        return function() error('Unexpected legacy oxmysql fallback: '..tostring(key)) end
    end
})
assert(not call('reviewPublicRecordsRequest',{id=4,action='denied',reason='Legacy metatable'}).success)
assert(not call('publishPublicRecordsResponse',{id=4,response='Legacy metatable'}).success)
assert(requests[4].status == beforeStatus and responses[4] == nil and #audits == beforeAudits)
setmetatable(env.MySQL, nil)
env.MySQL.startTransaction = originalTx

print('PASS Stage 5 agency isolation, counter/duty, rollback and oxmysql compatibility denial')
