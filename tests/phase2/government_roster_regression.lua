-- Run from the repository root: lua tests/phase2/government_roster_regression.lua
-- Production Lua runs in an isolated environment. SQL and framework state are
-- strict in-memory fixtures; all database writes and profile creation fail.
local players, storedRows, roleRows, fixtures, sharedJobs = {}, {}, {}, {}, {}
local callbacks, events, reads, threads = {}, {}, {}, {}
local onRoleRead, onRosterRead
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

local function contains(values, value)
    for _, entry in ipairs(values or {}) do if entry == value then return true end end
    return false
end

local function fixture(value)
    fixtureId = fixtureId + 1
    local token = 'fixture-' .. fixtureId
    fixtures[token] = copy(value)
    return token
end

local function decode(value)
    assert(fixtures[value] ~= nil, 'Invalid fixture JSON')
    return copy(fixtures[value])
end

local reference = {}
assert(loadfile('planning-reference/jobs.lua', 't', reference))()
local referenceJobs = reference.QBShared.Jobs

local function forbid()
    error('Government roster tests forbid writes, profile creation and job changes', 2)
end

local function online(source, job, grade, options)
    options = options or {}
    local definition = sharedJobs[job] or {}
    local gradeDefinition = definition.grades and definition.grades[tostring(grade)] or {}
    local data = {
        source = source, citizenid = options.citizenid or ('CID-' .. source),
        charinfo = { firstname = options.firstName or 'Live', lastname = options.lastName or ('Employee' .. source), birthdate = 'PRIVATE', phone = 'PRIVATE' },
        metadata = { callsign = 'PRIVATE', certifications = {'PRIVATE'}, medical = 'PRIVATE' },
        job = { name = job, type = options.jobType or definition.type, label = 'STALE DEPARTMENT',
            grade = { level = grade, name = 'STALE POSITION' },
            isboss = options.boss == nil and gradeDefinition.isboss == true or options.boss == true,
            onduty = options.duty ~= false, payment = 999999 },
    }
    players[source] = data
    return data
end

