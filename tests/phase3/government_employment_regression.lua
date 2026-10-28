-- Run from the repository root: lua tests/phase3/government_employment_regression.lua
-- Loads real government auth/roster code with in-memory QBCore players. Only
-- mocked framework SetJob/Save may mutate state; SQL writes and cleanup fail.
local players, corePlayers, sharedJobs, fixtures, roleRows = {}, {}, {}, {}, {}
local callbacks, events, threads, reads, setCalls, saves, audits = {}, {}, {}, {}, {}, {}, {}
local modes, saveModes, onRoleRead, onSetJob = {}, {}, nil, nil
local assertions, passed, failed, fixtureId = 0, 0, 0, 0

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end
local function expect(value, message)
    assertions = assertions + 1
    assert(value, message or 'Expectation failed')
end
local function equal(actual, expected, message)
    expect(actual == expected, (message or 'Unexpected value') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function forbid() error('Employment tests forbid SQL writes, profile creation and cleanup', 2) end
local function fixture(value)
    fixtureId = fixtureId + 1
    local token = 'fixture-' .. fixtureId
    fixtures[token] = copy(value)
    return token
end
local function decode(value)
    assert(fixtures[value] ~= nil, 'Unknown or malformed JSON fixture')
    return copy(fixtures[value])
end
local reference = {}
assert(loadfile('planning-reference/jobs.lua', 't', reference))()
local referenceJobs = reference.QBShared.Jobs
local core = { Shared = { Jobs = sharedJobs }, Functions = {} }
local coreAvailable = true

local function online(source, jobName, grade, options)
    options = options or {}
    local definition = sharedJobs[jobName] or {}
    local gradeDefinition = definition.grades and definition.grades[tostring(grade)] or {}
    local boss = options.boss
    if boss == nil then boss = gradeDefinition.isboss == true end
    local data = {
        source = source, citizenid = options.citizenid or ('CID-' .. source),
        charinfo = { firstname = options.firstName or 'Test', lastname = options.lastName or ('Employee' .. source), phone = 'PRIVATE', birthdate = 'PRIVATE' },
        metadata = { callsign = 'PRIVATE', medical = 'PRIVATE' },
        job = { name = jobName, type = options.jobType or definition.type,
            label = definition.label, grade = { level = grade, name = gradeDefinition.name },
            isboss = boss == true, onduty = options.duty ~= false },
    }
    players[source] = data
    local object = { PlayerData = data, Functions = {} }
    object.Functions.SetJob = function(newJob, newGrade)
        setCalls[#setCalls + 1] = { source = source, citizenid = data.citizenid, job = newJob, grade = newGrade }
        if onSetJob then local hook = onSetJob; onSetJob = nil; hook() end
        if modes[source] == 'throw' then error('Simulated framework SetJob error') end
        if modes[source] == 'false' then return false end
        if modes[source] == 'unchanged' then return true end
        local newDefinition = sharedJobs[newJob]
        local newGradeDefinition = newDefinition and newDefinition.grades and newDefinition.grades[tostring(newGrade)]
        if not newGradeDefinition then return false end
        data.job = { name = newJob, type = newDefinition.type, label = newDefinition.label,
            grade = { level = newGrade, name = newGradeDefinition.name },
            isboss = newGradeDefinition.isboss == true, onduty = newDefinition.defaultDuty == true }
        if modes[source] == 'nilSuccess' then return nil end
        return true
    end
    object.Functions.Save = function()
        saves[#saves + 1] = { source = source, citizenid = data.citizenid, job = copy(data.job) }
        if saveModes[source] == 'throw' then error('Simulated framework Save error') end
        if saveModes[source] == 'false' then return false end
        return true
    end
    corePlayers[source] = object
    return data
end
local function player(source) return assert(players[tonumber(source)], 'Offline framework source') end
core.Functions.GetPlayer = function(source) return corePlayers[tonumber(source)] end
core.Functions.GetPlayerByCitizenId = function(citizenid)
    for _, object in pairs(corePlayers) do if object.PlayerData.citizenid == citizenid then return object end end
end
local ps = {
    getJobData = function(source) return player(source).job end,
    getJobName = function(source) return player(source).job.name end,
    getJobType = function(source) return player(source).job.type end,
    getJobDuty = function(source) return player(source).job.onduty end,
    getIdentifier = function(source) return player(source).citizenid end,
    isBoss = function(source) return player(source).job.isboss == true end,
    getSharedJobData = function(job) return sharedJobs[job] end,
    getSharedJob = function(job) return sharedJobs[job] end,
    getSharedJobGrade = function(job, grade) return sharedJobs[job] and sharedJobs[job].grades[tostring(grade)] end,
    getPlayerByIdentifier = function(citizenid) return core.Functions.GetPlayerByCitizenId(citizenid) end,
    getPlayerData = function(source) return player(source) end,
    getPlayer = function(source) return corePlayers[tonumber(source)] end,
    getPlayerName = function(source) return player(source).charinfo.firstname .. ' ' .. player(source).charinfo.lastname end,
    getMetadata = function() return nil end,
    registerCallback = function(name, callback) callbacks[name] = callback end,
    auditLog = function(source, action, entity, id, detail) audits[#audits + 1] = { source = source, action = action, entity = entity, id = id, detail = copy(detail) } end,
    debug = function() end, warn = function() end, notify = function() end, setJob = forbid,
}
local exports = setmetatable({
    ps_lib = { init = function() return ps end },
    ['qb-core'] = { GetCoreObject = function() if not coreAvailable then error('QBCore unavailable') end return core end },
}, { __call = function() end })
local env = setmetatable({
    exports = exports, GetCurrentResourceName = function() return 'ps-mdt' end,
    GetResourceState = function(resource) return resource == 'qb-core' and 'started' or 'missing' end,
    RegisterNetEvent = function(name, fn) events[name] = fn end,
    AddEventHandler = function(name, fn) events[name] = fn end,
    CreateThread = function(fn) threads[#threads + 1] = fn end,
    GetPlayers = function() local sources = {}; for source in pairs(players) do sources[#sources + 1] = tostring(source) end; return sources end,
    TriggerClientEvent = function() end,
    EnsureProfileExists = forbid, EnsureProfileData = forbid, CleanupPersonnelData = forbid,
    json = { decode = decode, encode = fixture },
    MySQL = {
        single = { await = function(query, args)
            reads[#reads + 1] = { query = query, args = copy(args) }
            assert(query:find('FROM mdt_permission_roles', 1, true), 'Unexpected SQL scalar read: ' .. query)
            local row = copy(roleRows[args[1] .. ':' .. args[2]])
            if onRoleRead then local hook = onRoleRead; onRoleRead = nil; hook() end
            return row
        end },
        query = { await = function(query, args)
            reads[#reads + 1] = { query = query, args = copy(args) }
            assert(query:find('SELECT citizenid, charinfo, job FROM players', 1, true) and query:find('JSON_VALID', 1, true), 'Unexpected SQL roster read')
            equal(#args, 1, 'Roster filters one bound department')
            return {}
        end },
        insert = { await = forbid }, update = { await = forbid }, scalar = { await = forbid }, transaction = { await = forbid },
    },
}, { __index = _G })
assert(loadfile('config.lua', 't', env))()
assert(loadfile('server/auth.lua', 't', env))()
assert(loadfile('server/functions.lua', 't', env))()
env.EnsureProfileExists, env.EnsureProfileData = forbid, forbid
assert(loadfile('server/backend/roster.lua', 't', env))()
local permissionDefaults = copy(env.Config.PermissionDefaults)
local function reset()
    players, corePlayers, fixtures, roleRows, sharedJobs = {}, {}, {}, {}, copy(referenceJobs)
    reads, setCalls, saves, audits, modes, saveModes = {}, {}, {}, {}, {}, {}
    onRoleRead, onSetJob = nil, nil
    core.Shared.Jobs = sharedJobs
    coreAvailable = true
    env.Config.PermissionDefaults = copy(permissionDefaults)
    env.Config.OnlyShowOnDuty = true
end
local function test(name, run)
    reset()
    local ok, err = pcall(run)
    if ok then passed = passed + 1; print('PASS ' .. name)
    else failed = failed + 1; print('FAIL ' .. name .. ': ' .. tostring(err)) end
end
local function invoke(name, source, payload)
    local callback = assert(callbacks['ps-mdt:server:' .. name], 'Actual callback missing: ' .. name)
    return callback(source, payload)
end
local function denied(result, message)
    expect(type(result) == 'table', message or 'Denied result must be a table')
    equal(result.success, false, message)
end
local function grant(job, grade, list) roleRows[job .. ':' .. grade] = { permissions = fixture(list) } end
local function hire(source, target, grade, department)
    return invoke('hireGovernmentEmployee', source, { citizenid = player(target).citizenid, serverId = target, grade = grade, department = department or player(source).job.name })
end
local function change(source, target, grade, department)
    return invoke('setGovernmentEmployeeGrade', source, { citizenid = player(target).citizenid, grade = grade, department = department or player(source).job.name })
end
local function terminate(source, target, department)
    return invoke('terminateGovernmentEmployee', source, { citizenid = player(target).citizenid, department = department or player(source).job.name })
end

test('actual government employment callbacks register without startup work', function()
    for _, name in ipairs({ 'getGovernmentHireCandidate', 'hireGovernmentEmployee', 'setGovernmentEmployeeGrade', 'terminateGovernmentEmployee' }) do
        expect(type(callbacks['ps-mdt:server:' .. name]) == 'function', name)
    end
    equal(#threads, 0)
    equal(#setCalls, 0)
end)

test('every government boss grade can hire change grade and terminate within its actual job', function()
    for _, job in ipairs({'sagov','bcgov','lscgov','lsgov'}) do
        for key, gradeDefinition in pairs(referenceJobs[job].grades) do
            if gradeDefinition.isboss then
                reset()
                online(1, job, tonumber(key))
                online(2, 'unemployed', 0)
                local candidate = invoke('getGovernmentHireCandidate', 1, { serverId = 2, department = job })
                equal(candidate.success, true, job .. ':' .. key .. ' candidate')
                equal(candidate.candidate.citizenid, 'CID-2')
                equal(candidate.candidate.serverId, 2)
                equal(hire(1, 2, 0).success, true, job .. ':' .. key .. ' hire')
                equal(player(2).job.name, job)
                equal(player(2).job.grade.level, 0)
                equal(change(1, 2, 1).success, true, job .. ':' .. key .. ' change')
                equal(player(2).job.grade.level, 1)
                equal(terminate(1, 2).success, true, job .. ':' .. key .. ' terminate')
                equal(player(2).job.name, 'unemployed')
                equal(player(2).job.grade.level, 0)
                equal(#setCalls, 3)
                equal(#saves, 3, 'Each standard framework change is saved')
            end
        end
    end
end)

test('all nonboss government grades fail every employment action by default', function()
    for _, job in ipairs({'sagov','bcgov','lscgov','lsgov'}) do
        for key, definition in pairs(referenceJobs[job].grades) do
            if not definition.isboss then
                reset(); online(1, job, tonumber(key)); online(2, job, 0); online(3, 'unemployed', 0)
                denied(invoke('getGovernmentHireCandidate', 1, { serverId = 3, department = job }))
                denied(hire(1, 3, 0)); denied(change(1, 2, 1)); denied(terminate(1, 2))
                equal(#setCalls, 0)
            end
        end
    end
end)

test('both live and runtime shared boss flags are required', function()
    online(1, 'bcgov', 12, { boss = false }); online(2, 'bcgov', 0)
    denied(change(1, 2, 1))
    online(1, 'bcgov', 1, { boss = true })
    denied(change(1, 2, 1))
    online(1, 'bcgov', 12)
    sharedJobs.bcgov.grades['12'].isboss = false
    denied(change(1, 2, 1))
    equal(#setCalls, 0)
end)

test('state read-only oversight does not confer management on nonboss staff', function()
    online(1, 'sagov', 1); online(2, 'bcgov', 0); online(3, 'unemployed', 0)
    grant('sagov', 1, { 'government_roster_oversight', 'roster_manage_officers' })
    equal(invoke('getGovernmentRoster', 1, { department = 'bcgov' }).success, true)
    denied(change(1, 2, 1, 'bcgov')); denied(terminate(1, 2, 'bcgov')); denied(hire(1, 3, 0, 'bcgov'))
    denied(hire(1, 3, 0, 'sagov'))
    equal(#setCalls, 0)
end)

test('bosses including Governor cannot change or terminate another government job', function()
    for _, actorJob in ipairs({'sagov','bcgov','lscgov','lsgov'}) do
        reset(); online(1, actorJob, actorJob == 'sagov' and 9 or 12)
        grant(actorJob, actorJob == 'sagov' and 9 or 12, { 'government_roster_oversight' })
        for _, targetJob in ipairs({'sagov','bcgov','lscgov','lsgov'}) do
            if targetJob ~= actorJob then
                online(2, targetJob, 0)
                denied(change(1, 2, 1)); denied(terminate(1, 2))
                denied(change(1, 2, 1, targetJob)); denied(terminate(1, 2, targetJob))
            end
        end
        equal(#setCalls, 0)
    end
end)

test('bosses cannot use a foreign department payload against their own employees', function()
    online(1, 'bcgov', 12); online(2, 'bcgov', 0); online(3, 'unemployed', 0)
    denied(change(1, 2, 1, 'lscgov')); denied(terminate(1, 2, 'lscgov')); denied(hire(1, 3, 0, 'lscgov'))
    denied(invoke('setGovernmentEmployeeGrade', 1, { citizenid='CID-2', grade=1, department='bcgov', job='lscgov' }))
    equal(#setCalls, 0)
end)

test('hiring accepts only unemployed players and protects all existing employment domains', function()
    online(1, 'sagov', 9)
    for _, tuple in ipairs({{'sagov',0},{'bcgov',0},{'lscgov',0},{'lsgov',0},{'lspd',1},{'sadle',11},{'sadoj',5},{'safr',4},{'ambulance',2},{'bus',0}}) do
        online(2, tuple[1], tuple[2])
        local candidate = invoke('getGovernmentHireCandidate', 1, { serverId = 2, department = 'sagov' })
        denied(candidate)
        expect(candidate.candidate == nil, 'Ineligible lookup reveals no candidate information')
        denied(hire(1, 2, 0))
    end
    equal(#setCalls, 0)
end)

test('non-government actors cannot use government management despite boss metadata or spoofed payloads', function()
    for _, tuple in ipairs({{'lspd',10},{'sadle',11},{'sadoj',10},{'safr',16},{'ambulance',4},{'unemployed',0},{'bus',0}}) do
        reset(); online(1, tuple[1], tuple[2], {boss=true}); online(2, 'bcgov', 0); online(3,'unemployed',0)
        denied(invoke('getGovernmentHireCandidate', 1, {serverId=3,department='bcgov',isboss=true}))
        denied(hire(1,3,0,'bcgov')); denied(change(1,2,1,'bcgov')); denied(terminate(1,2,'bcgov'))
        equal(#setCalls,0)
    end
end)

test('own valid grades including zero and boss grades are usable without inventing a rank ceiling', function()
    online(1,'sagov',2); online(2,'sagov',0)
    equal(change(1,2,9).success,true)
    equal(player(2).job.grade.level,9)
    equal(player(2).job.isboss,true)
    equal(change(1,2,0).success,true)
    equal(player(2).job.grade.level,0)
end)

test('invalid requested grades never reach framework SetJob', function()
    online(1,'bcgov',12); online(2,'bcgov',0); online(3,'unemployed',0)
    for _, value in ipairs({false,{},-1,0.5,999,'invalid',0/0,math.huge,-math.huge}) do
        denied(change(1,2,value)); denied(hire(1,3,value))
    end
    denied(invoke('setGovernmentEmployeeGrade',1,{citizenid='CID-2',department='bcgov'}))
    denied(invoke('hireGovernmentEmployee',1,{citizenid='CID-3',serverId=3,department='bcgov'}))
    equal(#setCalls,0)
end)

test('malformed and unknown actor grades cannot use boss flags to manage', function()
    local setters={function(job)job.grade=nil end,function(job)job.grade={} end,function(job)job.grade={level=0.5}end,function(job)job.grade={level=999}end,function(job)job.grade={level=0/0}end}
    for _, apply in ipairs(setters) do
        reset();online(1,'bcgov',12);online(2,'bcgov',0);apply(player(1).job)
        denied(change(1,2,1));equal(#setCalls,0)
    end
end)

test('offline targets and invalid server IDs are rejected', function()
    online(1,'bcgov',12)
    for _, value in ipairs({false,{},0,-1,2.5,'invalid',math.huge,999}) do denied(invoke('getGovernmentHireCandidate',1,{serverId=value,department='bcgov'})) end
    denied(invoke('hireGovernmentEmployee',1,{citizenid='OFFLINE',serverId=999,grade=0,department='bcgov'}))
    denied(invoke('setGovernmentEmployeeGrade',1,{citizenid='OFFLINE',grade=1,department='bcgov'}))
    denied(invoke('terminateGovernmentEmployee',1,{citizenid='OFFLINE',department='bcgov'}))
    equal(#setCalls,0)
end)

test('candidate source reuse cannot hire a different character', function()
    online(1,'bcgov',12);online(2,'unemployed',0)
    local candidate=invoke('getGovernmentHireCandidate',1,{serverId=2,department='bcgov'})
    equal(candidate.success,true)
    online(2,'unemployed',0,{citizenid='NEW-CHARACTER'})
    denied(invoke('hireGovernmentEmployee',1,{citizenid=candidate.candidate.citizenid,serverId=2,grade=0,department='bcgov'}))
    equal(#setCalls,0)
end)

test('candidate eligibility is rechecked after lookup before hiring', function()
    online(1,'bcgov',12);online(2,'unemployed',0)
    local candidate=invoke('getGovernmentHireCandidate',1,{serverId=2,department='bcgov'})
    equal(candidate.success,true)
    online(2,'lscgov',0,{citizenid=candidate.candidate.citizenid})
    denied(hire(1,2,0));equal(#setCalls,0)
end)

test('hiring requires the specified citizen and source to match', function()
    online(1,'bcgov',12);online(2,'unemployed',0);online(3,'unemployed',0)
    denied(invoke('hireGovernmentEmployee',1,{citizenid='CID-3',serverId=2,grade=0,department='bcgov'}))
    denied(invoke('hireGovernmentEmployee',1,{serverId=2,grade=0,department='bcgov'}))
    equal(#setCalls,0)
end)

test('government personnel cannot promote or terminate themselves', function()
    online(1,'bcgov',12)
    denied(change(1,1,0));denied(terminate(1,1));equal(#setCalls,0)
end)

test('off-duty managers follow existing interface duty policy', function()
    online(1,'bcgov',12,{duty=false});online(2,'bcgov',0)
    denied(change(1,2,1));equal(#setCalls,0)
    env.Config.OnlyShowOnDuty=false
    equal(change(1,2,1).success,true)
end)

test('boss revocation during authorization prevents an employment mutation', function()
    online(1,'bcgov',12);online(2,'bcgov',0)
    onRoleRead=function()player(1).job.isboss=false end
    denied(change(1,2,1));equal(#setCalls,0)
end)

test('manager identity job grade and duty changes during authorization fail closed', function()
    for _, mutate in ipairs({function()online(1,'lscgov',12)end,function()player(1).citizenid='OTHER' end,function()player(1).job.grade.level=11 end,function()player(1).job.onduty=false end}) do
        reset();online(1,'bcgov',12);online(2,'bcgov',0)
        onRoleRead=mutate
        denied(change(1,2,1));equal(#setCalls,0)
    end
end)

test('target employer changes during authorization are not overwritten', function()
    online(1,'bcgov',12);online(2,'bcgov',0)
    onRoleRead=function()online(2,'lscgov',0)end
    denied(change(1,2,1));equal(#setCalls,0)
end)

test('target disconnection during authorization prevents all job writes', function()
    online(1,'bcgov',12);online(2,'bcgov',0)
    onRoleRead=function()players[2]=nil;corePlayers[2]=nil end
    denied(terminate(1,2));equal(#setCalls,0)
end)

test('framework errors false results and unchanged state never report success', function()
    for _, mode in ipairs({'throw','false','unchanged'}) do
        reset();online(1,'bcgov',12);online(2,'bcgov',0);modes[2]=mode
        denied(change(1,2,1));equal(#saves,0)
        equal(player(2).job.grade.level,0)
    end
end)

test('framework nil return is accepted only when the new actual job and grade match', function()
    online(1,'bcgov',12);online(2,'unemployed',0);modes[2]='nilSuccess'
    equal(hire(1,2,0).success,true)
    equal(player(2).job.name,'bcgov');equal(#saves,1)
end)

test('termination uses runtime unemployed grade zero and never deletes personnel data', function()
    online(1,'lsgov',12);online(2,'lsgov',1)
    equal(invoke('terminateGovernmentEmployee',1,{citizenid='CID-2',department='lsgov',deleteData=true}).success,true)
    equal(setCalls[1].job,'unemployed');equal(setCalls[1].grade,0)
    equal(#saves,1)
end)

test('missing runtime unemployed definition blocks termination without a write', function()
    online(1,'bcgov',12);online(2,'bcgov',1);sharedJobs.unemployed=nil
    denied(terminate(1,2));equal(#setCalls,0)
end)

test('successful framework changes preserve money and metadata', function()
    online(1,'bcgov',12);online(2,'bcgov',1)
    player(2).money={cash=123,bank=456}
    local metadata=player(2).metadata
    equal(change(1,2,6).success,true)
    equal(player(2).money.cash,123);equal(player(2).money.bank,456);equal(player(2).metadata,metadata)
end)

test('malformed payloads and unavailable QBCore are denied without writes', function()
    online(1,'bcgov',12);online(2,'bcgov',0)
    for _, name in ipairs({'getGovernmentHireCandidate','hireGovernmentEmployee','setGovernmentEmployeeGrade','terminateGovernmentEmployee'}) do
        for _, payload in ipairs({false,'spoofed',7}) do denied(invoke(name,1,payload)) end
        denied(invoke(name,999,{}))
    end
    coreAvailable=false
    denied(change(1,2,1));equal(#setCalls,0)
end)

test('roster management capability is restricted to the boss own selected job', function()
    online(1,'sagov',9);grant('sagov',9,{'government_roster_oversight'})
    equal(invoke('getGovernmentRoster',1,{department='sagov'}).canManagePersonnel,true)
    equal(invoke('getGovernmentRoster',1,{department='bcgov'}).canManagePersonnel,false)
    player(1).job.isboss=false
    equal(invoke('getGovernmentRoster',1,{department='sagov'}).canManagePersonnel,false)
end)

test('candidate lookup returns only identity and name fields', function()
    online(1,'bcgov',12);online(2,'unemployed',0)
    local result=invoke('getGovernmentHireCandidate',1,{serverId=2,department='bcgov'})
    equal(result.success,true)
    local allowed={citizenid=true,serverId=true,firstName=true,lastName=true}
    for key in pairs(result.candidate) do expect(allowed[key], 'Unexpected candidate field: '..key) end
end)

test('manager revocation during final locked role lookup prevents SetJob', function()
    for _, mutate in ipairs({function()player(1).job.isboss=false end,function()online(1,'lscgov',12)end,function()player(1).job.grade.level=11 end,function()player(1).job.onduty=false end,function()player(1).citizenid='REPLACED' end}) do
        reset();online(1,'bcgov',12);online(2,'bcgov',0)
        onRoleRead=function()onRoleRead=mutate end
        denied(change(1,2,1));equal(#setCalls,0)
    end
end)

test('target employer and source reuse are rechecked after the final role yield', function()
    for _, mutate in ipairs({
        function()online(2,'lscgov',0)end,
        function()online(2,'bcgov',0,{citizenid='NEW-CHARACTER'})end,
        function()players[2]=nil;corePlayers[2]=nil;online(3,'bcgov',0,{citizenid='CID-2'})end,
        function()players[2]=nil;corePlayers[2]=nil end,
    }) do
        reset();online(1,'bcgov',12);online(2,'bcgov',0)
        onRoleRead=function()onRoleRead=mutate end
        denied(change(1,2,1));equal(#setCalls,0)
    end
end)

test('hire candidate becoming employed during final role lookup is not overwritten', function()
    online(1,'bcgov',12);online(2,'unemployed',0)
    onRoleRead=function()onRoleRead=function()online(2,'bus',0)end end
    denied(hire(1,2,0));equal(#setCalls,0);equal(player(2).job.name,'bus')
end)

test('a concurrent government action for the same employee cannot bypass the target lock', function()
    online(1,'bcgov',12);online(2,'bcgov',0);online(3,'bcgov',12)
    local nested
    onSetJob=function()nested=change(3,2,6)end
    equal(change(1,2,1).success,true)
    denied(nested);equal(#setCalls,1);equal(player(2).job.grade.level,1)
end)

test('target locks are released after both framework failures and authorization changes', function()
    online(1,'bcgov',12);online(2,'bcgov',0);modes[2]='throw'
    denied(change(1,2,1));modes[2]=nil
    equal(change(1,2,1).success,true)
    onRoleRead=function()onRoleRead=function()online(2,'lscgov',0)end end
    denied(change(1,2,6));online(2,'bcgov',1)
    equal(change(1,2,6).success,true)
end)

test('save failures report the already applied change with an explicit persistence warning', function()
    for _, mode in ipairs({'throw','false'}) do
        reset();online(1,'bcgov',12);online(2,'bcgov',0);saveModes[2]=mode
        local result=change(1,2,1)
        equal(result.success,true)
        expect(type(result.message)=='string' and result.message:find('save',1,true), 'Applied changes must expose the immediate-save warning')
        equal(player(2).job.grade.level,1);equal(#saves,1)
    end
end)

test('missing optional framework Save does not duplicate employment persistence', function()
    online(1,'bcgov',12);online(2,'bcgov',0);corePlayers[2].Functions.Save=nil
    equal(change(1,2,1).success,true);equal(#setCalls,1);equal(#saves,0)
end)

test('successful actions are audited but rejected attempts do not create success audits', function()
    online(1,'bcgov',12);online(2,'bcgov',0);online(3,'lscgov',0)
    denied(change(1,3,1));equal(#audits,0)
    equal(change(1,2,6).success,true);equal(#audits,1)
    equal(audits[1].source,1);equal(audits[1].id,'CID-2')
    equal(audits[1].detail.department,'bcgov');equal(audits[1].detail.grade,6)
end)

test('existing operational roster and employment callbacks still reject government bosses', function()
    online(1,'bcgov',12);online(2,'bcgov',0)
    local list=invoke('getRosterList',1)
    equal(#list.roster,0)
    denied(invoke('promoteOfficer',1,{citizenid='CID-2',job='bcgov',grade=1}))
    denied(invoke('fireOfficer',1,{citizenid='CID-2',deleteData=true}))
    equal(env.CheckAuth(1),false);equal(#setCalls,0)
end)

print(('Phase 3 government employment: %d passed, %d failed, %d assertions; all framework and SQL state mocked.'):format(passed,failed,assertions))
if failed>0 then os.exit(1) end
