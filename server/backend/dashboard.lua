local resourceName = tostring(GetCurrentResourceName())

local function getEffectiveJobType(src)
    local jobType = ps.getJobType(src)
    local jobName = ps.getJobName(src)
    if Config.DojJobs then
        for _, name in ipairs(Config.DojJobs) do
            if name == jobName then return 'doj' end
        end
    end
    if Config.DojJobType and jobType == Config.DojJobType then return 'doj' end
    -- Normalise to a stable MDT domain (name + type aware) instead of returning
    -- the raw core job type, so EMS is detected even when its type isn't "ems".
    if IsEmsJob(jobName, jobType) then return 'ems' end
    if jobType == 'leo' then return 'leo' end
    if jobType == 'fire' then return 'fire' end
    return nil
end

-- A dashboard request may yield while reading permissions or SQL. Bind every
-- read to its original character/job and discard results after an identity or
-- permission change, including a police-to-EMS transfer during the request.
local function dashboardIdentity(src)
    local job = ps.getJobData(src)
    local grade = job and job.grade
    local isBoss = job and (job.isboss == true or job.isBoss == true)
        or false
    if type(grade) == 'table' then
        isBoss = isBoss or grade.isboss == true or grade.isBoss == true or grade.boss == true
    end
    if ps.isBoss then isBoss = isBoss or ps.isBoss(src) == true end
    if type(grade) == 'table' then grade = grade.level or grade.grade or grade.rank or grade.value or grade.id end
    local onDuty
    if ps.getJobDuty then
        onDuty = ps.getJobDuty(src) == true
    else
        onDuty = job and job.onduty == true
    end
    return {
        citizenid = ps.getIdentifier(src), job = ps.getJobName(src),
        coreType = ps.getJobType(src), grade = tonumber(grade),
        onDuty = onDuty, isBoss = isBoss,
    }
end

local function sameDashboardIdentity(a, b)
    return a and b and a.citizenid == b.citizenid and a.job == b.job
        and a.coreType == b.coreType and a.grade == b.grade and a.onDuty == b.onDuty
        and a.isBoss == b.isBoss
end