local function stored(citizenid, job, grade, options)
    options = options or {}
    local row = {
        citizenid = citizenid,
        job = fixture({ name = job, type = (sharedJobs[job] or {}).type, grade = options.gradeValue or { level = grade, name = 'OLD TITLE' }, label = 'OLD DEPARTMENT', payment = 999999, isboss = true }),
        charinfo = fixture({ firstname = options.firstName or 'Stored', lastname = options.lastName or citizenid, phone = 'PRIVATE', birthdate = 'PRIVATE' }),
        metadata = 'PRIVATE', money = 'PRIVATE', license = 'PRIVATE',
    }
    storedRows[#storedRows + 1] = row
    return row
end

local function getPlayer(source)
    assert(players[tonumber(source)], 'Offline framework source')
    return players[tonumber(source)]
end

local ps = {
    getJobData = function(source) return getPlayer(source).job end,
    getJobName = function(source) return getPlayer(source).job.name end,
    getJobType = function(source) return getPlayer(source).job.type end,
    getJobDuty = function(source) return getPlayer(source).job.onduty end,
    getIdentifier = function(source) return getPlayer(source).citizenid end,
    isBoss = function(source) return getPlayer(source).job.isboss == true end,
    getSharedJobData = function(job) return sharedJobs[job] end,
    getSharedJob = function(job) return sharedJobs[job] end,
    getSharedJobGrade = function(job, grade) return sharedJobs[job] and sharedJobs[job].grades[tostring(grade)] end,
    getPlayerByIdentifier = function(citizenid)
        for _, data in pairs(players) do if data.citizenid == citizenid then return { PlayerData = data } end end
    end,
    getPlayerData = function(source) return getPlayer(source) end,
    getPlayer = function(source) return { PlayerData = getPlayer(source) } end,
    getPlayerName = function(source) return getPlayer(source).charinfo.firstname .. ' ' .. getPlayer(source).charinfo.lastname end,
    getMetadata = function() return nil end,
    registerCallback = function(name, callback) callbacks[name] = callback end,
    debug = function() end, warn = function() end, notify = function() end,
    setJob = forbid,
}

local exports = setmetatable({ ps_lib = { init = function() return ps end } }, { __call = function() end })
local env = setmetatable({
    exports = exports,
    GetCurrentResourceName = function() return 'ps-mdt' end,
    GetResourceState = function() return 'missing' end,
    RegisterNetEvent = function(name, callback) events[name] = callback end,
    AddEventHandler = function(name, callback) events[name] = callback end,
    CreateThread = function(callback) threads[#threads + 1] = callback end,
    GetPlayers = function()
        local sources = {}
        for source in pairs(players) do sources[#sources + 1] = tostring(source) end
        table.sort(sources)
        return sources
    end,
    EnsureProfileExists = forbid, EnsureProfileData = forbid,
    json = { decode = decode, encode = fixture },
    MySQL = {
        single = { await = function(query, args)
            reads[#reads + 1] = { query = query, args = copy(args), type = 'role' }
            assert(query:find('FROM mdt_permission_roles', 1, true), 'Unexpected scalar query: ' .. query)
            equal(type(args[1]), 'string', 'Role job is bound')
            local result = copy(roleRows[args[1] .. ':' .. args[2]])
            if onRoleRead then local hook = onRoleRead; onRoleRead = nil; hook() end
            return result
        end },
        query = { await = function(query, args)
            reads[#reads + 1] = { query = query, args = copy(args), type = 'roster' }
            assert(query:find('FROM players', 1, true), 'Unexpected roster query: ' .. query)
            assert(query:find('WHERE', 1, true) and query:find('?', 1, true), 'Roster query must bind a department filter')
            assert(query:find('JSON_VALID', 1, true), 'Roster query must guard malformed job JSON')
            equal(#args, 1, 'Roster query has one bound job')
            expect(sharedJobs[args[1]] ~= nil, 'Bound department comes from shared jobs')
            local rows = {}
            for _, row in ipairs(storedRows) do
                local ok, job = pcall(decode, row.job)
                if (ok and type(job) == 'table' and job.name == args[1]) or row.forceReturn then rows[#rows + 1] = copy(row) end
            end
            if onRosterRead then local hook = onRosterRead; onRosterRead = nil; hook() end
            return rows
        end },
        update = { await = forbid }, insert = { await = forbid }, scalar = { await = forbid }, transaction = { await = forbid },
    },
}, { __index = _G })

assert(loadfile('config.lua', 't', env))()
assert(loadfile('server/auth.lua', 't', env))()
assert(loadfile('server/functions.lua', 't', env))()
-- Restore write traps after loading helpers that declare their own globals.
env.EnsureProfileExists, env.EnsureProfileData = forbid, forbid
assert(loadfile('server/backend/roster.lua', 't', env))()
local defaults = copy(env.Config.PermissionDefaults)
local jurisdictions = copy(env.Config.MdtAccess.GovernmentJobs)
local jurisdictionDefinitions = copy(env.Config.MdtAccess.GovernmentJurisdictions)
local listOnlinePlayers = env.GetPlayers
local function reset()
    players, storedRows, roleRows, fixtures, reads, sharedJobs = {}, {}, {}, {}, {}, copy(referenceJobs)
    env.Config.PermissionDefaults = copy(defaults)
    env.Config.MdtAccess.GovernmentJobs = copy(jurisdictions)
    env.Config.MdtAccess.GovernmentJurisdictions = copy(jurisdictionDefinitions)
    env.Config.OnlyShowOnDuty = true
    env.GetPlayers = listOnlinePlayers
    onRoleRead, onRosterRead = nil, nil
end

local function test(name, run)
    reset()
    local ok, err = pcall(run)
    if ok then passed = passed + 1; print('PASS ' .. name)
    else failed = failed + 1; print('FAIL ' .. name .. ': ' .. tostring(err)) end
end

local function grant(job, grade, permissions)
    roleRows[job .. ':' .. grade] = { permissions = fixture(permissions) }
end

local function roster(source, payload)
    assert(callbacks['ps-mdt:server:getGovernmentRoster'], 'Actual government callback was not registered')
    return callbacks['ps-mdt:server:getGovernmentRoster'](source, payload)
end

local function denied(result)
    equal(result.success, false)
    equal(#(result.roster or {}), 0, 'Denied response includes no employees')
    equal(#(result.departments or {}), 0, 'Denied response includes no departments')
end

local function byCitizen(result, citizenid)
    for _, employee in ipairs(result.roster or {}) do if employee.citizenid == citizenid then return employee end end
end

test('actual source registers government callback without executing startup work', function()
    expect(type(callbacks['ps-mdt:server:getGovernmentRoster']) == 'function')
    equal(#threads, 0)
end)

test('each government job and every boss grade stays within its own department by default', function()
    for job in pairs(jurisdictions) do
        for key, definition in pairs(sharedJobs[job].grades) do
            online(1, job, tonumber(key))
            local scope = env.GetGovernmentRosterAccess(1)
            expect(scope ~= nil, job .. ':' .. key)
            equal(scope.agency, job)
            equal(scope.hasOversight, false)
            equal(#scope.allowedJobs, 1)
            equal(scope.allowedJobs[1], job)
            expect(not env.CheckAuth(1))
            expect(not env.CheckPermission(1, 'roster_manage_officers'))
            expect(not env.CheckPermission(1, 'citizens_search'))
            equal(getPlayer(1).job.isboss, definition.isboss == true)
        end
    end
end)

test('own roster displays only government employees and runtime position labels', function()
    online(1, 'bcgov', 1)
    stored('BLAINE', 'bcgov', 12)
    stored('OTHER-COUNTY', 'lscgov', 12)
    stored('CITY', 'lsgov', 12)
    stored('STATE', 'sagov', 9)
    stored('LEO', 'lspd', 10)
    local result = roster(1)
    equal(result.success, true)
    equal(result.selectedDepartment, 'bcgov')
    equal(result.hasOversight, false)
    equal(result.canManagePersonnel, false)
    equal(#result.departments, 1)
    equal(result.departments[1].label, referenceJobs.bcgov.label)
    local employee = byCitizen(result, 'BLAINE')
    expect(employee ~= nil)
    equal(employee.rank, referenceJobs.bcgov.grades['12'].name)
    equal(employee.grade, 12)
    equal(employee.departmentLabel, referenceJobs.bcgov.label)
    equal(employee.jurisdiction, 'blaine_county')
    for _, row in ipairs(result.roster) do equal(row.department, 'bcgov') end
    for _, id in ipairs({'OTHER-COUNTY','CITY','STATE','LEO'}) do expect(byCitizen(result, id) == nil) end
end)

test('county and city bosses cannot cross peers parents or descendants even with stored oversight', function()
    for _, job in ipairs({'bcgov','lscgov','lsgov'}) do
        online(1, job, 12)
        grant(job, 12, {'government_roster_oversight','roster_manage_officers','citizens_search'})
        for target in pairs(jurisdictions) do
            if target ~= job then
                local before = #reads
                denied(roster(1, {department = target, jurisdiction = 'state', isBoss = true, permissions = {'government_roster_oversight'}}))
                for i = before + 1, #reads do expect(reads[i].type ~= 'roster', 'Foreign target rejected before roster SQL') end
            end
        end
    end
end)

test('Governor receives no automatic statewide personnel visibility from grade or boss status', function()
    online(1, 'sagov', 9)
    denied(roster(1, {department = 'bcgov'}))
    equal(env.GetGovernmentRosterAccess(1).hasOversight, false)
end)

test('exact explicit state role grant enables read-only oversight of all configured government jobs', function()
    online(1, 'sagov', 1, {boss = false})
    grant('sagov', 1, {'government_roster_oversight'})
    local scope = env.GetGovernmentRosterAccess(1)
    equal(scope.hasOversight, true)
    equal(#scope.allowedJobs, 4)
    for target in pairs(jurisdictions) do
        stored('EMPLOYEE-' .. target, target, 0)
        local result = roster(1, {department = target})
        equal(result.success, true)
        equal(result.selectedDepartment, target)
        equal(result.hasOversight, true)
        equal(result.canManagePersonnel, false)
        equal(#result.departments, 4)
        for _, employee in ipairs(result.roster) do equal(employee.department, target) end
        expect(byCitizen(result, 'EMPLOYEE-' .. target) ~= nil)
    end
    expect(not env.CheckAuth(1))
    expect(not env.CheckPermission(1, 'citizens_search'))
end)

test('configured exact role default can grant state oversight without enabling other grades', function()
    env.Config.PermissionDefaults.sagov = { ['1'] = {'government_roster_oversight'} }
    online(1, 'sagov', 1)
    equal(env.GetGovernmentRosterAccess(1).hasOversight, true)
    online(1, 'sagov', 9)
    equal(env.GetGovernmentRosterAccess(1).hasOversight, false)
end)

test('explicit empty stored grants override configured state oversight defaults', function()
    env.Config.PermissionDefaults.sagov = { ['9'] = {'government_roster_oversight'} }
    online(1, 'sagov', 9)
    grant('sagov', 9, {})
    equal(env.GetGovernmentRosterAccess(1).hasOversight, false)
end)

test('malformed stored permissions cannot manufacture oversight', function()
    online(1, 'sagov', 9)
    roleRows['sagov:9'] = {permissions = 'malformed-json'}
    equal(env.GetGovernmentRosterAccess(1).hasOversight, false)
    grant('sagov', 9, { ['government_roster_oversight'] = true })
    equal(env.GetGovernmentRosterAccess(1).hasOversight, false)
end)

test('malformed missing fractional or negative actor grades cannot inherit grade-zero oversight', function()
    local invalidGrades = {
        function(job) job.grade=nil end,
        function(job) job.grade={} end,
        function(job) job.grade='invalid' end,
        function(job) job.grade={level='invalid'} end,
        function(job) job.grade={level=0.5} end,
        function(job) job.grade={level=-1} end,
        function(job) job.grade={level=0/0} end,
        function(job) job.grade={level=math.huge} end,
        function(job) job.grade={level=-math.huge} end,
    }
    for _, applyGrade in ipairs(invalidGrades) do
        for _, useStoredGrant in ipairs({false,true}) do
            online(1,'sagov',0)
            if useStoredGrant then
                grant('sagov',0,{'government_roster_oversight'})
            else
                roleRows['sagov:0']=nil
                env.Config.PermissionDefaults.sagov={['0']={'government_roster_oversight'}}
            end
            applyGrade(getPlayer(1).job)
            local before=#reads
            equal(env.GetGovernmentRosterAccess(1),nil)
            denied(roster(1,{department='bcgov'}))
            equal(#reads,before,'Invalid actor grade rejected before a role-table lookup')
        end
    end
end)

test('valid grade zero with an explicit grant remains valid without boss authority', function()
    online(1,'sagov',0,{boss=false})
    grant('sagov',0,{'government_roster_oversight'})
    local access=env.GetGovernmentRosterAccess(1)
    expect(access~=nil)
    equal(access.grade,0)
    equal(access.hasOversight,true)
    equal(getPlayer(1).job.isboss,false)
end)

test('non-government actors cannot request a government roster through spoofed client data', function()
    for _, row in ipairs({{'sadle',11,'leo'},{'lspd',10,'leo'},{'sadoj',10,'doj'},{'safr',16,'ems'},{'ambulance',4,'ems'},{'unemployed',0,nil}}) do
        online(1,row[1],row[2],{jobType=row[3],boss=true})
        equal(env.GetGovernmentRosterAccess(1), nil)
        denied(roster(1,{department='sagov',job='sagov',grade=9,authorized=true,isBoss=true,interfaceId='sagov'}))
        equal(#reads, 0, 'Non-government caller rejected before SQL')
    end
end)

test('off-duty and unmapped government actors fail closed', function()
    online(1,'bcgov',12,{duty=false})
    denied(roster(1))
    online(1,'unmapped-government',12,{jobType='gov',boss=true})
    denied(roster(1,{department='bcgov'}))
    equal(#reads, 0)
end)

test('government roster respects the existing configured off-duty exception', function()
    online(1,'bcgov',1,{duty=false})
    env.Config.OnlyShowOnDuty=false
    equal(roster(1).success,true)
    expect(not env.CheckAuth(1),'Duty exception does not enable operational auth')
end)

test('invalid target types and SQL text cannot influence department selection', function()
    online(1,'sagov',9)
    grant('sagov',9,{'government_roster_oversight'})
    for _, value in ipairs({{},false,1,'','lspd',"bcgov' OR 1=1 --",'all'}) do denied(roster(1,{department=value})) end
    for _, read in ipairs(reads) do expect(read.type ~= 'roster') end
end)

test('non-table request payloads and disconnected sources fail without exposing rows', function()
    online(1,'bcgov',1)
    for _, payload in ipairs({'bcgov',false,9}) do denied(roster(1,payload)) end
    denied(roster(999))
    equal(#reads,0)
end)

test('permission storage and roster query failures return no personnel data', function()
    online(1,'sagov',9)
    onRoleRead=function() error('Simulated permission storage outage') end
    denied(roster(1))
    onRosterRead=function() error('Simulated roster storage outage') end
    denied(roster(1))
end)

test('failed online player enumeration does not fall back to stale employment records', function()
    online(1,'bcgov',1)
    stored('PRIVATE','bcgov',1)
    env.GetPlayers=function() error('Simulated framework enumeration failure') end
    denied(roster(1))
end)

test('live employees override stale saved jobs and recently transferred-in staff appear', function()
    online(1,'bcgov',1)
    stored('MOVED-OUT','bcgov',12)
    online(2,'lscgov',12,{citizenid='MOVED-OUT'})
    stored('MOVED-IN','lscgov',12)
    online(3,'bcgov',6,{citizenid='MOVED-IN',firstName='Current',lastName='Name'})
    local result=roster(1)
    equal(result.success,true)
    expect(byCitizen(result,'MOVED-OUT')==nil)
    local moved=byCitizen(result,'MOVED-IN')
    expect(moved~=nil)
    equal(moved.firstName,'Current')
    equal(moved.lastName,'Name')
    equal(moved.grade,6)
    equal(moved.rank,referenceJobs.bcgov.grades['6'].name)
end)

test('online and stored duplicate citizens produce one employee using live data', function()
    online(1,'lsgov',1)
    stored('DUPLICATE','lsgov',1)
    stored('DUPLICATE','lsgov',1)
    online(2,'lsgov',12,{citizenid='DUPLICATE',firstName='Live',lastName='Mayor'})
    local result=roster(1)
    local count=0
    for _, employee in ipairs(result.roster) do if employee.citizenid=='DUPLICATE' then count=count+1; equal(employee.rank,'Mayor') end end
    equal(count,1)
end)

test('response uses the minimal personnel allowlist and never includes operational metadata', function()
    online(1,'bcgov',12)
    stored('PRIVATE','bcgov',1)
    local result=roster(1)
    local allowed={citizenid=true,firstName=true,lastName=true,rank=true,grade=true,department=true,departmentLabel=true,jurisdiction=true}
    for _, employee in ipairs(result.roster) do for key in pairs(employee) do expect(allowed[key], 'Unexpected employee field: '..key) end end
    equal(result.canManagePersonnel,false)
end)

test('department grade catalog and jurisdiction ancestry use existing runtime definitions only', function()
    online(1,'lsgov',1)
    local result=roster(1)
    local department=result.departments[1]
    equal(department.job,'lsgov')
    equal(department.jurisdiction,'los_santos_city')
    equal(department.parentJurisdiction,'los_santos_county')
    equal(#department.grades,13)
    for _, grade in ipairs(department.grades) do equal(grade.name,referenceJobs.lsgov.grades[tostring(grade.grade)].name) end
    denied(roster(1,{department='lscgov'}))
end)

test('unknown runtime department configuration does not fall back to invented ranks', function()
    online(1,'bcgov',1)
    sharedJobs.bcgov=nil
    denied(roster(1))
end)

test('unknown runtime actor position cannot use stale explicit grants or view a local roster', function()
    online(1,'sagov',999,{boss=true})
    grant('sagov',999,{'government_roster_oversight'})
    local before=#reads
    denied(roster(1,{department='bcgov'}))
    for i=before+1,#reads do expect(reads[i].type~='roster','Unknown state position denied before employee SQL') end
    online(1,'bcgov',999,{boss=true})
    before=#reads
    denied(roster(1))
    for i=before+1,#reads do expect(reads[i].type~='roster','Unknown local position denied before employee SQL') end
end)

test('malformed stored job data cannot leak foreign employees or fail the whole request', function()
    online(1,'bcgov',1)
    stored('GOOD','bcgov',1)
    storedRows[#storedRows+1]={citizenid='CORRUPT',job='invalid',charinfo='invalid',forceReturn=true}
    storedRows[#storedRows+1]={citizenid='FOREIGN',job=fixture({name='lscgov',grade={level=12}}),charinfo=fixture({firstname='Private',lastname='OtherCounty'}),forceReturn=true}
    local result=roster(1)
    equal(result.success,true)
    expect(byCitizen(result,'GOOD')~=nil)
    expect(byCitizen(result,'CORRUPT')==nil)
    expect(byCitizen(result,'FOREIGN')==nil)
end)

test('missing or unknown grade is displayed safely without inventing grade zero', function()
    online(1,'bcgov',1)
    storedRows[#storedRows+1]={citizenid='NO-GRADE',job=fixture({name='bcgov'}),charinfo=fixture({firstname='No',lastname='Grade'})}
    stored('UNKNOWN-GRADE','bcgov',999)
    local result=roster(1)
    equal(result.success,true)
    local missing=byCitizen(result,'NO-GRADE')
    expect(missing~=nil)
    expect(missing.grade==nil, 'Missing grade must not become grade zero')
    local unknown=byCitizen(result,'UNKNOWN-GRADE')
    expect(unknown~=nil)
    expect(unknown.grade==nil or unknown.grade==999, 'Unknown grade must not be replaced with a real grade')
    expect(unknown.rank~='OLD TITLE','Unknown runtime rank must not trust stale serialized title')
end)

test('actor changing job during roster SQL invalidates the response', function()
    online(1,'bcgov',12)
    stored('PRIVATE','bcgov',1)
    onRosterRead=function() online(1,'lsgov',12) end
    denied(roster(1))
end)

test('actor changing grade citizen identity or duty during roster SQL invalidates the response', function()
    for _, change in ipairs({
        function() getPlayer(1).job.grade.level=0 end,
        function() getPlayer(1).citizenid='NEW-CHARACTER' end,
        function() getPlayer(1).job.onduty=false end,
    }) do
        online(1,'sagov',9)
        grant('sagov',9,{'government_roster_oversight'})
        onRosterRead=change
        denied(roster(1,{department='bcgov'}))
    end
end)

test('revoking oversight during roster SQL prevents a foreign roster response', function()
    online(1,'sagov',9)
    grant('sagov',9,{'government_roster_oversight'})
    onRosterRead=function() grant('sagov',9,{}) end
    denied(roster(1,{department='bcgov'}))
end)

test('changing actor identity during exact-role grant lookup fails closed', function()
    for _, change in ipairs({
        function() getPlayer(1).job.name='bcgov' end,
        function() getPlayer(1).job.grade.level=0 end,
        function() getPlayer(1).citizenid='NEW-CHARACTER' end,
        function() getPlayer(1).job.onduty=false end,
    }) do
        online(1,'sagov',9)
        grant('sagov',9,{'government_roster_oversight'})
        onRoleRead=change
        equal(env.GetGovernmentRosterAccess(1),nil)
    end
end)

test('valid grade zero becoming malformed during exact-role lookup loses access', function()
    for _, applyGrade in ipairs({
        function(job) job.grade=nil end,
        function(job) job.grade={} end,
        function(job) job.grade='invalid' end,
        function(job) job.grade={level='invalid'} end,
    }) do
        online(1,'sagov',0)
        grant('sagov',0,{'government_roster_oversight'})
        onRoleRead=function() applyGrade(getPlayer(1).job) end
        equal(env.GetGovernmentRosterAccess(1),nil)
    end
end)

test('government view access leaves old operational roster and employment mutations denied', function()
    online(1,'sagov',9)
    grant('sagov',9,{'government_roster_oversight','roster_manage_officers','roster_manage_certifications'})
    equal(roster(1).success,true)
    local old=callbacks['ps-mdt:server:getRosterList'](1)
    equal(#old.roster,0)
    equal(#old.activeUnits,0)
    for _, name in ipairs({'promoteOfficer','fireOfficer','updateOfficerCertifications','updateOfficerCallsign'}) do
        local result=callbacks['ps-mdt:server:'..name](1,{citizenid='CID-1',job='sagov',grade=9,callsign='TEST',certifications={}})
        equal(result.success,false,name)
    end
end)

print(('Phase 2 government roster: %d passed, %d failed, %d assertions; all SQL mocked, no writes or FiveM runtime.'):format(passed,failed,assertions))
if failed>0 then os.exit(1) end
