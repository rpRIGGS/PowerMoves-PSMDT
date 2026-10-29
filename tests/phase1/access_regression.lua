-- Run from the repository root with an existing Lua 5.4 interpreter:
-- lua tests/phase1/access_regression.lua
-- Loads production configuration/helpers into an isolated Lua environment.
-- FiveM/framework calls are stubs; SQL only reaches strict in-memory mocks.
-- Background startup threads are captured, never run (no schema changes).

local players, offlineJobs, roleRows, decodedFixtures = {}, {}, {}, {}
local callbacks, events, exported, databaseReads = {}, {}, {}, {}
local scheduledThreads, databaseWrites = {}, {}
local sharedJobs, encodedFixtureCount = {}, 0
local onDojRead, onDojWrite
local onRoleRead
local passed, failed, assertions = 0, 0, 0

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
    expect(actual == expected, (message or 'Unexpected value')
        .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end

local function includes(values, value)
    for _, entry in ipairs(values or {}) do
        if entry == value then return true end
    end
    return false
end

local function identity(source, job, jobType, grade, boss, duty)
    local player = {
        source = source,
        citizenid = 'TEST-' .. source,
        job = {
            name = job, type = jobType, grade = { level = grade },
            isboss = boss == true, onduty = duty ~= false,
        },
    }
    players[source] = player
    return player
end

local function player(source)
    assert(players[source], 'Offline/invalid framework source')
    return players[source]
end

local ps = {
    getJobData = function(source) return player(source).job end,
    getJobName = function(source) return player(source).job.name end,
    getJobType = function(source) return player(source).job.type end,
    getJobDuty = function(source) return player(source).job.onduty end,
    getIdentifier = function(source) return player(source).citizenid end,
    getMetadata = function() return nil end,
    getPlayerName = function(source) return 'Test Player ' .. source end,
    getSharedJobData = function(job) return sharedJobs[job] end,
    isBoss = function(source) return player(source).job.isboss == true end,
    getPlayerByIdentifier = function(citizenid)
        for _, value in pairs(players) do
            if value.citizenid == citizenid then return { PlayerData = value } end
        end
    end,
    registerCallback = function(name, callback) callbacks[name] = callback end,
    debug = function() end,
    warn = function() end,
}

local exports = setmetatable({ ps_lib = { init = function() return ps end } }, {
    __call = function(_, name, callback) exported[name] = callback end,
})

local function forbiddenWrite()
    error('Regression harness forbids database writes', 2)
end

local env = setmetatable({
    exports = exports,
    GetCurrentResourceName = function() return 'ps-mdt' end,
    RegisterNetEvent = function(name, callback) events[name] = callback end,
    AddEventHandler = function(name, callback) events[name] = callback end,
    CreateThread = function(callback) scheduledThreads[#scheduledThreads + 1] = callback end,
    json = {
        -- Only fixture tokens are decoded; no application JSON parser is replaced.
        decode = function(token)
            assert(decodedFixtures[token], 'Unknown JSON fixture')
            return copy(decodedFixtures[token])
        end,
        encode = function(value)
            encodedFixtureCount = encodedFixtureCount + 1
            local token = 'encoded-fixture-' .. encodedFixtureCount
            decodedFixtures[token] = copy(value)
            return token
        end,
    },
    MySQL = {
        single = { await = function(query, args)
            databaseReads[#databaseReads + 1] = query
            if query:find('FROM mdt_permission_roles', 1, true) then
                local row = roleRows[args[1] .. ':' .. args[2]]
                if onRoleRead then
                    local hook = onRoleRead
                    onRoleRead = nil
                    hook()
                end
                return row
            end
            if query:find('SELECT job FROM players', 1, true) then
                local job = offlineJobs[args[1]]
                return job and { job = copy(job) } or nil
            end
            error('Unanticipated database read: ' .. query)
        end },
        update = { await = forbiddenWrite },
        insert = { await = forbiddenWrite },
        query = { await = forbiddenWrite },
        scalar = { await = forbiddenWrite },
        transaction = { await = forbiddenWrite },
    },
}, { __index = _G })

for _, path in ipairs({ 'config.lua', 'server/auth.lua', 'server/functions.lua' }) do
    assert(loadfile(path, 't', env))()
end

local function test(name, callback)
    onRoleRead = nil
    onDojRead, onDojWrite = nil, nil
    local ok, err = pcall(callback)
    if ok then
        passed = passed + 1
        print('PASS ' .. name)
    else
        failed = failed + 1
        print('FAIL ' .. name .. ': ' .. tostring(err))
    end
end

test('actual configured LEO jobs retain SADLE eligibility', function()
    for index, job in ipairs(env.Config.PoliceJobs) do
        local source = 100 + index
        identity(source, job, 'leo', 1, false)
        local access = env.GetMdtAccess(source)
        equal(access.primaryInterfaceId, 'sadle', job)
        equal(access.interfaceId, 'sadle', job)
        equal(access.agency, job)
        equal(access.jobType, 'leo')
        expect(env.CheckAuth(source))
        expect(env.CheckMdtInterfaceAccess(source, 'sadle'))
        expect(not env.CheckMdtInterfaceAccess(source, 'sadoj'))
    end
end)

test('fire and hospital jobs select distinct interfaces despite shared ems type', function()
    for index, job in ipairs(env.Config.MedicalJobs) do
        local source = 200 + index
        identity(source, job, 'ems', 1, false)
        local expected = includes(env.Config.MdtAccess.FireJobs, job) and 'safr' or 'sams'
        local access = env.GetMdtAccess(source)
        equal(access.primaryInterfaceId, expected, job)
        expect(env.CheckAuth(source))
        expect(env.CheckMdtInterfaceAccess(source, expected))
        expect(not env.CheckMdtInterfaceAccess(source, 'sadle'))
    end
end)

test('all four government jobs have jurisdictional shell access without operations', function()
    local jurisdictions = {
        sagov = 'state', bcgov = 'blaine_county',
        lscgov = 'los_santos_county', lsgov = 'los_santos_city',
    }
    local source = 300
    for job, jurisdiction in pairs(jurisdictions) do
        source = source + 1
        identity(source, job, 'gov', 9, true)
        local access = env.GetMdtAccess(source)
        equal(access.primaryInterfaceId, 'sagov', job)
        equal(access.jurisdiction, jurisdiction, job)
        equal(access.jobType, 'gov')
        equal(#access.permissions, 0)
        expect(env.CheckMdtInterfaceAccess(source, 'sagov'))
        expect(not env.CheckAuth(source), 'Government must fail legacy operational CheckAuth')
        expect(not env.CheckPermission(source, 'management_permissions'))
        expect(not env.CheckPermission(source, 'reports_view'))
        expect(not env.HasMdtJudicialAuthority(source))
        expect(not env.CheckMdtInterfaceAccess(source, 'sadle'))
        expect(not env.CheckMdtInterfaceAccess(source, 'sadoj'))
    end
end)

test('government stored grants cannot create operational capabilities', function()
    identity(310, 'sagov', 'gov', 6, false)
    decodedFixtures.gov_grants = { 'reports_view', 'management_permissions', 'judicial_authority' }
    roleRows['sagov:6'] = { permissions = 'gov_grants' }
    local readsBefore = #databaseReads
    equal(#env.GetMdtAccess(310).permissions, 0)
    equal(#databaseReads, readsBefore, 'GOV should not load operational grants')
    expect(not env.CheckPermission(310, 'judicial_authority'))
end)

test('unmapped government jobs never fall through to police access', function()
    identity(311, 'future_government', 'gov', 20, true)
    local access = env.GetMdtAccess(311)
    expect(not access.eligible)
    equal(access.primaryInterfaceId, nil)
    equal(#access.allowedInterfaces, 0)
    expect(not env.CheckAuth(311))
    expect(not env.CheckMdtInterfaceAccess(311, 'sadle'))
    expect(not env.CheckPermission(311, 'reports_view'))
end)

test('boss status does not grant civilians or businesses staff access', function()
    identity(312, 'mechanic', 'mechanic', 4, true)
    local access = env.GetMdtAccess(312)
    expect(not access.eligible)
    expect(access.isCivilian)
    equal(#access.permissions, 0)
    expect(not env.CheckAuth(312))
end)

test('exact AG role has SADLE primary plus scoped SADOJ entry', function()
    local current = identity(400, 'sadle', 'leo', 11, true)
    local access = env.GetMdtAccess(400)
    expect(env.IsMdtAttorneyGeneral(400))
    equal(access.role, 'attorney_general')
    equal(access.primaryInterfaceId, 'sadle')
    equal(access.interfaceId, 'sadle')
    equal(#access.allowedInterfaces, 2)
    expect(env.CheckMdtInterfaceAccess(400, 'sadoj'))
    local result = callbacks['ps-mdt:server:setInterface'](400, { interfaceId = 'sadoj' })
    expect(result.success)
    equal(result.interfaceId, 'sadoj')
    equal(result.jobType, 'doj')
    equal(result.agency, 'sadle')
    equal(current.job.name, 'sadle', 'Switching must not change QBCore job')
    equal(current.job.grade.level, 11)
    expect(not env.HasMdtJudicialAuthority(400))
end)

test('AG boss cannot gain judicial or court mutation capabilities', function()
    identity(401, 'sadle', 'leo', 11, true)
    for _, permission in ipairs({
        'judicial_authority', 'warrants_approve', 'court_create', 'court_edit', 'court_delete',
        'warrants_issue', 'warrants_close',
    }) do
        expect(not env.CheckPermission(401, permission), permission)
    end
    expect(env.CheckPermission(401, 'court_view'))
    expect(env.CheckPermission(401, 'reports_view'), 'Keep ordinary LEO features')
end)

test('stored malicious grants do not override exact AG restrictions', function()
    identity(402, 'sadle', 'leo', 11, false)
    decodedFixtures.ag_grants = {
        'judicial_authority', 'warrants_approve', 'court_create', 'court_edit',
        'court_delete', 'court_view', 'reports_view', 'warrants_issue', 'warrants_close',
    }
    roleRows['sadle:11'] = { permissions = 'ag_grants' }
    for _, permission in ipairs({
        'judicial_authority', 'warrants_approve', 'court_create', 'court_edit', 'court_delete',
        'warrants_issue', 'warrants_close',
    }) do
        expect(not env.CheckPermission(402, permission), permission)
    end
    expect(env.CheckPermission(402, 'court_view'))
    expect(env.CheckPermission(402, 'reports_view'))
end)

test('nearby grades and same grade at other agencies cannot impersonate AG', function()
    for index, spec in ipairs({
        { 'sadle', 'leo', 10 }, { 'sadle', 'leo', 12 }, { 'lspd', 'leo', 11 },
        { 'sadoj', 'doj', 11 }, { 'sagov', 'gov', 11 },
    }) do
        local source = 410 + index
        identity(source, spec[1], spec[2], spec[3], true)
        expect(not env.IsMdtAttorneyGeneral(source))
        expect(not includes(env.GetMdtAccess(source).allowedInterfaces, 'sadoj')
            or spec[1] == 'sadoj', 'No AG secondary entitlement')
    end
end)

test('exact real judicial grades have authority even nonboss District Judge', function()
    for _, grade in ipairs({ 8, 9, 10 }) do
        local source = 430 + grade
        identity(source, 'sadoj', 'doj', grade, false)
        expect(env.HasMdtJudicialAuthority(source), 'Judicial grade ' .. grade)
        expect(env.CheckPermission(source, 'judicial_authority'))
        expect(env.CheckPermission(source, 'warrants_approve'))
        equal(env.GetMdtAccess(source).role, 'judiciary')
    end
end)

test('clerks prosecutors and defenders cannot acquire judicial authority via boss or saved grants', function()
    decodedFixtures.false_judiciary = { 'judicial_authority', 'warrants_approve', 'court_view' }
    for _, grade in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 11 }) do
        local source = 450 + grade
        identity(source, 'sadoj', 'doj', grade, grade == 4 or grade == 6 or grade == 7)
        roleRows['sadoj:' .. grade] = { permissions = 'false_judiciary' }
        expect(not env.HasMdtJudicialAuthority(source), 'Nonjudicial grade ' .. grade)
        expect(not env.CheckPermission(source, 'judicial_authority'))
        expect(not env.CheckPermission(source, 'warrants_approve'))
    end
end)

test('legacy judge and lawyer jobs cannot bypass SADOJ judicial grade policy', function()
    for _, grade in ipairs({ 0, 1, 2 }) do
        local src = 470 + grade
        identity(src, 'judge', 'doj', grade, grade == 2)
        expect(not env.HasMdtJudicialAuthority(src), 'Legacy judge grade ' .. grade)
        expect(not env.CheckPermission(src, 'warrants_approve'))
    end
    identity(473, 'lawyer', 'doj', 2, true)
    expect(not env.HasMdtJudicialAuthority(473))
    expect(not env.CheckPermission(473, 'warrants_approve'))
end)

test('EMS boss and stored grants stay within the medical permission ceiling', function()
    identity(480, 'safr', 'ems', 16, true)
    expect(env.CheckPermission(480, 'reports_view'))
    expect(not env.CheckPermission(480, 'warrants_issue'))
    expect(not env.CheckPermission(480, 'court_edit'))
    identity(481, 'pillboxmed', 'ems', 8, false)
    decodedFixtures.ems_grants = { 'reports_view', 'warrants_issue', 'court_edit' }
    roleRows['pillboxmed:8'] = { permissions = 'ems_grants' }
    expect(env.CheckPermission(481, 'reports_view'))
    expect(not env.CheckPermission(481, 'warrants_issue'))
    expect(not env.CheckPermission(481, 'court_edit'))
end)

test('unauthorized switch is denied without changing selected interface', function()
    identity(500, 'lspd', 'leo', 2, false)
    for _, interfaceId in ipairs({ 'sadoj', 'sagov', 'sams', 'safr', 'unknown' }) do
        local result = callbacks['ps-mdt:server:setInterface'](500, { interfaceId = interfaceId })
        expect(not result.success, interfaceId)
        equal(env.GetMdtAccess(500).interfaceId, 'sadle')
    end
    local malformed = callbacks['ps-mdt:server:setInterface'](500, { interfaceId = {} })
    expect(not malformed.success)
end)

test('off-duty interface selection respects live authorization', function()
    identity(501, 'sadle', 'leo', 11, true, false)
    local access = env.GetMdtAccess(501)
    expect(access.eligible)
    expect(not access.authorized)
    expect(not env.CheckMdtInterfaceAccess(501, 'sadoj'))
    expect(not callbacks['ps-mdt:server:setInterface'](501, 'sadoj').success)
end)

test('job or grade change revokes AG secondary selection', function()
    local current = identity(502, 'sadle', 'leo', 11, true)
    expect(callbacks['ps-mdt:server:setInterface'](502, 'sadoj').success)
    current.job.grade.level = 10
    local access = env.GetMdtAccess(502)
    equal(access.interfaceId, 'sadle')
    equal(#access.allowedInterfaces, 1)
    expect(not env.IsMdtAttorneyGeneral(502))
    current.job.name, current.job.type = 'pillboxmed', 'ems'
    equal(env.GetMdtAccess(502).interfaceId, 'sams')
end)

test('identity change during permission read cannot authorize a stale switch', function()
    local current = identity(503, 'sadle', 'leo', 11, false)
    onRoleRead = function()
        current.job.name, current.job.type, current.job.grade.level = 'lspd', 'leo', 2
    end
    local result = callbacks['ps-mdt:server:setInterface'](503, 'sadoj')
    expect(not result.success)
    equal(env.GetMdtAccess(503).interfaceId, 'sadle')
    expect(not env.CheckMdtInterfaceAccess(503, 'sadoj'))
end)

test('invalid or disconnected sources fail closed', function()
    for _, source in ipairs({ 0, -1, 'invalid', 999999 }) do
        expect(not env.CheckAuth(source))
        expect(not env.GetMdtAccess(source).eligible)
        expect(not env.CheckPermission(source, 'reports_view'))
        expect(not env.HasMdtJudicialAuthority(source))
    end
    expect(not env.CheckAuth(nil))
end)

test('personnel guard checks current employer and requested destination', function()
    identity(600, 'lspd', 'leo', 10, true)
    local same = identity(601, 'lspd', 'leo', 2, false)
    local other = identity(602, 'bcso', 'leo', 3, false)
    local government = identity(603, 'sagov', 'gov', 9, true)
    expect(env.CanManageMdtPersonnel(600, same.citizenid, 'lspd'), 'Same-employer role edit denied')
    expect(env.CanManageMdtPersonnel(600, same.citizenid), 'Same-employer role edit without destination denied')
    expect(not env.CanManageMdtPersonnel(600, same.citizenid, 'bcso'))
    expect(not env.CanManageMdtPersonnel(600, other.citizenid, 'lspd'))
    expect(not env.CanManageMdtPersonnel(600, government.citizenid, 'lspd'))
    expect(not env.CanManageMdtPersonnel(603, government.citizenid, 'sagov'))
    expect(not env.CanManageMdtPersonnel(600, 'MISSING'))
    expect(not env.CanManageMdtPersonnel(600, nil))
end)

test('AG prosecution supervision does not confer cross-employer employment edits', function()
    identity(610, 'sadle', 'leo', 11, true)
    local sadle = identity(611, 'sadle', 'leo', 4, false)
    expect(env.CanManageMdtPersonnel(610, sadle.citizenid, 'sadle'))
    for _, grade in ipairs({ 3, 4, 5, 6, 8, 9, 10 }) do
        local target = identity(620 + grade, 'sadoj', 'doj', grade, false)
        expect(not env.CanManageMdtPersonnel(610, target.citizenid, 'sadoj'))
        expect(not env.CanManageMdtPersonnel(610, target.citizenid, 'sadle'))
    end
end)

test('offline personnel targets use stored employer and fail closed on corrupt data', function()
    identity(650, 'bcso', 'leo', 16, true)
    offlineJobs.same_department = { name = 'bcso', grade = { level = 2 } }
    offlineJobs.other_department = { name = 'lspd', grade = { level = 2 } }
    decodedFixtures.offline_same = { name = 'bcso', grade = { level = 3 } }
    offlineJobs.encoded_same = 'offline_same'
    offlineJobs.corrupt = 'invalid-json-fixture'
    expect(env.CanManageMdtPersonnel(650, 'same_department', 'bcso'))
    expect(env.CanManageMdtPersonnel(650, 'encoded_same', 'bcso'))
    expect(not env.CanManageMdtPersonnel(650, 'other_department', 'bcso'))
    expect(not env.CanManageMdtPersonnel(650, 'corrupt', 'bcso'))
    expect(not env.CanManageMdtPersonnel(650, 'unknown_offline', 'bcso'))
end)

-- Exercise the production DOJ callbacks, with explicit SQL expectations per test.
-- Only these wrapper functions stand in for MySQL; no database driver is loaded.
local originalSingle = env.MySQL.single.await
env.MySQL.single.await = function(query, args)
    if onDojRead and not query:find('FROM mdt_permission_roles', 1, true) then
        databaseReads[#databaseReads + 1] = query
        return onDojRead('single', query, args)
    end
    return originalSingle(query, args)
end

local function mockWrite(operation, query, args)
    if not onDojWrite then return forbiddenWrite() end
    local result = onDojWrite(operation, query, args)
    databaseWrites[#databaseWrites + 1] = { operation = operation, query = query, args = copy(args) }
    return result
end

env.MySQL.insert.await = function(query, args) return mockWrite('insert', query, args) end
env.MySQL.update.await = function(query, args) return mockWrite('update', query, args) end
env.MySQL.query.await = function(query, args)
    if query:match('^%s*SELECT') and onDojRead then
        databaseReads[#databaseReads + 1] = query
        return onDojRead('query', query, args)
    end
    return mockWrite('query', query, args)
end

local function doj(name, ...)
    local callback = callbacks['ps-mdt:server:' .. name]
    assert(callback, 'Missing production callback: ' .. name)
    return callback(...)
end

local function mockDocumentReads(documents)
    onDojRead = function(operation, query, args)
        equal(operation, 'single')
        expect(query:find('FROM mdt_legal_documents WHERE id = ?', 1, true), 'Expected document lookup')
        return copy(documents[args[1]])
    end
end

test('DOJ source registers callbacks without running startup migration/reconciliation', function()
    local readsBefore, threadsBefore = #databaseReads, #scheduledThreads
    assert(loadfile('server/backend/doj.lua', 't', env))()
    equal(#databaseReads, readsBefore)
    equal(#databaseWrites, 0)
    equal(#scheduledThreads, threadsBefore + 1)
    expect(type(callbacks['ps-mdt:server:createLegalDocument']) == 'function')
    expect(type(callbacks['ps-mdt:server:reviewWarrantRequest']) == 'function')
end)

test('actual warrant review rejects AG approval and denial before any SQL mutation', function()
    identity(700, 'sadle', 'leo', 11, true)
    local writesBefore = #databaseWrites
    for _, decision in ipairs({ 'approved', 'denied' }) do
        local result = doj('reviewWarrantRequest', 700, 70, decision, 'Test decision')
        expect(not result.success)
        equal(result.error, 'Judicial authority required')
    end
    equal(#databaseWrites, writesBefore)
end)

test('actual court-order create update and revoke reject AG even when boss', function()
    identity(701, 'sadle', 'leo', 11, true)
    local writesBefore = #databaseWrites
    local payload = { type = 'subpoena', title = 'Test order', content = 'Test content' }
    expect(not doj('createCourtOrder', 701, payload).success)
    expect(not doj('updateCourtOrder', 701, 80, { content = 'Changed', status = 'active' }).success)
    expect(not doj('revokeCourtOrder', 701, 80).success)
    equal(#databaseWrites, writesBefore)
end)

test('actual judicial handlers reject clerks defenders and prosecutors with boss flags', function()
    local writesBefore = #databaseWrites
    for _, grade in ipairs({ 1, 2, 3, 4, 5, 6, 7 }) do
        local source = 710 + grade
        identity(source, 'sadoj', 'doj', grade, true)
        expect(not doj('reviewWarrantRequest', source, 70, 'approved', 'Test').success)
        expect(not doj('createCourtOrder', source, { type = 'subpoena', title = 'Test', content = 'Test' }).success)
    end
    equal(#databaseWrites, writesBefore)
end)

test('actual case administration rejects AG status judge and defense assignment edits', function()
    identity(720, 'sadle', 'leo', 11, true)
    for _, payload in ipairs({
        { status = 'closed' }, { closed_date = '2026-01-01 00:00:00' },
        { presiding_judge = 'OTHER' }, { presiding_judge_name = 'Other Judge' },
        { defense_attorney = 'OTHER' }, { defense_attorney_name = 'Other Defender' },
    }) do
        expect(not doj('updateCourtCase', 720, 1, payload).success)
    end
end)

test('actual document creation rejects AG judicial types and approval statuses', function()
    identity(730, 'sadle', 'leo', 11, true)
    for _, docType in ipairs({ 'ruling', 'opinion', 'sentencing' }) do
        expect(not doj('createLegalDocument', 730, {
            type = docType, title = 'Test', content = 'Test', status = 'draft',
        }).success, docType)
    end
    for _, status in ipairs({ 'approved', 'rejected' }) do
        expect(not doj('createLegalDocument', 730, {
            type = 'brief', title = 'Test', content = 'Test', status = status,
        }).success, status)
    end
end)

test('actual AG document reads edits and deletion protect another author draft', function()
    local current = identity(731, 'sadle', 'leo', 11, true)
    mockDocumentReads({
        [11] = { id = 11, type = 'brief', status = 'draft', author_citizenid = 'DEFENSE-PRIVATE' },
        [12] = { id = 12, type = 'brief', status = 'filed', author_citizenid = 'DEFENSE-SHARED' },
        [13] = { id = 13, type = 'brief', status = 'draft', author_citizenid = current.citizenid },
    })
    equal(doj('getLegalDocument', 731, 11), nil)
    expect(not doj('updateLegalDocument', 731, 11, { content = 'Tampered' }).success)
    expect(not doj('deleteLegalDocument', 731, 11).success)
    equal(doj('getLegalDocument', 731, 12).id, 12, 'Filed shared document remains readable')
    equal(doj('getLegalDocument', 731, 13).id, 13, 'Own draft remains readable')
end)

test('actual AG document list binds draft visibility to its server identifier', function()
    local current = identity(732, 'sadle', 'leo', 11, true)
    local countReads, pageReads = 0, 0
    onDojRead = function(operation, query, args)
        expect(query:find("(status != 'draft' OR author_citizenid = ?)", 1, true), 'Missing draft visibility predicate')
        equal(args[1], current.citizenid, 'Use server actor identifier')
        if operation == 'single' then countReads = countReads + 1; return { total = 1 } end
        equal(operation, 'query')
        pageReads = pageReads + 1
        return { { id = 12, status = 'filed' } }
    end
    local result = doj('getLegalDocuments', 732, 1, 20, 'all', 'all')
    equal(result.total, 1)
    equal(#result.documents, 1)
    equal(countReads, 1)
    equal(pageReads, 1)
end)

test('actual document update rejects relabeling old judicial types or approval reversal', function()
    local current = identity(733, 'sadle', 'leo', 11, true)
    mockDocumentReads({
        [20] = { id = 20, type = 'ruling', status = 'draft', author_citizenid = current.citizenid },
        [21] = { id = 21, type = 'brief', status = 'approved', author_citizenid = current.citizenid },
        [22] = { id = 22, type = 'brief', status = 'draft', author_citizenid = current.citizenid },
    })
    expect(not doj('updateLegalDocument', 733, 20, { type = 'brief', status = 'draft', content = 'Relabeled' }).success)
    expect(not doj('updateLegalDocument', 733, 21, { status = 'draft' }).success)
    expect(not doj('updateLegalDocument', 733, 22, { type = 'ruling' }).success)
    expect(not doj('updateLegalDocument', 733, 22, { status = 'approved' }).success)
    expect(not doj('updateLegalDocument', 733, 22, { status = 'rejected' }).success)
end)

test('actual AG can create its own brief draft with server-assigned authorship', function()
    local current = identity(734, 'sadle', 'leo', 11, true)
    local writesBefore = #databaseWrites
    onDojWrite = function(operation, query, args)
        equal(operation, 'insert')
        expect(query:find('INSERT INTO mdt_legal_documents', 1, true))
        equal(args[1], 42)
        equal(args[2], 'brief')
        equal(args[3], 'AG brief')
        equal(args[4], 'Draft content')
        equal(args[5], 'draft')
        equal(args[6], current.citizenid, 'Ignore forged payload author')
        return 100
    end
    local result = doj('createLegalDocument', 734, {
        court_case_id = 42, type = 'brief', title = 'AG brief', content = 'Draft content',
        author_citizenid = 'FORGED-AUTHOR',
    })
    expect(result.success)
    equal(result.id, 100)
    equal(#databaseWrites, writesBefore + 1)
end)

test('actual AG can edit and file its own draft but cannot alter the filed record', function()
    local current = identity(735, 'sadle', 'leo', 11, true)
    local documents = {
        [101] = { id = 101, type = 'brief', status = 'draft', author_citizenid = current.citizenid },
    }
    mockDocumentReads(documents)
    local writesBefore = #databaseWrites
    onDojWrite = function(operation, query, args)
        equal(operation, 'update')
        expect(query:find('UPDATE mdt_legal_documents SET', 1, true))
        equal(args[#args], 101)
        if query:find('content = ?', 1, true) then
            equal(args[1], 'Revised content')
        elseif query:find('status = ?', 1, true) then
            equal(args[1], 'filed')
            documents[101].status = 'filed'
        else
            error('Unexpected document mutation')
        end
        return 1
    end
    expect(doj('updateLegalDocument', 735, 101, { content = 'Revised content' }).success)
    expect(doj('updateLegalDocument', 735, 101, { status = 'filed' }).success)
    equal(#databaseWrites, writesBefore + 2)
    onDojWrite = nil
    expect(not doj('updateLegalDocument', 735, 101, { content = 'Post-filing overwrite' }).success)
    expect(not doj('updateLegalDocument', 735, 101, { status = 'draft' }).success)
    expect(not doj('deleteLegalDocument', 735, 101).success)
    equal(#databaseWrites, writesBefore + 2)
end)

test('actual nonboss District Judge can review warrants', function()
    local current = identity(740, 'sadoj', 'doj', 8, false)
    onDojRead = function(operation, query, args)
        equal(operation, 'single')
        expect(query:find('FROM mdt_warrant_requests WHERE id = ? AND status = ?', 1, true))
        equal(args[1], 70)
        equal(args[2], 'pending')
        return { id = 70, citizenid = 'TEST-DEFENDANT', status = 'pending' }
    end
    local stages = 0
    onDojWrite = function(operation, query, args)
        stages = stages + 1
        if stages == 1 then
            equal(operation, 'update')
            expect(query:find('UPDATE mdt_warrant_requests', 1, true))
            equal(args[1], 'approved')
            equal(args[2], current.citizenid)
        else
            equal(stages, 2)
            equal(operation, 'insert')
            expect(query:find('INSERT INTO mdt_warrant_reviews', 1, true))
            equal(args[1], 70)
            equal(args[2], current.citizenid)
            equal(args[4], 'approved')
        end
        return 1
    end
    expect(doj('reviewWarrantRequest', 740, 70, 'approved', 'Judicial decision').success)
    equal(stages, 2)
end)

test('actual nonboss District Judge can create update and revoke court orders', function()
    identity(741, 'sadoj', 'doj', 8, false)
    local stages = 0
    onDojWrite = function(operation, query, args)
        stages = stages + 1
        if stages == 1 then
            equal(operation, 'insert')
            expect(query:find('INSERT INTO mdt_court_orders', 1, true))
            equal(args[2], 'subpoena')
            equal(args[3], 'Judicial subpoena')
            return 200
        end
        equal(operation, 'update')
        expect(query:find('UPDATE mdt_court_orders SET', 1, true))
        if stages == 2 then expect(query:find('order_number = ?', 1, true)) end
        if stages == 3 then equal(args[1], 'Amended content') end
        if stages == 4 then equal(args[1], 'revoked') end
        return 1
    end
    local created = doj('createCourtOrder', 741, {
        type = 'subpoena', title = 'Judicial subpoena', content = 'Ordered appearance',
    })
    expect(created.success)
    equal(created.id, 200)
    expect(doj('updateCourtOrder', 741, 200, { content = 'Amended content' }).success)
    expect(doj('revokeCourtOrder', 741, 200).success)
    equal(stages, 4)
end)

test('actual nonboss District Judge can issue rulings and approve filed documents', function()
    local current = identity(742, 'sadoj', 'doj', 8, false)
    mockDocumentReads({
        [201] = { id = 201, type = 'motion', status = 'filed', author_citizenid = 'OTHER-PARTY' },
    })
    local stages = 0
    onDojWrite = function(operation, query, args)
        stages = stages + 1
        if stages == 1 then
            equal(operation, 'insert')
            expect(query:find('INSERT INTO mdt_legal_documents', 1, true))
            equal(args[2], 'ruling')
            equal(args[5], 'approved')
            equal(args[6], current.citizenid)
            return 202
        end
        equal(operation, 'update')
        expect(query:find('UPDATE mdt_legal_documents SET status = ?', 1, true))
        equal(args[1], 'approved')
        equal(args[2], 201)
        return 1
    end
    expect(doj('createLegalDocument', 742, {
        type = 'ruling', title = 'Judicial ruling', content = 'Motion granted', status = 'approved',
    }).success)
    expect(doj('updateLegalDocument', 742, 201, { status = 'approved' }).success)
    equal(stages, 2)
end)

test('actual DOJ callbacks reject government operational calls before any writes', function()
    identity(750, 'sagov', 'gov', 9, true)
    expect(not doj('reviewWarrantRequest', 750, 70, 'approved', 'Test').success)
    expect(not doj('createCourtOrder', 750, { type = 'subpoena', title = 'Test', content = 'Test' }).success)
    expect(not doj('updateCourtOrder', 750, 200, { status = 'active' }).success)
    expect(not doj('revokeCourtOrder', 750, 200).success)
    expect(not doj('createLegalDocument', 750, { type = 'brief', title = 'Test' }).success)
    expect(not doj('updateLegalDocument', 750, 101, { status = 'filed' }).success)
    expect(not doj('deleteLegalDocument', 750, 101).success)
    equal(doj('getLegalDocument', 750, 101), nil)
end)

-- The bridge returns job definitions, including per-grade framework boss flags.
-- The viewing actor's boss status must not overwrite these definitions.
sharedJobs.lspd = {
    label = 'Los Santos Police Department', type = 'leo', grades = {
        ['0'] = { name = 'Recruit' }, ['1'] = { name = 'Officer' },
        ['10'] = { name = 'Chief', isboss = true },
    },
}
sharedJobs.pillboxmed = {
    label = 'Pillbox Hill Medical Center', type = 'ems', grades = {
        ['0'] = { name = 'Trainee' }, ['8'] = { name = 'RN' },
        ['13'] = { name = 'Medical Director', isboss = true },
    },
}
sharedJobs.sadle = {
    label = 'San Andreas Division of Law Enforcement', type = 'leo', grades = {
        ['2'] = { name = 'State Officer' },
        ['10'] = { name = 'Division Chief', isboss = true },
        ['11'] = { name = 'Attorney General', isboss = true },
    },
}
sharedJobs.sadoj = {
    label = 'San Andreas Department of Justice', type = 'doj', grades = {
        ['5'] = { name = 'Assistant District Attorney' },
        ['6'] = { name = 'District Attorney' },
        ['7'] = { name = 'Clerk of the Court', isboss = true },
        ['8'] = { name = 'District Judge' },
        ['9'] = { name = 'Associate Justice', isboss = true },
        ['10'] = { name = 'Chief Justice', isboss = true },
    },
}

local function roleByGrade(result, grade)
    for _, role in ipairs(result.roles or {}) do
        if role.key == tostring(grade) then return role end
    end
    error('Expected management role grade ' .. grade)
end

local function mockRoleReads(jobName, rows)
    onDojRead = function(operation, query, args)
        equal(operation, 'query')
        expect(query:find('SELECT grade, permissions FROM mdt_permission_roles WHERE job = ?', 1, true))
        equal(args[1], jobName, 'Role query must use actual employer')
        return copy(rows or {})
    end
end

test('management source registers actual callbacks without startup work', function()
    local readsBefore, writesBefore, threadsBefore = #databaseReads, #databaseWrites, #scheduledThreads
    assert(loadfile('server/backend/management.lua', 't', env))()
    equal(#databaseReads, readsBefore)
    equal(#databaseWrites, writesBefore)
    equal(#scheduledThreads, threadsBefore)
    expect(type(callbacks['ps-mdt:server:getPermissionRoles']) == 'function')
    expect(type(callbacks['ps-mdt:server:updatePermissionRole']) == 'function')
end)

test('actual LEO boss role view keeps nonboss grade flags and boss LEO grants', function()
    identity(800, 'lspd', 'leo', 10, true)
    mockRoleReads('lspd')
    local result = doj('getPermissionRoles', 800)
    equal(result.job, 'lspd')
    equal(#result.roles, 3)
    equal(roleByGrade(result, 0).isBoss, false)
    equal(roleByGrade(result, 1).isBoss, false)
    equal(roleByGrade(result, 10).isBoss, true)
    expect(includes(roleByGrade(result, 10).permissions, 'warrants_issue'))
    expect(includes(roleByGrade(result, 10).permissions, 'management_permissions'))
    expect(not includes(roleByGrade(result, 10).permissions, 'judicial_authority'))
    expect(not includes(roleByGrade(result, 10).permissions, 'warrants_approve'))
end)

test('actual EMS boss role rows and catalog exclude police-only grants', function()
    identity(801, 'pillboxmed', 'ems', 13, true)
    decodedFixtures.stored_ems_police = { 'reports_view', 'warrants_issue', 'court_edit' }
    mockRoleReads('pillboxmed', { { grade = 8, permissions = 'stored_ems_police' } })
    local result = doj('getPermissionRoles', 801)
    equal(result.job, 'pillboxmed')
    equal(roleByGrade(result, 8).isBoss, false)
    equal(roleByGrade(result, 13).isBoss, true)
    expect(includes(roleByGrade(result, 8).permissions, 'reports_view'))
    expect(includes(roleByGrade(result, 13).permissions, 'reports_view'))
    for _, permissions in ipairs({ result.permissions, roleByGrade(result, 8).permissions, roleByGrade(result, 13).permissions }) do
        for _, forbidden in ipairs({ 'warrants_issue', 'warrants_close', 'court_edit', 'vehicles_search', 'weapons_add' }) do
            expect(not includes(permissions, forbidden), forbidden)
        end
    end
end)

test('actual management preserves explicitly empty stored nonboss grants over defaults', function()
    identity(802, 'lspd', 'leo', 10, true)
    decodedFixtures.explicit_empty = {}
    env.Config.PermissionDefaults.lspd = { ['1'] = { 'reports_view', 'warrants_issue' } }
    mockRoleReads('lspd', { { grade = 1, permissions = 'explicit_empty' } })
    local result = doj('getPermissionRoles', 802)
    equal(#roleByGrade(result, 1).permissions, 0)
    equal(roleByGrade(result, 1).isBoss, false)
end)

test('actual AG management row removes warrant granting closure and court mutations', function()
    identity(803, 'sadle', 'leo', 11, true)
    mockRoleReads('sadle')
    local result = doj('getPermissionRoles', 803)
    local agRole = roleByGrade(result, 11)
    equal(agRole.isBoss, true, 'Framework flag remains unchanged')
    expect(includes(agRole.permissions, 'court_view'))
    expect(includes(agRole.permissions, 'reports_view'))
    for _, permission in ipairs({
        'warrants_issue', 'warrants_close', 'warrants_approve', 'judicial_authority',
        'court_create', 'court_edit', 'court_delete',
    }) do
        expect(not includes(agRole.permissions, permission), permission)
    end
    expect(includes(roleByGrade(result, 10).permissions, 'warrants_issue'), 'Other LEO boss retains operational warrant feature')
end)

test('actual permission save rejects foreign employer and unknown grades without writes', function()
    identity(804, 'lspd', 'leo', 10, true)
    local writesBefore = #databaseWrites
    expect(not doj('updatePermissionRole', 804, { job = 'bcso', grade = 1, permissions = { 'reports_view' } }).success)
    for _, grade in ipairs({ -1, 2, 999, 1.5, 'not-a-grade' }) do
        expect(not doj('updatePermissionRole', 804, { job = 'lspd', grade = grade, permissions = { 'reports_view' } }).success)
    end
    equal(#databaseWrites, writesBefore)
end)

test('actual permission save rejects computed judicial and unknown grants without writes', function()
    identity(805, 'sadoj', 'doj', 10, true)
    local writesBefore = #databaseWrites
    for _, permission in ipairs({ 'judicial_authority', 'warrants_approve', 'invented_permission' }) do
        expect(not doj('updatePermissionRole', 805, { job = 'sadoj', grade = 8, permissions = { permission } }).success)
    end
    equal(#databaseWrites, writesBefore)
end)

test('actual EMS permission save rejects out-of-domain police grants without writes', function()
    identity(806, 'pillboxmed', 'ems', 13, true)
    local writesBefore = #databaseWrites
    for _, permission in ipairs({ 'warrants_issue', 'court_edit', 'vehicles_search', 'weapons_add' }) do
        expect(not doj('updatePermissionRole', 806, { job = 'pillboxmed', grade = 8, permissions = { permission } }).success)
    end
    equal(#databaseWrites, writesBefore)
end)

test('actual AG cannot store court mutations or warrant authority into its own grade', function()
    identity(807, 'sadle', 'leo', 11, true)
    local writesBefore = #databaseWrites
    for _, permission in ipairs({ 'warrants_issue', 'warrants_close', 'court_create', 'court_edit', 'court_delete' }) do
        expect(not doj('updatePermissionRole', 807, { job = 'sadle', grade = 11, permissions = { permission } }).success)
    end
    equal(#databaseWrites, writesBefore)
end)

test('actual valid own-employer permission save normalizes only requested grants', function()
    local current = identity(808, 'lspd', 'leo', 10, true)
    local writesBefore = #databaseWrites
    onDojWrite = function(operation, query, args)
        equal(operation, 'update')
        expect(query:find('INSERT INTO mdt_permission_roles', 1, true))
        equal(args[1], 'lspd')
        equal(args[2], 1)
        equal(args[4], current.citizenid)
        local permissions = env.json.decode(args[3])
        equal(#permissions, 2)
        equal(permissions[1], 'reports_view')
        equal(permissions[2], 'tab_hidden_reports')
        expect(not includes(permissions, 'management_permissions'), 'Do not expand saved grants because actor is boss')
        return 1
    end
    expect(doj('updatePermissionRole', 808, {
        job = 'lspd', grade = '1', permissions = { 'reports_view', 'tab_hidden_reports', 'reports_view' },
    }).success)
    equal(#databaseWrites, writesBefore + 1)
end)

test('actual government cannot read or save operational permission roles', function()
    identity(809, 'sagov', 'gov', 9, true)
    local writesBefore = #databaseWrites
    equal(#doj('getPermissionRoles', 809), 0)
    expect(not doj('updatePermissionRole', 809, { job = 'sagov', grade = 6, permissions = {} }).success)
    equal(#databaseWrites, writesBefore)
end)

local function mockHearingReads(hearing)
    onDojRead = function(operation, query, args)
        if operation == 'single' then
            expect(query:find('FROM mdt_court_hearings', 1, true), 'Expected hearing lookup')
            equal(args[1], hearing.id)
            return copy(hearing)
        end
        equal(operation, 'query')
        expect(query:find('FROM mdt_court_attendees', 1, true), 'Expected attendee lookup')
        return {}
    end
end

test('court source registers callbacks without running lifecycle or reminders', function()
    local readsBefore, writesBefore, threadsBefore = #databaseReads, #databaseWrites, #scheduledThreads
    assert(loadfile('server/backend/court.lua', 't', env))()
    equal(#databaseReads, readsBefore)
    equal(#databaseWrites, writesBefore)
    equal(#scheduledThreads, threadsBefore + 1)
    expect(type(callbacks['ps-mdt:server:updateHearing']) == 'function')
    expect(type(callbacks['ps-mdt:server:setHearingStatus']) == 'function')
end)

test('nonjudicial LEO can save normal court form with unchanged status and judge', function()
    identity(900, 'lspd', 'leo', 10, true)
    mockHearingReads({
        id = 901, category = 'court', status = 'scheduled', job_type = 'police',
        judge_cid = 'JUDGE-1', judge_name = 'Existing Judge',
    })
    local writesBefore, hearingUpdates = #databaseWrites, 0
    onDojWrite = function(operation, query, args)
        equal(operation, 'update')
        if query:find('UPDATE mdt_court_attendees SET notified_at', 1, true) then
            equal(args[1], 901)
        else
            expect(query:find('UPDATE mdt_court_hearings SET', 1, true))
            expect(not query:find('status = ?', 1, true), 'Do not write protected status back')
            expect(not query:find('judge_cid = ?', 1, true), 'Do not write protected judge ID back')
            expect(not query:find('judge_name = ?', 1, true), 'Do not write protected judge name back')
            equal(args[#args], 901)
            hearingUpdates = hearingUpdates + 1
        end
        return 1
    end
    local result = doj('updateHearing', 900, { hearingId = 901, data = {
        title = 'Revised hearing title', category = 'court', hearing_type = 'trial',
        scheduled_at = '2026-11-01 12:00:00', duration_minutes = 30,
        location = 'Main courthouse', judge_cid = 'JUDGE-1', judge_name = 'Existing Judge',
        status = 'scheduled', notes = 'Revised nonjudicial scheduling notes',
    } })
    expect(result.success)
    equal(hearingUpdates, 1)
    equal(#databaseWrites, writesBefore + 2)
end)

test('nonjudicial court save accepts unchanged empty judge fields', function()
    identity(902, 'lspd', 'leo', 10, true)
    mockHearingReads({ id = 902, category = 'court', status = 'scheduled', job_type = 'police' })
    onDojWrite = function(operation, query, args)
        equal(operation, 'update')
        expect(query:find('UPDATE mdt_court_hearings SET title = ?', 1, true))
        expect(not query:find('judge_', 1, true))
        expect(not query:find('status = ?', 1, true))
        equal(args[#args], 902)
        return 1
    end
    expect(doj('updateHearing', 902, { hearingId = 902, data = {
        title = 'Unassigned hearing', status = 'scheduled', judge_cid = '', judge_name = '',
    } }).success)
end)

test('nonjudicial court edits reject actual status and judge changes before writes', function()
    identity(903, 'lspd', 'leo', 10, true)
    mockHearingReads({
        id = 903, category = 'court', status = 'scheduled', job_type = 'police',
        judge_cid = 'JUDGE-1', judge_name = 'Existing Judge',
    })
    local writesBefore = #databaseWrites
    for _, data in ipairs({
        { status = 'in_session' }, { status = 'cancelled' },
        { judge_cid = 'JUDGE-2' }, { judge_name = 'Replacement Judge' },
        { judge_cid = '' }, { judge_name = '' },
        { category = 'training', status = 'cancelled' },
        { category = 'training', judge_name = 'Replacement Judge' },
    }) do
        local result = doj('updateHearing', 903, { hearingId = 903, data = data })
        expect(not result.success)
        equal(result.error, 'Judicial authority required for judge assignments or court status')
    end
    equal(#databaseWrites, writesBefore)
end)

test('AG remains unable to edit court events even with unchanged protected fields', function()
    identity(904, 'sadle', 'leo', 11, true)
    mockHearingReads({
        id = 904, category = 'court', status = 'scheduled', job_type = 'police',
        judge_name = 'Existing Judge',
    })
    local result = doj('updateHearing', 904, { hearingId = 904, data = {
        title = 'Attempted AG edit', status = 'scheduled', judge_name = 'Existing Judge',
    } })
    expect(not result.success)
    equal(result.error, 'No permission')
end)

test('judicial court editor retains protected status and judge mutations', function()
    identity(905, 'sadoj', 'doj', 8, false)
    decodedFixtures.judge_calendar_grants = { 'court_view', 'court_create', 'court_edit' }
    roleRows['sadoj:8'] = { permissions = 'judge_calendar_grants' }
    mockHearingReads({
        id = 905, category = 'court', status = 'scheduled', job_type = 'police',
        judge_cid = 'OLD-JUDGE', judge_name = 'Old Judge',
    })
    onDojWrite = function(operation, query, args)
        equal(operation, 'update')
        expect(query:find('judge_cid = ?', 1, true))
        expect(query:find('judge_name = ?', 1, true))
        expect(query:find('status = ?', 1, true))
        equal(args[1], 'NEW-JUDGE')
        equal(args[2], 'New Judge')
        equal(args[3], 'adjourned')
        equal(args[4], 905)
        return 1
    end
    expect(doj('updateHearing', 905, { hearingId = 905, data = {
        judge_cid = 'NEW-JUDGE', judge_name = 'New Judge', status = 'adjourned',
    } }).success)
end)

test('nonjudicial EMS and LEO training edits retain status and instructor fields', function()
    for _, spec in ipairs({ { 906, 'pillboxmed', 'ems', 'ems' }, { 907, 'lspd', 'leo', 'police' } }) do
        local source = spec[1]
        identity(source, spec[2], spec[3], 13, true)
        mockHearingReads({ id = source, category = 'training', status = 'scheduled', job_type = spec[4] })
        onDojWrite = function(operation, query, args)
            equal(operation, 'update')
            expect(query:find('judge_name = ?', 1, true), 'Training lead field remains editable')
            expect(query:find('status = ?', 1, true), 'Training status remains editable')
            equal(args[1], 'Training Instructor')
            equal(args[2], 'adjourned')
            equal(args[3], source)
            return 1
        end
        expect(doj('updateHearing', source, { hearingId = source, data = {
            judge_name = 'Training Instructor', status = 'adjourned',
        } }).success)
    end
end)

test('court reads update and status changes preserve police versus EMS domains', function()
    for _, spec in ipairs({
        { 908, 'lspd', 'leo', 'ems', 'training' },
        { 909, 'pillboxmed', 'ems', 'police', 'court' },
    }) do
        local source = spec[1]
        identity(source, spec[2], spec[3], 13, true)
        mockHearingReads({ id = source, category = spec[5], status = 'scheduled', job_type = spec[4] })
        expect(not doj('getHearing', source, { hearingId = source }).success)
        local updated = doj('updateHearing', source, { hearingId = source, data = { title = 'Cross-domain' } })
        expect(not updated.success)
        equal(updated.error, 'Unauthorized calendar')
        local changed = doj('setHearingStatus', source, { hearingId = source, status = 'adjourned' })
        expect(not changed.success)
        equal(changed.error, 'Unauthorized calendar')
    end
end)

test('calendar range reads keep DOJ and LEO together while separating EMS', function()
    for _, spec in ipairs({
        { 910, 'lspd', 'leo', 10, true, 'police' },
        { 911, 'sadoj', 'doj', 8, false, 'police' },
        { 912, 'pillboxmed', 'ems', 13, true, 'ems' },
    }) do
        identity(spec[1], spec[2], spec[3], spec[4], spec[5])
        onDojRead = function(operation, query, args)
            equal(operation, 'query')
            expect(query:find('WHERE h.job_type = ?', 1, true))
            equal(args[1], spec[6])
            return {}
        end
        equal(#doj('getHearings', spec[1], { from = '2026-11-01 00:00:00', to = '2026-12-01 00:00:00' }), 0)
    end
end)

test('nonjudicial court status endpoint remains denied and training endpoint remains usable', function()
    identity(913, 'lspd', 'leo', 10, true)
    mockHearingReads({ id = 913, category = 'court', status = 'scheduled', job_type = 'police' })
    expect(not doj('setHearingStatus', 913, { hearingId = 913, status = 'adjourned' }).success)
    identity(914, 'pillboxmed', 'ems', 13, true)
    mockHearingReads({ id = 914, category = 'training', status = 'scheduled', job_type = 'ems' })
    onDojWrite = function(operation, query, args)
        equal(operation, 'update')
        expect(query:find('UPDATE mdt_court_hearings SET status = ?', 1, true))
        equal(args[1], 'adjourned')
        equal(args[2], 914)
        return 1
    end
    expect(doj('setHearingStatus', 914, { hearingId = 914, status = 'adjourned' }).success)
end)

test('off-duty LEO cannot use legacy callbacks or operational permissions', function()
    identity(990, 'lspd', 'leo', 10, true, false)
    local access = env.GetMdtAccess(990)
    expect(access.eligible)
    expect(not access.authorized)
    expect(not env.CheckAuth(990))
    expect(not env.CheckPermission(990, 'cases_view'))
    expect(not env.CheckPermission(990, 'management_permissions'))
    local perms = callbacks['ps-mdt:server:getMyPermissions'](990)
    equal(#perms.permissions, 0)
end)

test('off-duty SADLE AG cannot read statewide rosters', function()
    local current = identity(991, 'sadle', 'leo', 11, true, false)
    expect(not env.CheckAuth(991))
    expect(not env.CanViewStatewideLeoRoster(991))
    current.job.onduty = true
    expect(env.CheckAuth(991))
    expect(env.CanViewStatewideLeoRoster(991))
end)

test('legacy login tracking rejects off-duty sessions', function()
    identity(992, 'bcso', 'leo', 16, true, false)
    local handler = events['ps-mdt:server:trackLogin']
    expect(type(handler) == 'function')
    -- Source is supplied by the FiveM event runtime, not a callback argument.
    env.source = 992
    local before = #databaseWrites
    local ok, err = pcall(handler)
    env.source = nil
    expect(ok, tostring(err))
    equal(#databaseWrites, before)
end)

test('Stage 2 opt-in calendar reads bind employer and preserve court permission', function()
    identity(980, 'lspd', 'leo', 10, true)
    env.Config.Court.DepartmentCalendarOwnership = true
    onDojRead = function(operation, query, args)
        equal(operation, 'query')
        expect(query:find("h.owner_job = ?", 1, true), 'Employer calendar filter missing')
        expect(query:find("h.category = 'court' AND ? = 1", 1, true), 'Court permission filter missing')
        equal(args[1], 'police')
        equal(args[#args], 'lspd')
        return {}
    end
    local ok, result = pcall(function()
        return doj('getHearings', 980, { from = '2026-11-01 00:00:00', to = '2026-12-01 00:00:00' })
    end)
    env.Config.Court.DepartmentCalendarOwnership = false
    expect(ok, tostring(result))
    equal(#result, 0)
end)

test('Stage 2 calendar rejects other-employer detail while preserving legacy mode', function()
    identity(981, 'lspd', 'leo', 10, true)
    env.Config.Court.DepartmentCalendarOwnership = true
    onDojRead = function(operation, query)
        equal(operation, 'single')
        expect(query:find('FROM mdt_court_hearings', 1, true))
        return { id = 981, job_type = 'police', category = 'training', owner_job = 'bcso' }
    end
    local ok, result = pcall(function()
        return doj('getHearing', 981, { hearingId = 981 })
    end)
    env.Config.Court.DepartmentCalendarOwnership = false
    expect(ok, tostring(result))
    expect(not result.success, 'Cross-employer event detail leaked')
end)

test('Stage 2 calendar notifications acknowledge only returned authorized event IDs', function()
    identity(993, 'lspd', 'leo', 10, true)
    env.Config.Court.DepartmentCalendarOwnership = true
    local writesBefore = #databaseWrites
    onDojRead = function(operation, query, args)
        equal(operation, 'query')
        expect(query:find("h.owner_job = ?", 1, true), 'Missing employer restriction')
        equal(args[1], 'TEST-993')
        equal(args[2], 'police')
        equal(args[#args], 'lspd')
        return { { hearing_id = 17, title = 'Agency briefing' }, { hearing_id = 23, title = 'Duty refresher' } }
    end
    onDojWrite = function(operation, query, args)
        equal(operation, 'update')
        expect(query:find('hearing_id IN (?,?)', 1, true), 'Delivery update must restrict selected event IDs')
        equal(args[1], 'TEST-993')
        equal(args[2], 17)
        equal(args[3], 23)
        return 2
    end
    local ok, result = pcall(function() return doj('getMissedHearings', 993) end)
    env.Config.Court.DepartmentCalendarOwnership = false
    expect(ok, tostring(result))
    equal(#result, 2)
    equal(#databaseWrites, writesBefore + 1)
end)

test('Stage 2 calendar list discards records after an employer transfer during SQL', function()
    identity(994, 'lspd', 'leo', 10, true)
    env.Config.Court.DepartmentCalendarOwnership = true
    onDojRead = function(operation, query, args)
        equal(operation, 'query')
        equal(args[#args], 'lspd')
        identity(994, 'bcso', 'leo', 10, true)
        return { { id = 71, title = 'LSPD training', category = 'training', owner_job = 'lspd' } }
    end
    local ok, result = pcall(function()
        return doj('getHearings', 994, { from = '2026-11-01 00:00:00', to = '2026-12-01 00:00:00' })
    end)
    env.Config.Court.DepartmentCalendarOwnership = false
    expect(ok, tostring(result))
    equal(#result, 0, 'Transferred employee must not receive former employer events')
end)

test('Stage 2 calendar detail drops attendees when job changes during second SQL', function()
    identity(995, 'lspd', 'leo', 10, true)
    env.Config.Court.DepartmentCalendarOwnership = true
    onDojRead = function(operation, query, args)
        if operation == 'single' then
            expect(query:find('FROM mdt_court_hearings', 1, true))
            return { id = 77, job_type = 'police', category = 'training', owner_job = 'lspd' }
        end
        equal(operation, 'query')
        identity(995, 'bcso', 'leo', 10, true)
        return { { id = 9, display_name = 'Confidential attendee' } }
    end
    local ok, response = pcall(function() return doj('getHearing', 995, { hearingId = 77 }) end)
    env.Config.Court.DepartmentCalendarOwnership = false
    expect(ok, tostring(response))
    expect(not response.success, 'Attendees should be withheld after employer change')
end)

print(('Phase 1 access regressions: %d passed, %d failed, %d assertions; all SQL mocked.')
    :format(passed, failed, assertions))
if failed > 0 then os.exit(1) end