local function dashboardSnapshot(src)
    local ok, snapshot = pcall(function()
        if not CheckAuth(src) then return nil end
        local before = dashboardIdentity(src)
        if type(before.citizenid) ~= 'string' or not before.citizenid:find('%S')
            or #before.citizenid > 64 or before.citizenid:find('%z')
            or type(before.job) ~= 'string' or not before.job:find('%S')
            or #before.job > 64 or before.job:find('%z') then return nil end
        local access = GetMdtAccess(src)
        local current = dashboardIdentity(src)
        if not sameDashboardIdentity(before, current) or type(access) ~= 'table'
            or access.authorized ~= true or access.isCivilian == true then return nil end
        current.jobType = getEffectiveJobType(src)
        if current.jobType == nil or access.jobType ~= current.jobType then return nil end
        if current.jobType == 'ems' and (access.authorized ~= true or access.jobType ~= 'ems') then return nil end
        if type(access.interfaceId) ~= 'string' or not access.interfaceId:find('%S')
            or #access.interfaceId > 64 or access.interfaceId:find('%z') then return nil end
        current.interfaceId = access.interfaceId
        current.permissions, current.permissionKeys = {}, {}
        if type(access.permissions) ~= 'table' then return nil end
        for _, permission in ipairs(access.permissions) do
            if type(permission) == 'string' and #permission <= 100
                and permission:find('%S') and not permission:find('%z')
                and not current.permissions[permission] then
                current.permissions[permission] = true
                current.permissionKeys[#current.permissionKeys + 1] = permission
            end
        end
        table.sort(current.permissionKeys)
        current.permissionKey = table.concat(current.permissionKeys, '\0')
        return current
    end)
    return ok and snapshot or nil
end

local function sameDashboardSnapshot(a, b)
    return sameDashboardIdentity(a, b) and a.jobType == b.jobType
        and a.interfaceId == b.interfaceId and a.permissionKey == b.permissionKey
end

local function registerDashboardRead(name, reader, empty)
    ps.registerCallback(resourceName .. ':server:' .. name, function(source, ...)
        local snapshot = dashboardSnapshot(source)
        if not snapshot then return empty and empty() or {} end
        local ok, result = pcall(reader, source, snapshot, ...)
        if not ok or not sameDashboardSnapshot(snapshot, dashboardSnapshot(source))
            or not CheckAuth(source) then
            return empty and empty() or {}
        end
        return result
    end)
end

local function canReadEmsReports(snapshot)
    return snapshot.permissions.reports_view == true or snapshot.permissions.reports_create == true
end

-- Same unrestricted-or-explicit viewer ACL used by existing report reads.
-- EXISTS avoids counting a report more than once when several grants match.
local EMS_REPORT_ACCESS = [[
    (NOT EXISTS (SELECT 1 FROM mdt_reports_restrictions restricted WHERE restricted.reportid = mr.id)
     OR EXISTS (
        SELECT 1 FROM mdt_reports_restrictions granted
        WHERE granted.reportid = mr.id AND (
            (granted.type = 'citizenid' AND granted.identifier = ?)
            OR (granted.type = 'job' AND granted.identifier = ?)
            OR (granted.type = 'jobtype' AND granted.identifier = ?)
        )
     ))
]]

local function emsReportParameters(snapshot)
    return { snapshot.citizenid, snapshot.job, snapshot.jobType }
end

local function computeJobData(src)
    return {
        rank    = ps.getJobGradeName(src) or 'Officer',
        payRate = '$' .. (ps.getJobGradePay(src) or 300) .. '/hr',
    }
end

registerDashboardRead('getJobData', function(src)
    return computeJobData(src)
end)

local function computeReportStatistics(src, snapshot)
    if not snapshot or not snapshot.permissions.reports_view then
        return { totalThisWeek = 0, changeFromLastWeek = 0 }
    end
    if snapshot.jobType == 'ems' then
        if not canReadEmsReports(snapshot) then return { totalThisWeek = 0, changeFromLastWeek = 0 } end
        local ok, response = pcall(MySQL.query.await, ([[
            SELECT
                COUNT(DISTINCT CASE WHEN mr.datecreated >= NOW() - INTERVAL 1 WEEK THEN mr.id END) AS totalThisWeek,
                COUNT(DISTINCT CASE WHEN mr.datecreated >= NOW() - INTERVAL 2 WEEK AND mr.datecreated < NOW() - INTERVAL 1 WEEK THEN mr.id END) AS totalLastWeek
            FROM mdt_reports mr WHERE %s
        ]]):format(EMS_REPORT_ACCESS), emsReportParameters(snapshot))
        if not ok or not CheckAuth(src) or not CheckPermission(src, 'reports_view') then
            return { totalThisWeek = 0, changeFromLastWeek = 0 }
        end
        local row = type(response) == 'table' and type(response[1]) == 'table'
            and response[1] or {}
        return {
            totalThisWeek = tonumber(row.totalThisWeek) or 0,
            changeFromLastWeek = (tonumber(row.totalThisWeek) or 0) - (tonumber(row.totalLastWeek) or 0),
        }
    end
    return Cache.getOrSet('dashboard:reportStats:' .. tostring(snapshot.job) .. ':' .. tostring(snapshot.jobType)
        .. ':' .. tostring(snapshot.permissionKey),
        Config.CacheTTL and Config.CacheTTL.ReportStats or 30, function()
        local ok, response = pcall(MySQL.query.await, [[
            SELECT
                COUNT(CASE WHEN datecreated >= NOW() - INTERVAL 1 WEEK THEN 1 END) AS totalThisWeek,
                COUNT(CASE WHEN datecreated >= NOW() - INTERVAL 2 WEEK AND datecreated < NOW() - INTERVAL 1 WEEK THEN 1 END) AS totalLastWeek
            FROM mdt_reports mr
            WHERE NOT EXISTS (SELECT 1 FROM mdt_reports_restrictions own
                WHERE own.reportid = mr.id AND own.type = 'owner')
              OR EXISTS (SELECT 1 FROM mdt_reports_restrictions own
                WHERE own.reportid = mr.id AND own.type = 'owner' AND own.identifier = ?)
        ]], { snapshot.job })
        if not ok or not CheckAuth(src) or not CheckPermission(src, 'reports_view') then
            return { totalThisWeek = 0, changeFromLastWeek = 0 }
        end

        local row = type(response) == 'table' and type(response[1]) == 'table'
            and response[1] or { totalThisWeek = 0, totalLastWeek = 0 }
        return {
            totalThisWeek      = tonumber(row.totalThisWeek) or 0,
            changeFromLastWeek = (tonumber(row.totalThisWeek) or 0) - (tonumber(row.totalLastWeek) or 0),
        }
    end)
end

registerDashboardRead('getReportStatistics', function(src, snapshot)
    if not snapshot.permissions.reports_view then
        return { totalThisWeek = 0, changeFromLastWeek = 0 }
    end
    return computeReportStatistics(src, snapshot)
end)

local function computeTimeStatistics(src)
    local citizenid = ps.getIdentifier(src)
    if type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then return {} end

    local ok, rows = pcall(MySQL.query.await, [[
        SELECT DATE(login_at) AS day,
               SUM(TIMESTAMPDIFF(SECOND, login_at, COALESCE(logout_at, NOW()))) AS seconds
        FROM mdt_profile_sessions
        WHERE citizenid = ?
          AND login_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
        GROUP BY DATE(login_at)
        ORDER BY day ASC
    ]], { citizenid })
    if not ok then return {} end

    local secondsByDay = {}
    if type(rows) ~= 'table' or #rows > 7 then return {} end
    for _, row in ipairs(rows) do
        if type(row) ~= 'table' or row.day == nil then return {} end
        local seconds = tonumber(row.seconds)
        if seconds and seconds == seconds and seconds >= 0
            and seconds ~= math.huge then
            secondsByDay[tostring(row.day)] = math.min(seconds, 86400 * 7)
        end
    end

    local result = {}
    for i = 6, 0, -1 do
        local dayTs  = os.time() - (i * 24 * 60 * 60)
        local dayKey = os.date('%Y-%m-%d', dayTs)
        local label  = os.date('%a', dayTs)
        result[#result + 1] = {
            day   = label,
            hours = math.floor(((secondsByDay[dayKey] or 0) / 3600) * 10) / 10,
        }
    end
    return result
end

registerDashboardRead('getTimeStatistics', function(src)
    return computeTimeStatistics(src)
end)

-- Active warrants handled in server/backend/warrants.lua

local function computeBulletins()
    local ok, rows = pcall(MySQL.query.await,
        'SELECT id, content FROM mdt_bulletins ORDER BY id DESC LIMIT 100')
    if not ok then return {} end
    if type(rows) ~= 'table' then return {} end
    if #rows == 0 then return { { content = 'No bulletins found..' } } end
    for _, row in ipairs(rows) do
        if type(row) ~= 'table' or not tonumber(row.id)
            or type(row.content) ~= 'string' then return {} end
    end
    return rows
end

local function computeEmsBulletins(snapshot)
    if not snapshot.permissions.bulletin_view then return {} end
    return MySQL.query.await([[
        SELECT id, content FROM mdt_bulletin_posts
        WHERE job = ?
        ORDER BY pinned DESC, FIELD(priority, 'urgent', 'high', 'normal', 'low'), created_at DESC
    ]], { snapshot.job }) or {}
end

registerDashboardRead('getBulletins', function(src, snapshot)
    if not snapshot.permissions.bulletin_view then return {} end
    -- This legacy management endpoint has no department column. Never mix
    -- exact-job board-post IDs with legacy global create/delete operations.
    if snapshot.jobType ~= 'leo' and snapshot.jobType ~= 'doj' then return {} end
    if not snapshot.permissions.bulletin_view then return {} end
    return computeBulletins()
end)

ps.registerCallback(resourceName .. ':server:createBulletin', function(source, payload)
    local src = source
    assert(src, 'Player ID cannot be nil')
    local snapshot = dashboardSnapshot(src)
    if not snapshot or (snapshot.jobType ~= 'leo' and snapshot.jobType ~= 'doj')
        or not CheckAuth(src) or not CheckPermission(src, 'bulletin_create') then
        return { success = false, message = 'Unauthorized' }
    end

    if type(payload) ~= 'table' then return { success = false, message = 'Invalid bulletin' } end
    local content = payload.content
    if type(content) ~= 'string' or not content:find('%S')
        or #content > 10000 or content:find('%z') then
        return { success = false, message = 'Bulletin content is required' }
    end

    if not sameDashboardSnapshot(snapshot, dashboardSnapshot(src))
        or not CheckPermission(src, 'bulletin_create') then
        return { success = false, message = 'Authorization changed' }
    end
    local ok, inserted = pcall(MySQL.insert.await,
        'INSERT INTO mdt_bulletins (content) VALUES (?)', { content })
    if not ok then return { success = false, message = 'Failed to create bulletin' } end
    if type(inserted) ~= 'number' or inserted ~= inserted
        or inserted == math.huge or inserted == -math.huge or inserted <= 0 then
        return { success = false, message = 'Failed to create bulletin' }
    end

    Cache.invalidate('dashboard:bulletins')
    if ps.auditLog then
        ps.auditLog(src, 'bulletin_created', 'bulletin', inserted, {job=snapshot.job})
    end
    return { success = true, id = inserted }
end)

ps.registerCallback(resourceName .. ':server:deleteBulletin', function(source, payload)
    local src = source
    assert(src, 'Player ID cannot be nil')
    local snapshot = dashboardSnapshot(src)
    if not snapshot or (snapshot.jobType ~= 'leo' and snapshot.jobType ~= 'doj')
        or not CheckAuth(src) or not CheckPermission(src, 'bulletin_delete') then
        return { success = false, message = 'Unauthorized' }
    end

    if type(payload) ~= 'table' then return { success = false, message = 'Invalid bulletin' } end
    local id = tonumber(payload.id)
    if not id or id ~= id or id == math.huge or id == -math.huge
        or id <= 0 or id % 1 ~= 0 then
        return { success = false, message = 'Invalid bulletin ID' }
    end

    if not sameDashboardSnapshot(snapshot, dashboardSnapshot(src))
        or not CheckPermission(src, 'bulletin_delete') then
        return { success = false, message = 'Authorization changed' }
    end
    local ok, deleted = pcall(MySQL.update.await,
        'DELETE FROM mdt_bulletins WHERE id = ?', { id })
    if not ok then return { success = false, message = 'Failed to delete bulletin' } end
    if type(deleted) ~= 'number' or deleted ~= deleted
        or deleted == math.huge or deleted == -math.huge or deleted <= 0 then
        return { success = false, message = 'Bulletin not found' }
    end
    Cache.invalidate('dashboard:bulletins')
    if ps.auditLog then
        ps.auditLog(src, 'bulletin_deleted', 'bulletin', id, {job=snapshot.job})
    end
    return { success = true }
end)

registerDashboardRead('getRecentReports', function(src, snapshot, page, limit)
    if not snapshot.permissions.reports_view then return {} end
    local pageNumber = tonumber(page) or 1
    if pageNumber ~= pageNumber or pageNumber == math.huge or pageNumber == -math.huge then pageNumber = 1 end
    pageNumber = math.floor(math.min(10000, math.max(1, pageNumber)))
    local pageSize = tonumber(limit) or 10
    if pageSize ~= pageSize or pageSize == math.huge or pageSize == -math.huge then pageSize = 10 end
    pageSize = math.floor(math.min(50, math.max(1, pageSize)))

    local identifier = snapshot.citizenid
    local job        = snapshot.job
    local jobType    = snapshot.jobType
    local offset     = (pageNumber - 1) * pageSize

    if jobType == 'ems' then
        if not canReadEmsReports(snapshot) then return {} end
        local params = emsReportParameters(snapshot)
        params[#params + 1] = pageSize
        params[#params + 1] = offset
        local ok, rows = pcall(MySQL.query.await, ([[
            SELECT mr.id, mr.title, mr.type, mr.contentplaintext, mr.author, mr.authorplaintext, mr.datecreated, mr.dateupdated
            FROM mdt_reports mr WHERE %s
            ORDER BY mr.datecreated DESC LIMIT ? OFFSET ?
        ]]):format(EMS_REPORT_ACCESS), params)
        if not ok or type(rows) ~= 'table' then return {} end
        for _, row in ipairs(rows) do
            if type(row) ~= 'table' or not tonumber(row.id) then return {} end
        end
        if not CheckAuth(src) or not CheckPermission(src, 'reports_view')
            or not sameDashboardSnapshot(snapshot, dashboardSnapshot(src)) then return {} end
        return rows
    end

    local ok, rows = pcall(MySQL.query.await, [[
        SELECT mr.id, mr.title, mr.type, mr.contentplaintext, mr.author, mr.authorplaintext, mr.datecreated, mr.dateupdated
        FROM mdt_reports mr
        LEFT JOIN mdt_reports_restrictions mrr ON mr.id = mrr.reportid
        WHERE (
            (? = 'doj' AND NOT EXISTS(
                SELECT 1 FROM mdt_reports_restrictions mrr_ems
                WHERE mrr_ems.reportid = mr.id AND mrr_ems.type = 'jobtype' AND mrr_ems.identifier IN ('ems', 'fire')
            ))
            OR (mrr.reportid IS NULL AND (? = 'leo' OR ? = 'ems'))
            OR (mrr.type = 'citizenid' AND mrr.identifier = ?)
            OR (mrr.type = 'job'       AND mrr.identifier = ?)
            OR (mrr.type = 'jobtype'   AND mrr.identifier = ?)
        )
        AND (NOT EXISTS (SELECT 1 FROM mdt_reports_restrictions own
            WHERE own.reportid = mr.id AND own.type = 'owner')
          OR EXISTS (SELECT 1 FROM mdt_reports_restrictions own
            WHERE own.reportid = mr.id AND own.type = 'owner' AND own.identifier = ?)
          OR EXISTS (SELECT 1 FROM mdt_reports_restrictions grant_scope
            WHERE grant_scope.reportid = mr.id
              AND ((grant_scope.type = 'citizenid' AND grant_scope.identifier = ?)
                OR (grant_scope.type = 'job' AND grant_scope.identifier = ?))))
        GROUP BY mr.id
        ORDER BY mr.datecreated DESC
        LIMIT ?
        OFFSET ?
    ]], { jobType, jobType, jobType, identifier, job, jobType, job, identifier, job, pageSize, offset })
    if not ok then return {} end
    if type(rows) ~= 'table' then return {} end
    for _, row in ipairs(rows) do
        if type(row) ~= 'table' or not tonumber(row.id) then return {} end
    end
    if not CheckAuth(src) or not CheckPermission(src, 'reports_view')
        or not sameDashboardSnapshot(snapshot, dashboardSnapshot(src)) then return {} end
    return rows
end)

local function computeActiveBolos(src)
    local ok, BOLOS = pcall(MySQL.query.await,
        'SELECT id, type, subject_id, subject_name, reportId, notes, status FROM mdt_bolos WHERE status = ? ORDER BY id DESC LIMIT 500', { 'active' })
    if not ok then return {} end
    if type(BOLOS) ~= 'table' or #BOLOS > 500 then return {} end
    if not CheckAuth(src) or not CheckPermission(src, 'bolos_view') then return {} end
    local result = {}
    for _, v in pairs(BOLOS) do
        if type(v) ~= 'table' or not tonumber(v.id) then return {} end
        local reportId = tonumber(v.reportId)
        if not reportId or (type(CanReadMdtReport) == 'function'
            and CheckAuth(src) and CheckPermission(src, 'bolos_view')
            and CanReadMdtReport(src, reportId)) then
        result[#result + 1] = {
            id       = v.id,
            reportId = v.reportId and tostring(v.reportId) or 'N/A',
            name     = type(v.subject_name) == 'string' and v.subject_name
                or (v.subject_id and ps.getPlayerNameByIdentifier(v.subject_id)) or 'Unknown',
            type     = v.type,
            notes    = v.notes or '',
            status   = v.status,
        }
        end
    end
    if not CheckAuth(src) or not CheckPermission(src, 'bolos_view') then return {} end
    for _, entry in ipairs(result) do
        if tonumber(entry.reportId) and (type(CanReadMdtReport) ~= 'function'
            or not CanReadMdtReport(src, tonumber(entry.reportId))) then return {} end
    end
    return result
end

registerDashboardRead('getActiveBolos', function(src, snapshot)
    if snapshot.jobType ~= 'leo' and snapshot.jobType ~= 'doj' then return {} end
    if not snapshot.permissions.bolos_view then return {} end
    return computeActiveBolos(src)
end)

local function computeActiveUnits(snapshot)
    if snapshot and snapshot.jobType == 'ems' then
        local count = tonumber(ps.getJobTypeCount(Config.MedicalJobType or 'ems'))
        if not count or count ~= count or count < 0 or count == math.huge then count = 0 end
        return { count = math.floor(count) }
    end
    return Cache.getOrSet('dashboard:activeUnits:' .. tostring(snapshot and snapshot.jobType),
        Config.CacheTTL and Config.CacheTTL.ActiveUnits or 10, function()
        local count = tonumber(ps.getJobTypeCount('leo'))
        if not count or count ~= count or count < 0 or count == math.huge then count = 0 end
        return { count = math.floor(count) }
    end)
end

registerDashboardRead('getActiveUnits', function(src, snapshot)
    return computeActiveUnits(snapshot)
end, function() return { count = 0 } end)

local function sanitizeDispatch(call)
    if type(call) ~= 'table' then return nil end
    if call.id ~= nil and type(call.id) ~= 'number' and type(call.id) ~= 'string' then return nil end
    if type(call.id) == 'string' and (#call.id > 128 or call.id:find('%z')) then return nil end
    if type(call.id) == 'number' and (call.id ~= call.id or math.abs(call.id) == math.huge) then return nil end
    local sanitized = {
        id          = call.id,
        message     = call.message     or call.dispatchMessage or '',
        code        = call.code        or call.dispatchCode    or '',
        street      = call.street      or '',
        priority    = call.priority    or 0,
        time        = call.time        or 0,
        gender      = call.gender,
        plate       = call.plate,
        color       = call.color,
        model       = call.model,
        weapon      = call.weapon,
        heading     = call.heading,
        speed       = call.speed,
        callSign    = call.callSign,
        description = call.description,
        camId       = call.camId,
        firstColor  = call.firstColor,
    }
    if call.coords then
        if type(call.coords) == 'vector3' or type(call.coords) == 'vector4' then
            sanitized.coords = { x = call.coords.x, y = call.coords.y, z = call.coords.z }
        elseif type(call.coords) == 'table' then
            sanitized.coords = { x = call.coords.x or call.coords[1], y = call.coords.y or call.coords[2], z = call.coords.z or call.coords[3] }
        end
    end
    if sanitized.coords then
        local x, y, z = tonumber(sanitized.coords.x), tonumber(sanitized.coords.y), tonumber(sanitized.coords.z)
        if not x or not y or not z or x ~= x or y ~= y or z ~= z
            or math.abs(x) > 100000 or math.abs(y) > 100000 or math.abs(z) > 100000 then
            sanitized.coords = nil
        else
            sanitized.coords = { x = x, y = y, z = z }
        end
    end
    sanitized.units = {}
    if call.units and type(call.units) == 'table' then
        local unitCount = 0
        for _, unit in pairs(call.units) do
            unitCount = unitCount + 1
            if unitCount > 100 then break end
            if type(unit) == 'table' then
                sanitized.units[#sanitized.units + 1] = {
                    citizenid = unit.citizenid,
                    charinfo  = unit.charinfo,
                    job       = unit.job,
                    metadata  = type(unit.metadata) == 'table'
                        and { callsign = unit.metadata.callsign } or nil,
                }
            end
        end
    end
    if call.jobs and type(call.jobs) == 'table' and #call.jobs <= 100 then
        sanitized.jobs = {}
        for _, job in ipairs(call.jobs) do
            if type(job) == 'string' and #job <= 64 and job:find('%S') then
                sanitized.jobs[#sanitized.jobs + 1] = job
            end
        end
    end
    return sanitized
end

-- Latest open investigations for the dashboard.
local function computeOpenCases()
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT id, case_number, title, status, priority, updated_at
        FROM mdt_cases
        WHERE status IN ('open', 'in_progress')
        ORDER BY updated_at DESC
        LIMIT 6
    ]])
    if not ok or type(rows) ~= 'table' then return {} end
    for _, row in ipairs(rows) do
        if type(row) ~= 'table' or not tonumber(row.id) then return {} end
    end
    return rows
end

-- Next few calendar entries (court/training/meetings) for the dashboard.
local function computeUpcomingHearings(src, snapshot)
    if snapshot and snapshot.jobType == 'ems' then
        if not snapshot.permissions.training_view or not CheckAuth(src)
            or not CheckPermission(src, 'training_view') then return {} end
        local ok, rows = pcall(MySQL.query.await, [[
            SELECT id, title, category, hearing_type, scheduled_at, location, status
            FROM mdt_court_hearings
            WHERE job_type = ? AND category IN ('training', 'meeting', 'other')
              AND status IN ('scheduled', 'in_session')
              AND scheduled_at >= (NOW() - INTERVAL 1 HOUR)
            ORDER BY scheduled_at ASC LIMIT 6
        ]], { 'ems' })
        if not ok or type(rows) ~= 'table' or not CheckAuth(src)
            or not CheckPermission(src, 'training_view') then return {} end
        return rows
    end
    local domain = GetMdtDomain and GetMdtDomain(src)
    if type(domain) ~= 'string' or not domain:find('%S')
        or #domain > 64 or domain:find('%z') then return {} end
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT id, title, category, hearing_type, defendant_name, scheduled_at, location, status
        FROM mdt_court_hearings
        WHERE job_type = ?
          AND status IN ('scheduled', 'in_session')
          AND scheduled_at >= (NOW() - INTERVAL 1 HOUR)
        ORDER BY scheduled_at ASC
        LIMIT 6
    ]], { domain })
    if not ok or type(rows) ~= 'table' or not CheckAuth(src) then return {} end
    for _, row in ipairs(rows) do
        if type(row) ~= 'table' or not tonumber(row.id) then return {} end
    end
    return rows
