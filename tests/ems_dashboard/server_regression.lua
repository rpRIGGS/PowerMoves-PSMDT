-- Run from the repository root: lua tests/ems_dashboard/server_regression.lua
-- Loads real config/auth/helpers/dashboard/warrant code. Framework, dispatch and
-- SQL are isolated fixtures; writes are forbidden and startup threads never run.
-- This checks callback/security contracts, not a FiveM or real MySQL runtime.

local callbacks, events, exported, scheduled, sent = {}, {}, {}, {}, {}
local players, roles, jsonFixtures, reads, failures, cache = {}, {}, {}, {}, {}, {}
local currentSource, afterRead, afterRoleRead
local timer, serial, passed, failed, assertions, writes = 10000, 0, 0, 0, 0, 0
local dispatchCalls, unitCounts = {}, {}
local countRequests, cacheRequests = {}, {}
local reference = {}
assert(loadfile('planning-reference/jobs.lua', 't', reference))()
local jobs = reference.QBShared.Jobs

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
    expect(actual == expected, (message or 'Unexpected value') .. ': expected '
        .. tostring(expected) .. ', got ' .. tostring(actual))
end

local function contains(values, wanted)
    for _, value in ipairs(values or {}) do if value == wanted then return true end end
    return false
end

local function ids(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do out[#out + 1] = tostring(row.id) end
    table.sort(out)
    return table.concat(out, ',')
end

local function player(source)
    assert(players[source], 'Unknown framework source ' .. tostring(source))
    return players[source]
end

local function identity(source, jobName, jobType, grade, boss, duty)
    local definition = jobs[jobName] or {}
    local gradeData = (definition.grades or {})[tostring(grade or 1)] or {}
    local data = {
        source = source, citizenid = 'CID-' .. source,
        job = { name = jobName, type = jobType or definition.type, label = definition.label,
            grade = { level = grade or 1, name = gradeData.name or 'Fixture rank' },
            payment = gradeData.payment or 321, isboss = boss == true, onduty = duty ~= false },
    }
    players[source] = data
    return data
end

local function grant(jobName, grade, permissions)
    serial = serial + 1
    local token = 'permissions-' .. serial
    jsonFixtures[token] = copy(permissions)
    roles[jobName .. ':' .. grade] = { permissions = token }
end

local function forbidWrite()
    writes = writes + 1
    error('Regression harness forbids database writes', 2)
end

local reports = {
    { id = 1, age = 1, grants = {}, title = 'Public existing report' },
    { id = 2, age = 2, grants = {{ 'jobtype', 'ems' }}, title = 'EMS report' },
    { id = 3, age = 3, grants = {{ 'job', 'lsfd' }}, title = 'Fire department report' },
    { id = 4, age = 5, grants = {{ 'citizenid', 'CID-1' }}, title = 'Explicit citizen grant' },
    { id = 5, age = 1, grants = {{ 'jobtype', 'leo' }}, title = 'POLICE PRIVATE' },
    { id = 6, age = 8, grants = {{ 'job', 'pillboxmed' }}, title = 'Hospital report' },
    { id = 7, age = 2, grants = {{ 'citizenid', 'PRIVATE-CID' }}, title = 'Other private report' },
    { id = 8, age = 9, grants = {{ 'jobtype', 'ems' }, { 'job', 'lsfd' }}, title = 'Multiple matching grants' },
    { id = 9, age = 35, grants = {}, title = 'Old public report' },
}
local hearings = {
    { id = 21, job_type = 'ems', category = 'training', title = 'Medical training' },
    { id = 22, job_type = 'ems', category = 'meeting', title = 'EMS meeting' },
    { id = 23, job_type = 'ems', category = 'other', title = 'EMS event' },
    { id = 24, job_type = 'ems', category = 'court', title = 'Invalid legacy court row' },
    { id = 25, job_type = 'police', category = 'court', title = 'PRIVATE COURT HEARING' },
}
local posts = {
    { id = 31, job = 'lsfd', content = 'Own fire bulletin' },
    { id = 32, job = 'pillboxmed', content = 'Other hospital bulletin' },
    { id = 33, job = 'lspd', content = 'PRIVATE POLICE BULLETIN' },
}

local function visibleReports(cid, jobName, jobType, doj)
    local rows = {}
    for _, report in ipairs(reports) do
        local visible, emsRestricted = #report.grants == 0, false
        for _, restriction in ipairs(report.grants) do
            local kind, identifier = restriction[1], restriction[2]
            if kind == 'jobtype' and identifier == 'ems' then emsRestricted = true end
            if (kind == 'citizenid' and identifier == cid)
                or (kind == 'job' and identifier == jobName)
                or (kind == 'jobtype' and identifier == jobType) then visible = true end
        end
        if doj and not emsRestricted then visible = true end
        if visible then rows[#rows + 1] = copy(report) end
    end
    return rows
end

local function databaseFailure(message)
    failures[#failures + 1] = message
    error(message, 3)
end

local function check(condition, message)
    if not condition then databaseFailure(message) end
end

local function emsCaller()
    if not currentSource or not players[currentSource] then return false end
    local data = players[currentSource]
    return exported.IsEmsJob and exported.IsEmsJob(data.job.name, data.job.type)
end

local function assertEmsReportScope(query, args)
    check(query:find('NOT EXISTS', 1, true) and query:find('OR EXISTS', 1, true),
        'EMS reports must preserve public-or-explicit ACL')
    check(query:find('restricted.reportid = mr.id', 1, true)
        and query:find('granted.reportid = mr.id AND (', 1, true), 'ACL must bind every grant to the same report')
    for _, kind in ipairs({ 'citizenid', 'job', 'jobtype' }) do
        check(query:find("granted.type = '" .. kind .. "' AND granted.identifier = ?", 1, true),
            'Missing bound report ' .. kind .. ' restriction')
    end
    check(args[1] == player(currentSource).citizenid, 'Report CID must come from server identity')
    check(args[2] == player(currentSource).job.name, 'Report job must come from server identity')
    check(args[3] == 'ems', 'Report domain must be EMS')
    check(not query:find(' OR 1', 1, true), 'Unrestricted report ACL bypass')
end

local function readDatabase(kind, query, args)
    args = args or {}
    local compact = query:gsub('%s+', ' ')
    check(compact:match('^%s*SELECT') ~= nil, 'Only SELECT statements may reach mock SQL')
    reads[#reads + 1] = { query = compact, args = copy(args), source = currentSource, kind = kind }
    local result
    if compact:find('FROM mdt_permission_roles', 1, true) then
        check(kind == 'single' and #args == 2, 'Role lookup contract changed')
        result = copy(roles[tostring(args[1]) .. ':' .. tostring(args[2])])
        if afterRoleRead then local hook = afterRoleRead; afterRoleRead = nil; hook() end
        return result
    elseif compact:find('FROM mdt_profile_sessions', 1, true) then
        check(#args == 1 and args[1] == player(currentSource).citizenid,
            'Duty history must query only caller CID')
        result = { { day = os.date('%Y-%m-%d'), seconds = 7200 } }
    elseif compact:find('FROM mdt_bulletin_posts', 1, true) then
        check(compact:find('WHERE job = ?', 1, true) and #args == 1
            and args[1] == player(currentSource).job.name, 'Bulletins must use exact server-side job')
        result = {}
        for _, row in ipairs(posts) do
            if row.job == args[1] then result[#result + 1] = { id = row.id, content = row.content } end
        end
    elseif compact:find('FROM mdt_bulletins', 1, true) then
        check(not emsCaller(), 'EMS queried unscoped legacy bulletins')
        result = { { id = 99, content = 'LEGACY GLOBAL BULLETIN' } }
    elseif compact:find('FROM mdt_court_hearings', 1, true) then
        check(#args == 1, 'Calendar domain must be bound')
        if emsCaller() then
            check(args[1] == 'ems', 'EMS queried police calendar')
            check(compact:find("category IN ('training', 'meeting', 'other')", 1, true),
                'EMS calendar must exclude court-only categories')
            check(not compact:find('defendant_name', 1, true), 'EMS calendar exposed court-only field')
        end
        result = {}
        for _, row in ipairs(hearings) do
            if row.job_type == args[1] and (not emsCaller() or row.category ~= 'court') then
                result[#result + 1] = copy(row)
            end
        end
    elseif compact:find('FROM mdt_reports mr WHERE', 1, true) then
        assertEmsReportScope(compact, args)
        local rows = visibleReports(args[1], args[2], args[3])
        if compact:find('COUNT(', 1, true) then
            local _, distinct = compact:gsub('COUNT%(DISTINCT', '')
            local isUsage = compact:find(' AS reportsLast7', 1, true) ~= nil
            check(distinct == (isUsage and 3 or 2), 'All EMS report counts must be distinct')
            check(#args == 3, 'Counts must bind only CID/job/domain')
            local total, week, lastWeek, month = 0, 0, 0, 0
            for _, row in ipairs(rows) do
                total = total + 1
                if row.age <= 7 then week = week + 1 end
                if row.age > 7 and row.age <= 14 then lastWeek = lastWeek + 1 end
                if row.age <= 30 then month = month + 1 end
            end
            result = { isUsage and { reports = total, reportsLast7 = week, reportsLast30 = month }
                or { totalThisWeek = week, totalLastWeek = lastWeek } }
        else
            check(#args == 5 and args[4] == 10 and args[5] == 0, 'Existing report pagination contract changed')
            check(compact:find('LIMIT ? OFFSET ?', 1, true), 'Pagination must remain bound')
            result = rows
        end
    elseif compact:find('FROM mdt_reports mr', 1, true) then
        check(not emsCaller(), 'EMS reached old report query instead of scoped ACL')
        check(#args == 8, 'Legacy LEO/DOJ report callback contract changed')
        result = visibleReports(args[4], args[5], args[6], args[1] == 'doj')
    elseif compact:find('FROM mdt_reports_warrants', 1, true) then
        check(not emsCaller(), 'EMS queried private warrant records')
        result = kind == 'scalar' and 777 or { { reportid = 70, citizenid = 'PRIVATE-CID',
            firstname = 'Warrant', lastname = 'Subject', felonies = 2, misdemeanors = 1,
            infractions = 0, expirydate = '2099-01-01 00:00:00' } }
    elseif compact:find('FROM mdt_reports', 1, true) then
        check(not emsCaller(), 'EMS queried global report statistics')
        result = kind == 'scalar' and 777 or { { totalThisWeek = 701, totalLastWeek = 700 } }
    elseif compact:find('FROM mdt_bolos', 1, true) then
        check(not emsCaller(), 'EMS queried private BOLOs')
        result = { { id = 71, reportId = 70, subject_name = 'PRIVATE BOLO', type = 'person', status = 'active' } }
    elseif compact:find('FROM mdt_cases', 1, true) then
        check(not emsCaller(), 'EMS queried police case data')
        result = { { id = 72, title = 'PRIVATE CASE', status = 'open' } }
    elseif compact:find('FROM mdt_arrests', 1, true) then
        check(not emsCaller(), 'EMS queried global arrests')
        result = 777
    elseif compact:find('FROM mdt_impound', 1, true) then
        check(not emsCaller(), 'EMS queried impound operations')
        result = kind == 'scalar' and 777 or { { fee = 50, fee_paid = 0, time = os.time() - 86400 } }
    else
        databaseFailure('Unexpected database read: ' .. compact)
    end
    if afterRead then
        local hook = afterRead
        afterRead = nil
        hook(compact)
    end
    return result
end

local ps = {
    getJobData = function(source) return player(source).job end,
    getJobName = function(source) return player(source).job.name end,
    getJobType = function(source) return player(source).job.type end,
    getJobDuty = function(source) return player(source).job.onduty end,
    getIdentifier = function(source) return player(source).citizenid end,
    isBoss = function(source) return player(source).job.isboss == true end,
    getJobGradeName = function(source) return player(source).job.grade.name end,
    getJobGradePay = function(source) return player(source).job.payment end,
    getMetadata = function() return nil end,
    getPlayerName = function(source) return 'Employee ' .. source end,
    getPlayerNameByIdentifier = function(cid) return 'Name ' .. cid end,
    getSharedJobData = function(jobName) return jobs[jobName] end,
    getJobTypeCount = function(jobType)
        countRequests[#countRequests + 1] = jobType
        return unitCounts[jobType] or 0
    end,
    registerCallback = function(name, callback) callbacks[name] = callback end,
    warn = function() end, debug = function() end, error = function() end,
}
local exports = setmetatable({ ps_lib = { init = function() return ps end },
    ['ps-dispatch'] = { GetDispatchCalls = function() return copy(dispatchCalls) end },
}, { __call = function(_, name, callback) exported[name] = callback end })

local env = setmetatable({
    exports = exports,
    GetCurrentResourceName = function() return 'ps-mdt' end,
    GetGameTimer = function() return timer end,
    GetResourceState = function(resource) return resource == 'ps-dispatch' and 'started' or 'missing' end,
    GetPlayers = function()
        local sources = {}
        for source in pairs(players) do sources[#sources + 1] = tostring(source) end
        return sources
    end,
    TriggerClientEvent = function(name, target, payload)
        sent[#sent + 1] = { name = name, target = target, payload = copy(payload) }
    end,
    RegisterNetEvent = function(name, callback) events[name] = callback end,
    AddEventHandler = function(name, callback) events[name] = callback end,
    CreateThread = function(callback) scheduled[#scheduled + 1] = callback end,
    json = {
        decode = function(token) assert(jsonFixtures[token], 'Unknown JSON fixture'); return copy(jsonFixtures[token]) end,
        encode = function(value)
            serial = serial + 1
            local token = 'json-' .. serial
            jsonFixtures[token] = copy(value)
            return token
        end,
    },
    MySQL = {
        single = { await = function(query, args) return readDatabase('single', query, args) end },
        query = { await = function(query, args) return readDatabase('query', query, args) end },
        scalar = { await = function(query, args) return readDatabase('scalar', query, args) end },
        insert = { await = forbidWrite }, update = { await = forbidWrite }, transaction = { await = forbidWrite },
    },
    Cache = {
        getOrSet = function(key, _, callback)
            cacheRequests[#cacheRequests + 1] = key
            if cache[key] == nil then cache[key] = callback() end
            return cache[key]
        end,
        invalidate = function(key) cache[key] = nil end,
    },
}, { __index = _G })

for _, path in ipairs({ 'config.lua', 'server/auth.lua', 'server/functions.lua',
    'server/backend/warrants.lua', 'server/backend/dashboard.lua' }) do
    assert(loadfile(path, 't', env))()
end
-- functions.lua exposes IsEmsJob as a global, not necessarily an export.
exported.IsEmsJob = env.IsEmsJob
local originalMedicalType = env.Config.MedicalJobType

local fullEmsPermissions = { 'reports_view', 'reports_create', 'training_view', 'bulletin_view' }
local function reset()
    players, roles, reads, failures, cache, sent = {}, {}, {}, {}, {}, {}
    afterRead, afterRoleRead, currentSource = nil, nil, nil
    dispatchCalls = {}
    unitCounts, countRequests, cacheRequests = { ems = 12, leo = 41 }, {}, {}
    env.Config.MedicalJobType = originalMedicalType
    env.Config.Dispatch.FilterByJob = true
    timer = timer + 3000
end

local function invoke(name, source, ...)
    currentSource = source
    local callback = assert(callbacks['ps-mdt:server:' .. name], 'Callback missing: ' .. name)
    local result = callback(source, ...)
    currentSource = nil
    return result
end

local function ems(source, jobName, boss, permissions)
    local data = identity(source or 1, jobName or 'lsfd', 'ems', 1, boss)
    grant(data.job.name, 1, permissions or fullEmsPermissions)
    return data
end

local function noPoliceData(data)
    equal(data.dashboardDomain, 'ems')
    equal(#data.activeWarrants, 0, 'No warrants')
    equal(#data.activeBolos, 0, 'No BOLOs')
    equal(#data.openCases, 0, 'No police investigations')
    equal(data.usageMetrics.totals.arrests, 0)
    equal(data.usageMetrics.totals.activeWarrants, 0)
    equal(data.usageMetrics.windows.arrestsLast7, 0)
    equal(data.usageMetrics.windows.arrestsLast30, 0)
    for key, value in pairs(data.usageMetrics.impound) do equal(value, 0, 'No impound ' .. key) end
end

local function test(name, callback)
    reset()
    local ok, err = pcall(function()
        callback()
        equal(#failures, 0, 'Strict SQL contract failed: ' .. table.concat(failures, '; '))
        equal(writes, 0, 'Database writes must never execute')
    end)
    if ok then passed = passed + 1; print('PASS ' .. name)
    else failed = failed + 1; print('FAIL ' .. name .. ': ' .. tostring(err)) end
end

test('all configured fire and hospital jobs, bosses and employees, receive only EMS dashboard data', function()
    for index, jobName in ipairs(env.Config.MedicalJobs) do
        for _, boss in ipairs({ false, true }) do
            ems(index, jobName, boss)
            noPoliceData(invoke('getDashboard', index))
            local access = env.GetMdtAccess(index)
            equal(access.interfaceId, contains(env.Config.MdtAccess.FireJobs, jobName) and 'safr' or 'sams', jobName)
        end
    end
    equal(#cacheRequests, 0, 'EMS must not consume global police dashboard caches')
end)

test('EMS reports preserve public, domain, exact-job and citizen ACL grants with distinct counts', function()
    ems(1)
    equal(ids(invoke('getRecentReports', 1)), '1,2,3,4,8,9')
    local data = invoke('getDashboard', 1)
    equal(data.reportStatistics.totalThisWeek, 4)
    equal(data.reportStatistics.changeFromLastWeek, 3)
    equal(data.usageMetrics.totals.reports, 6)
    equal(data.usageMetrics.windows.reportsLast7, 4)
    equal(data.usageMetrics.windows.reportsLast30, 5)
    equal(data.jobData.rank, players[1].job.grade.name)
    equal(data.jobData.payRate, '$' .. players[1].job.payment .. '/hr')
    equal(data.timeStatistics[#data.timeStatistics].hours, 2)
    equal(data.activeUnits.count, 12)
    expect(not contains(countRequests, 'leo'), 'EMS personnel count must not use police domain')
end)

test('separate employees never inherit another job or citizen report grants', function()
    ems(1, 'lsfd')
    ems(2, 'pillboxmed')
    equal(invoke('getUsageMetrics', 1).totals.reports, 6)
    equal(ids(invoke('getRecentReports', 2)), '1,2,6,8,9')
    equal(invoke('getUsageMetrics', 2).totals.reports, 5)
    equal(invoke('getReportStatistics', 2).totalThisWeek, 2)
    equal(invoke('getReportStatistics', 1).totalThisWeek, 4)
end)

test('police global cache priming cannot contaminate an EMS response', function()
    identity(10, 'lspd', 'leo', 1, true)
    local leo = invoke('getDashboard', 10)
    equal(leo.usageMetrics.totals.reports, 777)
    equal(leo.reportStatistics.totalThisWeek, 701)
    equal(leo.activeUnits.count, 41)
    ems(1)
    local data = invoke('getDashboard', 1)
    noPoliceData(data)
    equal(data.usageMetrics.totals.reports, 6)
    equal(data.reportStatistics.totalThisWeek, 4)
    equal(data.activeUnits.count, 12)
end)

test('EMS without report, bulletin or training permissions receives no protected optional sections', function()
    ems(1, 'lsfd', false, {})
    local data = invoke('getDashboard', 1)
    noPoliceData(data)
    equal(data.usageMetrics.totals.reports, 0)
    equal(data.reportStatistics.totalThisWeek, 0)
    equal(#data.bulletins, 0)
    equal(#data.upcomingHearings, 0)
    equal(#invoke('getRecentReports', 1), 0)
    equal(invoke('getUsageMetrics', 1).totals.reports, 0)
    equal(invoke('getReportStatistics', 1).totalThisWeek, 0)
    for _, read in ipairs(reads) do
        expect(not read.query:find('FROM mdt_reports', 1, true), 'Denied report section must not query reports')
        expect(not read.query:find('FROM mdt_bulletin', 1, true), 'Denied bulletin section must not query posts')
        expect(not read.query:find('FROM mdt_court_hearings', 1, true), 'Denied calendar section must not query calendar')
    end
    equal(data.activeUnits.count, 12)
    equal(data.timeStatistics[#data.timeStatistics].hours, 2)
end)

for _, permission in ipairs({ 'reports_view', 'reports_create' }) do
    test('existing ' .. permission .. ' independently permits authorized EMS report reads', function()
        ems(1, 'lsfd', false, { permission })
        equal(ids(invoke('getRecentReports', 1)), '1,2,3,4,8,9')
        equal(invoke('getUsageMetrics', 1).totals.reports, 6)
    end)
end

test('EMS calendar keeps authorized EMS events and excludes police/court rows', function()
    ems(1)
    equal(ids(invoke('getDashboard', 1).upcomingHearings), '21,22,23')
end)

test('EMS bulletins use only own-job posts while legacy management IDs stay inaccessible', function()
    ems(1)
    local data = invoke('getDashboard', 1)
    equal(ids(data.bulletins), '31')
    equal(data.bulletins[1].content, 'Own fire bulletin')
    local before = #reads
    equal(#invoke('getBulletins', 1), 0)
    for index = before + 1, #reads do
        expect(not reads[index].query:find('FROM mdt_bulletin', 1, true), 'Legacy EMS bulletins must not query either ID namespace')
    end
end)

test('standalone EMS BOLO and warrant endpoints and shared helper cannot bypass the aggregate policy', function()
    ems(1, 'lsfd', true)
    equal(#invoke('getActiveBolos', 1), 0)
    equal(#invoke('getActiveWarrants', 1), 0)
    currentSource = 1
    equal(#env.GetActiveWarrantsData(1), 0)
    currentSource = nil
    for _, read in ipairs(reads) do
        expect(not read.query:find('FROM mdt_bolos', 1, true))
        expect(not read.query:find('FROM mdt_reports_warrants', 1, true))
    end
end)

local function seedDispatches()
    local unit = {
        citizenid = 'PUBLIC-UNIT-ID',
        charinfo = { firstname = 'Pat', lastname = 'Officer', birthdate = 'PRIVATE DOB', phone = 'PRIVATE PHONE' },
        job = { name = 'lspd', label = 'Los Santos Police', type = 'leo', payment = 999, isboss = true },
        metadata = { callsign = 'P-12', private = 'PRIVATE METADATA' },
    }
    local audiences = {
        { 'ems' }, { 'lsfd' }, { 'pillboxmed' }, { 'leo' }, { 'leo', 'ems' },
        {}, false, 'ems', { ems = true }, { ems = 0 }, { ems = false },
        { ems = 'invalid' }, { { job = 'ems' } }, 123, { 'unknown' },
    }
    dispatchCalls = {}
    for index, audience in ipairs(audiences) do
        dispatchCalls[#dispatchCalls + 1] = {
            id = index, jobs = audience, message = 'Dispatch ' .. index, code = '10-52',
            coords = { x = 123, y = 456, z = 78 }, units = { copy(unit) }, time = 100,
        }
    end
    dispatchCalls[#dispatchCalls + 1] = { id = 16, message = 'Missing audience', units = {} }
end

for _, filtering in ipairs({ true, false }) do
    test('EMS dispatch requires explicit recipients even when global filtering is ' .. tostring(filtering), function()
        ems(1)
        env.Config.Dispatch.FilterByJob = filtering
        seedDispatches()
        equal(ids(invoke('getRecentDispatches', 1)), '1,10,2,5,8,9')
        equal(ids(invoke('getDashboard', 1).recentDispatches), '1,10,2,5,8,9')
    end)
end

test('authorized shared dispatch retains coordination fields without private police personnel details', function()
    ems(1)
    seedDispatches()
    local calls = invoke('getRecentDispatches', 1)
    local shared
    for _, call in ipairs(calls) do if call.id == 5 then shared = call end end
    expect(shared, 'Shared EMS/LEO call missing')
    equal(shared.coords.x, 123)
    equal(shared.message, 'Dispatch 5')
    local unit = shared.units[1]
    equal(unit.citizenid, 'PUBLIC-UNIT-ID')
    equal(unit.charinfo.firstname, 'Pat')
    equal(unit.charinfo.lastname, 'Officer')
    equal(unit.charinfo.birthdate, nil)
    equal(unit.charinfo.phone, nil)
    equal(unit.job.name, 'lspd')
    equal(unit.job.label, 'Los Santos Police')
    equal(unit.job.type, 'leo')
    equal(unit.job.payment, nil)
    equal(unit.job.isboss, nil)
    equal(unit.metadata.callsign, 'P-12')
    equal(unit.metadata.private, nil)
end)

test('shared dispatch cache never leaks private unit shape from a preceding LEO request', function()
    identity(10, 'lspd', 'leo', 1, true)
    ems(1)
    seedDispatches()
    env.Config.Dispatch.FilterByJob = false
    equal(#invoke('getRecentDispatches', 10), 16)
    local data = invoke('getRecentDispatches', 1)
    equal(ids(data), '1,10,2,5,8,9')
    equal(data[1].units[1].charinfo.phone, nil)
    equal(invoke('getRecentDispatches', 10)[1].units[1].charinfo.phone, 'PRIVATE PHONE',
        'EMS projection must not mutate existing LEO response/cache')
end)

test('configured medical job types and name-based EMS routing remain authorized and scoped', function()
    ems(1)
    players[1].job.type = 'custom_hospital'
    env.Config.MedicalJobType = 'custom_hospital'
    unitCounts.custom_hospital = 15
    dispatchCalls = {
        { id = 1, jobs = { 'custom_hospital' } }, { id = 2, jobs = { 'ems' } },
        { id = 3, jobs = { 'leo' } },
    }
    local data = invoke('getDashboard', 1)
    noPoliceData(data)
    equal(data.activeUnits.count, 15)
    equal(ids(data.recentDispatches), '1,2')
    -- Named medical jobs must still resolve to EMS even with a legacy core type.
    players[1].job.type = 'legacy_hospital'
    noPoliceData(invoke('getDashboard', 1))
end)

for _, domain in ipairs({ 'leo', 'doj' }) do
    test(domain .. ' legacy aggregate, standalone reads and report contracts remain functional', function()
        local jobName = domain == 'leo' and 'lspd' or 'sadoj'
        identity(10, jobName, domain, domain == 'doj' and 8 or 1, true)
        local data = invoke('getDashboard', 10)
        equal(data.dashboardDomain, nil)
        equal(data.activeWarrants[1].reportid, 70)
        equal(data.activeWarrants[1].name, 'Warrant Subject')
        equal(data.openCases[1].id, 72)
        expect(#data.activeBolos == 1)
        equal(data.bulletins[1].id, 99)
        equal(ids(data.upcomingHearings), '25')
        equal(data.reportStatistics.totalThisWeek, 701)
        equal(data.usageMetrics.totals.arrests, 777)
        equal(data.activeUnits.count, 41)
        equal(#invoke('getActiveBolos', 10), 1)
        equal(invoke('getActiveWarrants', 10)[1].reportid, 70)
        equal(invoke('getBulletins', 10)[1].id, 99)
        local recent = invoke('getRecentReports', 10)
        expect(#recent > 0)
        if domain == 'doj' then expect(not contains({ ids(recent) }, '2'), 'DOJ remains on legacy report ACL') end
    end)
end

test('LEO dispatch keeps existing FilterByJob behavior', function()
    identity(10, 'lspd', 'leo', 1, true)
    dispatchCalls = {
        { id = 1, jobs = { 'leo' } }, { id = 2, jobs = { 'ems' } },
        { id = 3 }, { id = 4, jobs = {} },
    }
    equal(ids(invoke('getRecentDispatches', 10)), '1,3,4')
    env.Config.Dispatch.FilterByJob = false
    equal(ids(invoke('getRecentDispatches', 10)), '1,2,3,4')
end)

test('government, civilian, offline and off-duty EMS cannot retrieve operational dashboard data', function()
    identity(20, 'sagov', 'gov', 9, true)
    identity(21, 'unemployed', 'civ', 0, false)
    ems(1)
    players[1].job.onduty = false
    for _, source in ipairs({ 20, 21, 999, 1 }) do
        for _, name in ipairs({ 'getDashboard', 'getRecentReports', 'getActiveBolos', 'getActiveWarrants',
            'getBulletins', 'getUsageMetrics', 'getJobData', 'getTimeStatistics', 'getRecentDispatches' }) do
            equal(next(invoke(name, source)), nil, name .. ' source ' .. source)
        end
        equal(invoke('getActiveUnits', source).count, 0)
    end
    for _, read in ipairs(reads) do
        expect(read.query:find('FROM mdt_permission_roles', 1, true),
            'Denied callers may query role grants, but must not query operational SQL')
    end
end)

for _, change in ipairs({ 'job', 'grade', 'citizenid', 'duty', 'boss', 'permissions' }) do
    test('EMS ' .. change .. ' change during SQL discards the original dashboard response', function()
        ems(1)
        afterRead = function()
            if change == 'job' then players[1].job.name = 'pillboxmed'
            elseif change == 'grade' then players[1].job.grade.level = 2
            elseif change == 'citizenid' then players[1].citizenid = 'NEW-CID'
            elseif change == 'duty' then players[1].job.onduty = false
            elseif change == 'boss' then players[1].job.isboss = true
            else grant('lsfd', 1, {}) end
        end
        -- On an aggregate, later sections may read after the framework changes;
        -- use a single SQL endpoint to isolate final authorization correctly.
        equal(next(invoke('getReportStatistics', 1)), nil)
    end)
end

test('EMS identity changes during permission lookup fail closed before dashboard SQL', function()
    ems(1)
    afterRoleRead = function() players[1].job.name = 'pillboxmed' end
    equal(next(invoke('getDashboard', 1)), nil)
    for _, read in ipairs(reads) do
        expect(read.query:find('FROM mdt_permission_roles', 1, true), 'Changed source must not reach dashboard SQL')
    end
end)

test('LEO response cannot survive a transfer into EMS while its query yields', function()
    identity(10, 'lspd', 'leo', 1, true)
    afterRead = function() identity(10, 'lsfd', 'ems', 1, true) end
    equal(next(invoke('getReportStatistics', 10)), nil)
end)

test('warrant reads recheck source job and citizen identity after SQL', function()
    identity(10, 'lspd', 'leo', 1, true)
    afterRead = function() identity(10, 'lsfd', 'ems', 1, true) end
    equal(#invoke('getActiveWarrants', 10), 0)
    identity(10, 'lspd', 'leo', 1, true)
    afterRead = function() players[10].citizenid = 'NEW-CID' end
    equal(#invoke('getActiveWarrants', 10), 0)
end)

test('warrant broadcasts target only explicit authorized LEO/DOJ sources and retain legacy payload', function()
    identity(10, 'lspd', 'leo', 1, true)
    identity(11, 'sadoj', 'doj', 8, true)
    identity(12, 'sadle', 'leo', 11, true)
    ems(1, 'lsfd', true)
    ems(2, 'pillboxmed', false)
    identity(20, 'sagov', 'gov', 9, true)
    identity(21, 'unemployed', 'civ', 0, false)
    env.BroadcastActiveWarrants()
    equal(#sent, 3)
    local targets = {}
    for _, event in ipairs(sent) do
        expect(event.target > 0, 'Never broadcast sensitive records to -1')
        targets[#targets + 1] = event.target
        equal(event.name, 'ps-mdt:client:updateActiveWarrants')
        equal(event.payload[1].reportid, 70)
        equal(event.payload[1].name, 'Warrant Subject')
    end
    table.sort(targets)
    equal(table.concat(targets, ','), '10,11,12')
    local warrantReads = 0
    for _, read in ipairs(reads) do if read.query:find('FROM mdt_reports_warrants', 1, true) then warrantReads = warrantReads + 1 end end
    equal(warrantReads, 1, 'Broadcast should read its authorized server payload once')
end)

print(('EMS dashboard regressions: %d passed, %d failed (%d assertions).'):format(passed, failed, assertions))
if failed > 0 then os.exit(1) end