end

-- Globally dismissed calls (dispatcher action) — filtered out of every list.
-- Entries auto-expire so the table can't grow forever.
local DismissedDispatches = {}
local DISMISS_TTL = 2 * 60 * 60 -- seconds

-- One note per call: DispatchNotes[callId] = { text, author, updatedAt }.
-- Lives alongside the call; pruned on the same TTL and cleared on dismiss.
local DispatchNotes = {}

-- Manually created calls (from the MDT "Create Call" modal). These are owned by
-- the MDT so we control the id, note and initial units directly. They're merged
-- into the dispatch list alongside the provider's own calls.
local ManualDispatches = {}
local MANUAL_TTL = 2 * 60 * 60 -- seconds
local manualSeq = 0

local function pruneDismissed()
    local now = os.time()
    for id, at in pairs(DismissedDispatches) do
        if (now - at) > DISMISS_TTL then DismissedDispatches[id] = nil end
    end
    for id, note in pairs(DispatchNotes) do
        if note.updatedAt and (now - note.updatedAt) > DISMISS_TTL then DispatchNotes[id] = nil end
    end
    for id, call in pairs(ManualDispatches) do
        if call.time and (os.time() - math.floor(call.time / 1000)) > MANUAL_TTL then ManualDispatches[id] = nil end
    end
end

local function filterDismissed(list)
    pruneDismissed()
    if not next(DismissedDispatches) then return list end
    local out = {}
    for _, call in ipairs(list or {}) do
        if not DismissedDispatches[tostring(call.id)] then
            out[#out + 1] = call
        end
    end
    return out
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Dispatch provider layer
-- Each provider returns a RAW call list in a ps-dispatch-like shape; the shared
-- sanitizeDispatch() below turns that into the MDT's final format. Adding a new
-- system means writing one fetch function here — the map, ticker, unit
-- assignment and dismiss logic never need to change.
-- ═══════════════════════════════════════════════════════════════════════════

local function resourceRunning(name)
    return GetResourceState(name) == 'started' or GetResourceState(name) == 'starting'
end

-- ps-dispatch: already exposes a normalized list via GetDispatchCalls().
local function fetchPsDispatch()
    local ok, calls = pcall(function()
        return exports['ps-dispatch'] and exports['ps-dispatch']:GetDispatchCalls() or {}
    end)
    if not ok then return {} end
    return calls or {}
end

-- qs-dispatch: calls carry callLocation / callCode{code,snippet} / message and a
-- responses/units list. Map those onto the ps-style fields sanitizeDispatch wants.
local function fetchQsDispatch()
    local ok, calls = pcall(function()
        local ex = exports['qs-dispatch']
        if not ex then return {} end
        -- qs exposes a couple of getter names across versions; try both.
        if ex.GetDispatchCalls then return ex:GetDispatchCalls() end
        if ex.GetActiveCalls   then return ex:GetActiveCalls()   end
        return {}
    end)
    if not ok or type(calls) ~= 'table' then return {} end

    local out = {}
    for _, c in pairs(calls) do
        if type(c) == 'table' then
            local code = c.code or (c.callCode and (c.callCode.code or c.callCode.snippet))
            out[#out + 1] = {
                id       = c.id or c.callId or c.dispatchId,
                message  = c.message,
                code     = code,
                codeName = c.callCode and c.callCode.snippet or nil,
                priority = c.priority or (c.blip and c.blip.priority) or 0,
                coords   = c.callLocation or c.coords or c.location,
                street   = c.street or c.street_1,
                time     = c.time or c.dispatchTime,
                gender   = c.sex or c.gender,
                plate    = c.vehicle_plate or c.plate,
                color    = c.vehicle_colour or c.color,
                model    = c.vehicle_label or c.model,
                units    = c.units or c.responses,
                jobs     = c.job or c.jobs,
                image    = c.image,
            }
        end
    end
    return out
end

-- cd_dispatch (Codesign): calls use title / message / coords and a unique_id.
local function fetchCdDispatch()
    local ok, calls = pcall(function()
        local ex = exports['cd_dispatch']
        if not ex then return {} end
        if ex.GetActiveCalls   then return ex:GetActiveCalls()   end
        if ex.GetDispatchCalls then return ex:GetDispatchCalls() end
        return {}
    end)
    if not ok or type(calls) ~= 'table' then return {} end

    local out = {}
    for _, c in pairs(calls) do
        if type(c) == 'table' then
            out[#out + 1] = {
                id       = c.id or c.unique_id or c.callId,
                message  = c.message,
                code     = c.code or c.title,
                codeName = c.title,
                priority = c.priority or 0,
                coords   = c.coords or c.origin or c.location,
                street   = c.street,
                time     = c.time,
                gender   = c.gender or c.sex,
                plate    = c.plate,
                color    = c.color,
                model    = c.model or c.vehicle,
                units    = c.units or c.responses,
                jobs     = c.job_table or c.jobs or c.job,
                image    = c.image,
            }
        end
    end
    return out
end

-- Resolve the configured provider and fetch raw calls. When none of the three
-- supported dispatch resources can be found, warn once (server console) so the
-- server owner knows the MDT has nothing to read from.
local dispatchWarned = false
local function resolveProvider()
    local provider = (Config and Config.Dispatch and Config.Dispatch.Provider) or 'auto'

    -- Explicit choice: honor it only if that resource is actually running.
    if provider == 'ps' or provider == 'qs' or provider == 'cd' then
        local resByProvider = { ps = 'ps-dispatch', qs = 'qs-dispatch', cd = 'cd_dispatch' }
        if resourceRunning(resByProvider[provider]) then return provider end
    end

    -- Auto-detect (also the fallback when an explicit choice isn't running).
    if resourceRunning('ps-dispatch') then return 'ps' end
    if resourceRunning('qs-dispatch') then return 'qs' end
    if resourceRunning('cd_dispatch') then return 'cd' end

    if not dispatchWarned then
        dispatchWarned = true
        print('^3[ps-mdt]^0 No supported dispatch resource detected (ps-dispatch, qs-dispatch or cd_dispatch). Dispatch calls will not appear on the map.')
    end
    return nil
end

local function fetchDispatchCalls()
    local provider = resolveProvider()
    if provider == 'qs' then return fetchQsDispatch() end
    if provider == 'cd' then return fetchCdDispatch() end
    if provider == 'ps' then return fetchPsDispatch() end
    return {}
end

-- The heavy part of building the dispatch list (provider fetch, manual-call
-- merge, dismiss filter, and sanitizing + note-attaching EVERY call) produces
-- the same result for every player — only the final job filter is per-player.
-- We cache that shared list for a short window so N open MDTs polling every
-- ~10s don't each redo the provider export + full sanitize pass. The cache is
-- invalidated immediately whenever a call/note/assignment changes.
local dispatchListCache = { ts = 0, list = nil }
-- Short TTL: long enough to collapse the burst of simultaneous polls from many
-- open MDTs (and the open-time fetch), short enough that a brand-new provider
-- alert still shows up promptly. Mutations from the MDT itself (notes, dismiss,
-- manual calls, assignments) invalidate instantly, so this only ever delays
-- calls created by the external dispatch resource, by at most this window.
local DISPATCH_CACHE_TTL = 2000 -- ms

local function invalidateDispatchCache()
    dispatchListCache.ts = 0
    dispatchListCache.list = nil
end

-- Preserve the provider's audience separately from the legacy response shape.
-- Older sanitization drops string/map audiences; EMS must never interpret a
-- missing or malformed recipient list as a globally authorized call.
local dispatchAudiences = setmetatable({}, { __mode = 'k' })
local function normalizedDispatchAudience(value)
    local audience = {}
    if type(value) == 'string' then
        if value ~= '' and #value <= 64 and not value:find('%z') then audience[value] = true end
    elseif type(value) == 'table' then
        for key, entry in pairs(value) do
            if type(key) == 'number' and type(entry) == 'string' and entry ~= ''
                and #entry <= 64 and not entry:find('%z') then
                audience[entry] = true
            elseif type(key) == 'string' and key ~= '' and #key <= 64 and not key:find('%z') and
                (entry == true or (type(entry) == 'number' and entry >= 0)) then
                audience[key] = true
            end
        end
    end
    return audience
end

local function projectEmsDispatch(call, audience)
    local result = {}
    for key, value in pairs(call) do if key ~= 'units' then result[key] = value end end
    result.jobs = {}
    for jobName in pairs(audience) do
        if #result.jobs >= 100 then break end
        if type(jobName) == 'string' and #jobName <= 64
            and jobName:find('%S') and not jobName:find('%z') then
            result.jobs[#result.jobs + 1] = jobName
        end
    end
    table.sort(result.jobs)
    result.units = {}
    if type(call.units) ~= 'table' then return nil end
    local projectedUnitCount = 0
    for _, unit in pairs(call.units) do
        projectedUnitCount = projectedUnitCount + 1
        if projectedUnitCount > 100 then return nil end
        if type(unit) ~= 'table' then return nil end
        local info = type(unit.charinfo) == 'table' and unit.charinfo or {}
        local job = type(unit.job) == 'table' and unit.job or {}
        local metadata = type(unit.metadata) == 'table' and unit.metadata or {}
        result.units[#result.units + 1] = {
            citizenid = unit.citizenid,
            charinfo = { firstname = info.firstname, lastname = info.lastname },
            job = { name = job.name, label = job.label, type = job.type },
            metadata = { callsign = metadata.callsign },
        }
    end
    return result
end

local function buildSanitizedDispatches()
    local now = GetGameTimer()
    if dispatchListCache.list and now >= dispatchListCache.ts
        and (now - dispatchListCache.ts) < DISPATCH_CACHE_TTL then
        return dispatchListCache.list
    end

    local providerCalls = fetchDispatchCalls()
    if type(providerCalls) ~= 'table' then providerCalls = {} end
    local recentDispatches = {}
    for _, call in pairs(providerCalls) do
        if #recentDispatches >= 500 then break end
        if type(call) == 'table' then recentDispatches[#recentDispatches + 1] = call end
    end

    -- Merge MDT-created calls in alongside the provider's own calls.
    for _, call in pairs(ManualDispatches) do
        if #recentDispatches >= 600 then break end
        if type(call) == 'table' then recentDispatches[#recentDispatches + 1] = call end
    end

    recentDispatches = filterDismissed(recentDispatches)

    -- Sanitize + attach notes once (player-independent).
    local built = {}
    for _, call in ipairs(recentDispatches) do
        local sanitized = sanitizeDispatch(call)
        if sanitized and sanitized.id ~= nil then
            dispatchAudiences[sanitized] = normalizedDispatchAudience(call.jobs)
            local note = sanitized.id ~= nil and DispatchNotes[tostring(sanitized.id)] or nil
            if note then
                sanitized.note = { text = note.text, author = note.author, updatedAt = note.updatedAt }
            end
            built[#built + 1] = sanitized
        end
    end

    dispatchListCache.list = built
    dispatchListCache.ts = now
    return built
end

local function computeRecentDispatches(src, snapshot)
    local dispatches = buildSanitizedDispatches()

    if snapshot and snapshot.jobType == 'ems' then
        if type(snapshot.job) ~= 'string' or snapshot.job == '' then return {} end
        local filtered = {}
        for _, call in ipairs(dispatches) do
            local audience = dispatchAudiences[call] or {}
            if audience[snapshot.job] or audience[Config.MedicalJobType or 'ems'] or audience.ems then
                local projected = projectEmsDispatch(call, audience)
                if projected then filtered[#filtered + 1] = projected end
            end
        end
        if not CheckAuth(src) or not sameDashboardSnapshot(snapshot, dashboardSnapshot(src)) then return {} end
        return filtered
    end

    -- Per-player job filter is cheap (a table scan, no DB/export), so it stays
    -- outside the cache.
    if Config and Config.Dispatch and Config.Dispatch.FilterByJob == true then
        local jobName = ps.getJobName(src)
        local jobType = ps.getJobType and ps.getJobType(src) or nil
        if not jobName then return {} end
        if jobName then
            local filtered = {}
            for _, call in ipairs(dispatches) do
                if not call.jobs or #call.jobs == 0 then
                    filtered[#filtered + 1] = call
                else
                    for _, job in ipairs(call.jobs) do
                        if job == jobName or job == jobType then
                            filtered[#filtered + 1] = call
                            break
                        end
                    end
                end
            end
            dispatches = filtered
        end
    end

    if not CheckAuth(src) or not sameDashboardSnapshot(snapshot, dashboardSnapshot(src)) then return {} end
    return dispatches
end

registerDashboardRead('getRecentDispatches', function(src, snapshot)
    if snapshot.jobType ~= 'leo' and snapshot.jobType ~= 'ems'
        and snapshot.jobType ~= 'fire' and snapshot.jobType ~= 'doj' then return {} end
    return computeRecentDispatches(src, snapshot)
end)

-- Impound at a glance: how much is being held, how much money is outstanding and
-- how long the oldest car has been sitting there. Storage fees are derived from
-- the impound date (see server/backend/impound.lua), so the outstanding total has
-- to be worked out the same way here rather than read from a column.
local function computeImpoundMetrics(safeCount)
    local cfg = (Config and Config.Impound) or {}
    local storage = cfg.Storage or {}
    local perDay = tonumber(storage.PerDay) or 0
    local maxDays = tonumber(storage.MaxDays) or 0
    if perDay ~= perDay or perDay < 0 or perDay == math.huge then perDay = 0 end
    perDay = math.min(perDay, 1000000)
    if maxDays ~= maxDays or maxDays < 0 or maxDays == math.huge then maxDays = 0 end
    maxDays = math.floor(math.min(maxDays, 36500))

    local held = safeCount("SELECT COUNT(*) FROM mdt_impound WHERE status = 'active'")
    local impoundedLast7 = safeCount(
        "SELECT COUNT(*) FROM mdt_impound WHERE time >= UNIX_TIMESTAMP(NOW() - INTERVAL 7 DAY)")

    local rows = {}
    local ok, res = pcall(MySQL.query.await,
        "SELECT fee, fee_paid, time FROM mdt_impound WHERE status = 'active'")
    if ok and type(res) == 'table' and #res <= 5000 then rows = res end

    local outstanding, oldestDays = 0, 0
    local now = os.time()
    for _, r in ipairs(rows) do
        if type(r) ~= 'table' then return { held = 0, outstanding = 0, oldestDays = 0, impoundedLast7 = 0 } end
        local impoundTime = tonumber(r.time) or now
        if impoundTime ~= impoundTime or math.abs(impoundTime) == math.huge then impoundTime = now end
        local days = math.floor((now - impoundTime) / 86400)
        if days < 0 then days = 0 end
        if days > 36500 then days = 36500 end
        if days > oldestDays then oldestDays = days end

        local paid = r.fee_paid == true or r.fee_paid == 1
            or r.fee_paid == '1'
        if not paid then
            local billable = math.min(days, maxDays)
            local fee = tonumber(r.fee) or 0
            if fee ~= fee or fee < 0 or fee == math.huge then fee = 0 end
            outstanding = outstanding + fee + (billable * perDay)
        end
    end

    return {
        held           = held,
        outstanding    = outstanding,
        oldestDays     = oldestDays,
        impoundedLast7 = impoundedLast7,
    }
end

local function computeUsageMetrics(snapshot)
    if snapshot and snapshot.jobType == 'ems' then
        if not snapshot.permissions.reports_view then return {} end
        local row = {}
        if canReadEmsReports(snapshot) then
            local ok, rows = pcall(MySQL.query.await, ([[
                SELECT COUNT(DISTINCT mr.id) AS reports,
                    COUNT(DISTINCT CASE WHEN mr.datecreated >= NOW() - INTERVAL 7 DAY THEN mr.id END) AS reportsLast7,
                    COUNT(DISTINCT CASE WHEN mr.datecreated >= NOW() - INTERVAL 30 DAY THEN mr.id END) AS reportsLast30
                FROM mdt_reports mr WHERE %s
            ]]):format(EMS_REPORT_ACCESS), emsReportParameters(snapshot))
            row = ok and type(rows) == 'table' and type(rows[1]) == 'table' and rows[1] or {}
        end
        return {
            totals = { reports = tonumber(row.reports) or 0, arrests = 0, activeWarrants = 0 },
            windows = {
                reportsLast7 = tonumber(row.reportsLast7) or 0,
                reportsLast30 = tonumber(row.reportsLast30) or 0,
                arrestsLast7 = 0, arrestsLast30 = 0,
            },
            impound = { held = 0, outstanding = 0, oldestDays = 0, impoundedLast7 = 0 },
        }
    end
    if not snapshot or not snapshot.permissions.reports_view
        or (snapshot.jobType ~= 'leo' and snapshot.jobType ~= 'doj')
        or type(snapshot.job) ~= 'string' or not snapshot.job:find('%S')
        or #snapshot.job > 64 or snapshot.job:find('%z') then return {} end
    return Cache.getOrSet('dashboard:usageMetrics:' .. snapshot.job .. ':' .. tostring(snapshot.permissionKey),
        Config.CacheTTL and Config.CacheTTL.UsageMetrics or 60, function()
        local function safeCount(query, params)
            local ok, result = pcall(MySQL.scalar.await, query, params or {})
            local count = ok and tonumber(result) or nil
            if not count or count ~= count or count < 0 or count == math.huge then return 0 end
            return math.floor(count)
        end
        return {
            totals = {
                reports       = safeCount([[SELECT COUNT(*) FROM mdt_reports mr
                    WHERE EXISTS (SELECT 1 FROM mdt_reports_restrictions own
                        WHERE own.reportid = mr.id AND own.type = 'owner' AND own.identifier = ?)]], {snapshot.job}),
                arrests       = safeCount('SELECT COUNT(*) FROM mdt_arrests'),
                activeWarrants = safeCount('SELECT COUNT(*) FROM mdt_reports_warrants WHERE expirydate >= NOW()'),
            },
            windows = {
                reportsLast7   = safeCount([[SELECT COUNT(*) FROM mdt_reports mr
                    WHERE mr.datecreated >= NOW() - INTERVAL 7 DAY
                    AND EXISTS (SELECT 1 FROM mdt_reports_restrictions own
                        WHERE own.reportid = mr.id AND own.type = 'owner' AND own.identifier = ?)]], {snapshot.job}),
                reportsLast30  = safeCount([[SELECT COUNT(*) FROM mdt_reports mr
                    WHERE mr.datecreated >= NOW() - INTERVAL 30 DAY
                    AND EXISTS (SELECT 1 FROM mdt_reports_restrictions own
                        WHERE own.reportid = mr.id AND own.type = 'owner' AND own.identifier = ?)]], {snapshot.job}),
                arrestsLast7   = safeCount('SELECT COUNT(*) FROM mdt_arrests WHERE created_at >= NOW() - INTERVAL 7 DAY'),
                arrestsLast30  = safeCount('SELECT COUNT(*) FROM mdt_arrests WHERE created_at >= NOW() - INTERVAL 30 DAY'),
            },
            impound = computeImpoundMetrics(safeCount),
        }
    end)
end

registerDashboardRead('getUsageMetrics', function(src, snapshot)
    return computeUsageMetrics(snapshot)
end)

-- ============================================================================
--  Aggregate: one round-trip for the whole dashboard.
--  The frontend previously fired ~9 separate NUI callbacks on open (one per
--  widget). This bundles them into a single callback so opening the MDT does
--  one server round-trip + one cb() serialisation instead of nine, which is
--  the bulk of the on-open client spike.
-- ============================================================================
registerDashboardRead('getDashboard', function(src, snapshot)
    if snapshot.jobType == 'ems' then
        return {
            dashboardDomain = 'ems',
            jobData = computeJobData(src),
            upcomingHearings = computeUpcomingHearings(src, snapshot),
            openCases = {},
            reportStatistics = computeReportStatistics(src, snapshot),
            timeStatistics = computeTimeStatistics(src),
            activeWarrants = {},
            bulletins = computeEmsBulletins(snapshot),
            activeBolos = {},
            activeUnits = computeActiveUnits(snapshot),
            usageMetrics = computeUsageMetrics(snapshot),
            recentDispatches = computeRecentDispatches(src, snapshot),
        }
    end
    return {
        jobData          = computeJobData(src),
        upcomingHearings = computeUpcomingHearings(src, snapshot),
        openCases        = snapshot.permissions.cases_view and computeOpenCases() or {},
        reportStatistics = computeReportStatistics(src, snapshot),
        timeStatistics   = computeTimeStatistics(src),
        activeWarrants   = snapshot.permissions.warrants_view
            and (GetActiveWarrantsData and GetActiveWarrantsData(src)) or {},
        bulletins        = (snapshot.permissions.bulletin_view
            and (snapshot.jobType == 'leo' or snapshot.jobType == 'doj'))
            and computeBulletins() or {},
        activeBolos      = snapshot.permissions.bolos_view and computeActiveBolos(src) or {},
        activeUnits      = computeActiveUnits(snapshot),
        -- The frontend already reads usageMetrics off this payload but the server
        -- never sent it, so the numbers (and the impound tile) stayed empty.
        usageMetrics     = snapshot.permissions.reports_view
            and computeUsageMetrics(snapshot) or {},
        recentDispatches = computeRecentDispatches(src, snapshot),
    }
end)
-- Human-readable description of a call for audit labels, e.g. "10-71 (Shooting)"
-- or "call #mdt-…" as a fallback. Reads from the cached/known call data.
local function describeCall(id)
    id = tostring(id)
    local manual = ManualDispatches[id]
    if manual then
        local code = manual.code or 'Call'
        local msg  = manual.message and manual.message ~= '' and manual.message or nil
        return msg and ('%s (%s)'):format(code, msg) or code
    end
    return ('call #%s'):format(id)
end

-- Dispatcher: globally dismiss a call — it disappears from every MDT.
ps.registerCallback(resourceName .. ':server:dismissDispatch', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    if not CheckPermission(src, 'dispatch_assign') then
        return { success = false, error = 'No permission' }
    end
    data = data or {}
    local id = data.dispatch_id and tostring(data.dispatch_id) or nil
    if not id then return { success = false, error = 'Invalid request' } end

    local label = describeCall(id)
    DismissedDispatches[id] = os.time()
    DispatchNotes[id] = nil -- note dies with the call
    ManualDispatches[id] = nil -- MDT-created calls are removed outright
    if ps.auditLog then
        ps.auditLog(src, 'dispatch_dismiss', 'dispatch', id, {
            dispatch_id  = id,
            action_label = ('Dismissed %s for all units'):format(label),
        })
    end
    -- Nudge every open MDT to refresh its (now filtered) dispatch list.
    invalidateDispatchCache()
    TriggerClientEvent(resourceName .. ':client:dispatchDismissed', -1, id)
    return { success = true }
end)

-- ---------------------------------------------------------------------------
-- Dispatcher: per-call notes (one note per call).
-- Notes are attached to each call in computeRecentDispatches and shown to
-- assigned units. Editing a note re-notifies everyone currently on the call.
-- ---------------------------------------------------------------------------
local NOTE_MAX = 300

-- Resolve the source IDs of the units currently attached to a call, so we can
-- re-notify them when a note changes. Reads back the live provider call list.
local function getAssignedSources(dispatchId)
    local sources = {}
    local calls = fetchDispatchCalls()
    for _, call in ipairs(calls or {}) do
        if tostring(call.id) == tostring(dispatchId) and type(call.units) == 'table' then
            local okCore, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
            if not okCore then QBCore = nil end
            for _, unit in pairs(call.units) do
                local cid = type(unit) == 'table' and unit.citizenid or nil
                if cid then
                    local tSrc = nil
                    if ps.getPlayerByIdentifier then
                        local p = ps.getPlayerByIdentifier(cid)
                        tSrc = p and (p.PlayerData and p.PlayerData.source or p.source) or nil
                    end
                    if not tSrc and QBCore and QBCore.Functions.GetPlayerByCitizenId then
                        local p = QBCore.Functions.GetPlayerByCitizenId(cid)
                        tSrc = p and p.PlayerData and p.PlayerData.source or nil
                    end
                    if tSrc then sources[#sources + 1] = tSrc end
                end
            end
            break
        end
    end
    return sources
end

ps.registerCallback(resourceName .. ':server:setDispatchNote', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    if not CheckPermission(src, 'dispatch_notes') then
        return { success = false, error = 'No permission' }
    end

    data = data or {}
    local id = data.dispatch_id and tostring(data.dispatch_id) or nil
    local text = type(data.text) == 'string' and data.text or ''
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    if not id then return { success = false, error = 'Invalid request' } end
    if text == '' then return { success = false, error = 'Note cannot be empty' } end
    if #text > NOTE_MAX then text = text:sub(1, NOTE_MAX) end

    local existed = DispatchNotes[id] ~= nil
    local okName, author = pcall(function()
        if ps.getCharInfo then
            return (ps.getCharInfo('firstname', src) or '') .. ' ' .. (ps.getCharInfo('lastname', src) or '')
        end
        return nil
    end)
    if not okName then author = nil end
    if author then author = author:gsub('^%s+', ''):gsub('%s+$', '') end
    DispatchNotes[id] = { text = text, author = (author ~= '' and author) or nil, updatedAt = os.time() }

    if ps.auditLog then
        local label = describeCall(id)
        ps.auditLog(src, existed and 'dispatch_note_edit' or 'dispatch_note_add', 'dispatch', id, {
            dispatch_id  = id,
            note         = text,
            action_label = existed
                and ('Edited the note on %s'):format(label)
                or  ('Added a note to %s'):format(label),
        })
    end

    -- Tell every open MDT to refresh (note now travels with the call).
    invalidateDispatchCache()
    TriggerClientEvent(resourceName .. ':client:dispatchNoteChanged', -1, id)

    -- If units are already on the call, re-notify them that the note changed.
    if existed then
        for _, tSrc in ipairs(getAssignedSources(id)) do
            TriggerClientEvent(resourceName .. ':client:dispatchNoteNotify', tSrc, { text = text })
        end
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:deleteDispatchNote', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    if not CheckPermission(src, 'dispatch_notes') then
        return { success = false, error = 'No permission' }
    end
    data = data or {}
    local id = data.dispatch_id and tostring(data.dispatch_id) or nil
    if not id then return { success = false, error = 'Invalid request' } end

    local label = describeCall(id)
    DispatchNotes[id] = nil
    if ps.auditLog then
        ps.auditLog(src, 'dispatch_note_delete', 'dispatch', id, {
            dispatch_id  = id,
            action_label = ('Removed the note from %s'):format(label),
        })
    end
    invalidateDispatchCache()
    TriggerClientEvent(resourceName .. ':client:dispatchNoteChanged', -1, id)
    return { success = true }
end)

-- Self attach/detach for MANUAL calls (provider calls handle this themselves).
-- No dispatch permission needed — you're only touching your own attachment.
ps.registerCallback(resourceName .. ':server:selfDispatchAttach', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    data = data or {}
    local id = data.dispatch_id and tostring(data.dispatch_id) or nil
    local call = id and ManualDispatches[id] or nil
    if not call then return { success = false, error = 'Unknown call' } end

    local cid = ps.getIdentifier and ps.getIdentifier(src) or nil
    if not cid then return { success = false } end
    call.units = call.units or {}

    if data.action == 'detach' then
        for i = #call.units, 1, -1 do
            if call.units[i].citizenid == cid then table.remove(call.units, i) end
        end
    else
        local exists = false
        for _, u in ipairs(call.units) do if u.citizenid == cid then exists = true break end end
        if not exists then
            local okFirst, firstname = pcall(function() return ps.getCharInfo('firstname', src) end)
            local okLast,  lastname  = pcall(function() return ps.getCharInfo('lastname', src) end)
            call.units[#call.units + 1] = {
                citizenid = cid,
                charinfo  = {
                    firstname = okFirst and firstname or nil,
                    lastname  = okLast and lastname or nil,
                },
                metadata  = { callsign = ps.getMetadata and ps.getMetadata(src, 'callsign') or nil },
            }
        end
    end

    invalidateDispatchCache()
    TriggerClientEvent(resourceName .. ':client:dispatchNoteChanged', -1, id)
    return { success = true }
end)

-- ---------------------------------------------------------------------------
-- Dispatcher: create a manual call from the MDT "Create Call" modal.
-- These are owned by the MDT (we control the id/note/units) and merged into the
-- dispatch list, so they flow into the ticker/map/assignment like any call —
-- without touching the underlying dispatch resource.
-- ---------------------------------------------------------------------------
ps.registerCallback(resourceName .. ':server:createManualDispatch', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    if not CheckPermission(src, 'dispatch_assign') then
        return { success = false, error = 'No permission' }
    end

    data = data or {}
    local code     = type(data.code) == 'string' and data.code or ''
    local title    = type(data.title) == 'string' and data.title or ''
    local coords   = type(data.coords) == 'table' and data.coords or nil
    title = title:gsub('^%s+', ''):gsub('%s+$', '')

    if code == '' then return { success = false, error = 'A 10-code is required' } end
    if not coords or not tonumber(coords.x) or not tonumber(coords.y) then
        return { success = false, error = 'Pick a location on the map' }
    end

    -- Title falls back to the code's label (sent by the client from config).
    if title == '' then
        title = type(data.label) == 'string' and data.label:gsub('^%s+', ''):gsub('%s+$', '') or ''
    end
    if title == '' then title = code end

    -- Priority is derived from the code/title keywords (1 high / 2 med / 3 low),
    -- so it doesn't need to be configured per code.
    local function derivePriority(hay)
        hay = (hay or ''):lower()
        if hay:find('shoot') or hay:find('pursuit') or hay:find('robber') or hay:find('assist')
            or hay:find('10%-13') or hay:find('10%-71') or hay:find('10%-80') or hay:find('10%-90')
            or hay:find('officer') or hay:find('weapon') or hay:find('armed') then
            return 1
        end
        if hay:find('accident') or hay:find('ambulance') or hay:find('fire') or hay:find('disturb')
            or hay:find('suspicious') or hay:find('911') or hay:find('10%-52') or hay:find('10%-53') then
            return 2
        end
        return 3
    end
    local priority = derivePriority(code .. ' ' .. title)

    manualSeq = manualSeq + 1
    local id = 'mdt-' .. os.time() .. '-' .. manualSeq

    local jobs = nil
    if type(data.jobs) == 'table' and #data.jobs > 0 then
        jobs = data.jobs
    end

    ManualDispatches[id] = {
        id       = id,
        code     = code,
        message  = title,
        priority = priority,
        time     = os.time() * 1000, -- ms, matches the ticker's age display
        coords   = { x = tonumber(coords.x), y = tonumber(coords.y), z = tonumber(coords.z) or 0.0 },
        street   = type(data.street) == 'string' and data.street or nil,
        units    = {},
        jobs     = jobs,
        manual   = true,
    }

    -- Optional note straight from the modal.
    local note = type(data.note) == 'string' and data.note:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if note ~= '' then
        local okName, author = pcall(function()
            if ps.getCharInfo then
                return (ps.getCharInfo('firstname', src) or '') .. ' ' .. (ps.getCharInfo('lastname', src) or '')
            end
            return nil
        end)
        if not okName then author = nil end
        if author then author = author:gsub('^%s+', ''):gsub('%s+$', '') end
        DispatchNotes[id] = { text = note:sub(1, 300), author = (author ~= '' and author) or nil, updatedAt = os.time() }
    end

    if ps.auditLog then
        local label = (title and title ~= '' and title ~= code) and ('%s (%s)'):format(code, title) or code
        local streetPart = (type(data.street) == 'string' and data.street ~= '') and (' at %s'):format(data.street) or ''
        ps.auditLog(src, 'dispatch_create', 'dispatch', id, {
            dispatch_id  = id,
            code         = code,
            title        = title,
            action_label = ('Created %s%s'):format(label, streetPart),
        })
    end

    -- Broadcast so open MDTs pick the new call up immediately.
    invalidateDispatchCache()
    TriggerClientEvent(resourceName .. ':client:dispatchNoteChanged', -1, id)
    return { success = true, id = id }
end)

-- ---------------------------------------------------------------------------
-- Dispatcher: assign or detach OTHER units to/from a dispatch call.
-- The actual attach runs on the TARGET client (same path as self-attach via
-- ps-dispatch), which also sets their waypoint and notifies them. This keeps
-- ps-dispatch's unit bookkeeping identical to a self-attach.
-- ---------------------------------------------------------------------------
ps.registerCallback(resourceName .. ':server:assignToDispatch', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    if not CheckPermission(src, 'dispatch_assign') then
        return { success = false, error = 'No permission' }
    end

    data = data or {}
    local dispatchId = data.dispatch_id
    local action = data.action == 'detach' and 'detach' or 'attach'
    local citizenids = type(data.citizenids) == 'table' and data.citizenids or {}
    if not dispatchId or #citizenids == 0 then
        return { success = false, error = 'Invalid request' }
    end

    local okCore, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if not okCore then QBCore = nil end

    -- Manual (MDT-created) calls keep their unit list on the server, since the
    -- dispatch provider doesn't know about them.
    local manualCall = ManualDispatches[tostring(dispatchId)]

    local hit, miss = 0, 0
    local assignedNames = {} -- for a readable audit label
    local noteEntry = DispatchNotes[tostring(dispatchId)]
    local noteText = noteEntry and noteEntry.text or nil
    for _, cid in ipairs(citizenids) do
        local targetSrc = nil
        local targetPly = nil
        if ps.getPlayerByIdentifier then
            targetPly = ps.getPlayerByIdentifier(cid)
            targetSrc = targetPly and (targetPly.PlayerData and targetPly.PlayerData.source or targetPly.source) or nil
        end
        if not targetSrc and QBCore and QBCore.Functions.GetPlayerByCitizenId then
            targetPly = QBCore.Functions.GetPlayerByCitizenId(cid)
            targetSrc = targetPly and targetPly.PlayerData and targetPly.PlayerData.source or nil
        end

        -- Remember the officer's name (falls back to the citizenid) for the log.
        local ci = targetPly and targetPly.PlayerData and targetPly.PlayerData.charinfo or nil
        assignedNames[#assignedNames + 1] = ci and (ci.firstname .. ' ' .. ci.lastname) or cid

        -- For manual calls, maintain the unit list ourselves — do this even if
        -- the unit is offline so a detach always cleans the roster.
        if manualCall then
            manualCall.units = manualCall.units or {}
            if action == 'detach' then
                for i = #manualCall.units, 1, -1 do
                    if manualCall.units[i].citizenid == cid then table.remove(manualCall.units, i) end
                end
            else
                local exists = false
                for _, u in ipairs(manualCall.units) do
                    if u.citizenid == cid then exists = true break end
                end
                if not exists then
                    local pd = targetPly and targetPly.PlayerData or nil
                    manualCall.units[#manualCall.units + 1] = {
                        citizenid = cid,
                        charinfo  = pd and pd.charinfo or nil,
                        job       = pd and pd.job or nil,
                        metadata  = pd and pd.metadata and { callsign = pd.metadata.callsign } or nil,
                    }
                end
            end
        end

        if targetSrc then
            TriggerClientEvent(resourceName .. ':client:dispatchAssign', targetSrc, {
                id = dispatchId,
                action = action,
                coords = data.coords, -- {x, y} for waypoint (attach only)
                note = noteText,      -- included in the assignment notify
                manual = manualCall ~= nil, -- skip provider attach for manual calls
            })
            hit = hit + 1
        else
            miss = miss + 1
        end
    end

    -- Manual call unit changes: refresh open MDTs.
    if manualCall then
        invalidateDispatchCache()
        TriggerClientEvent(resourceName .. ':client:dispatchNoteChanged', -1, tostring(dispatchId))
    end

    if ps.auditLog then
        local label = describeCall(dispatchId)
        local who
        if #assignedNames == 1 then
            who = assignedNames[1]
        elseif #assignedNames == 2 then
            who = assignedNames[1] .. ' and ' .. assignedNames[2]
        else
            who = ('%d officers'):format(#assignedNames)
        end
        ps.auditLog(src, 'dispatch_' .. action .. '_units', 'dispatch', tostring(dispatchId), {
            dispatch_id  = tostring(dispatchId),
            officers     = assignedNames,
            count        = hit,
            action_label = action == 'detach'
                and ('Removed %s from %s'):format(who, label)
                or  ('Assigned %s to %s'):format(who, label),
        })
    end
    return { success = hit > 0, assigned = hit, offline = miss }
end)
