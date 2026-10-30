local resourceName = tostring(GetCurrentResourceName())

-- Warrant records belong to the existing police/DOJ audience. A medical job
-- must not receive the payload merely because it can open an MDT.
local function canReadWarrantData(src)
    if not CheckAuth(src) then return false end
    local access = GetMdtAccess(src)
    return type(access) == 'table' and access.authorized == true and access.isCivilian ~= true
        and (access.jobType == 'leo' or access.jobType == 'doj')
end

local function warrantReportExists(reportId)
    local id = tonumber(reportId)
    if not id or id ~= id or id == math.huge or id == -math.huge or id <= 0 or id % 1 ~= 0 then return false end
    return MySQL.scalar.await('SELECT id FROM mdt_reports WHERE id = ? LIMIT 1', { id }) ~= nil
end

local function validateExpiry(expiry)
    if expiry == nil then return nil end
    if type(expiry) ~= 'string' and type(expiry) ~= 'number' then return nil end
    if type(expiry) == 'string' and (expiry:find('%z') or #expiry > 32
        or not expiry:find('%S')) then return nil end
    local numeric = tonumber(expiry)
    if numeric then
        if numeric ~= numeric or numeric == math.huge or numeric == -math.huge then return nil end
        return numeric
    end
    if type(expiry) == 'string' then
        local trimmed = expiry:match('^%s*(.-)%s*$')
        if trimmed and trimmed:match('^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d
    end
    return nil
end

local function toTimestamp(value)
    local numeric = tonumber(value)
    if not numeric or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then return nil end
    if numeric > 100000000000 then return math.floor(numeric / 1000) end
    return numeric
end

local function getExpiryDate(value)
    local ts = toTimestamp(value)
    if ts then return os.date('%Y-%m-%d %H:%M:%S', ts) end
    if type(value) == 'string' and value:match('^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d
    return nil
end

-- Exposed as a global so the dashboard aggregate (server/backend/dashboard.lua)
-- can reuse it without a second round-trip.
function GetActiveWarrantsData(src)
    if src ~= nil and (not canReadWarrantData(src) or not CheckPermission(src, 'warrants_view')
        or type(CanReadMdtReport) ~= 'function') then
        return {}
    end
    local citizenid = src ~= nil and ps.getIdentifier(src) or nil
    local jobName = src ~= nil and ps.getJobName(src) or nil
    if src ~= nil and (type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z')
        or type(jobName) ~= 'string' or not jobName:find('%S')
        or #jobName > 64 or jobName:find('%z')) then return {} end
    local access = src ~= nil and GetMdtAccess(src) or nil
    local interfaceId = access and access.interfaceId or nil
    local rows = MySQL.query.await([[
        SELECT
            w.reportid,
            w.citizenid,
            w.felonies,
            w.misdemeanors,
            w.infractions,
            w.expirydate,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')) AS firstname,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname')) AS lastname
        FROM mdt_reports_warrants w
        LEFT JOIN players p ON p.citizenid COLLATE utf8mb4_general_ci = w.citizenid COLLATE utf8mb4_general_ci
        WHERE w.expirydate >= NOW()
        ORDER BY w.expirydate ASC, w.reportid ASC, w.citizenid ASC
    ]])

    if type(rows) ~= 'table' then return {} end
    if src ~= nil and (not canReadWarrantData(src)
        or not CheckPermission(src, 'warrants_view')) then return {} end
    for _, row in ipairs(rows) do
        local id = type(row) == 'table' and tonumber(row.reportid) or nil
        if not id or id ~= id or id == math.huge or id == -math.huge
            or id <= 0 or id % 1 ~= 0 or type(row.citizenid) ~= 'string'
            or not row.citizenid:find('%S') or #row.citizenid > 64
            or row.citizenid:find('%z') then return {} end
    end
    local results = {}
    for _, row in ipairs(rows) do
        if type(row) == 'table' and (src == nil or (canReadWarrantData(src)
            and CheckPermission(src, 'warrants_view')
            and type(CanReadMdtReport) == 'function'
            and CanReadMdtReport(src, row.reportid))) then
        local first = type(row.firstname) == 'string' and row.firstname or ''
        local last = type(row.lastname) == 'string' and row.lastname or ''
        local name = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+
        if name == '' then
            local fallback = ps.getPlayerNameByIdentifier(row.citizenid)
            name = type(fallback) == 'string' and fallback ~= '' and fallback or 'Unknown'
        end
        results[#results + 1] = {
            reportid = row.reportid,
            citizenid = row.citizenid,
            name = name,
            felonies = tonumber(row.felonies) or 0,
            misdemeanors = tonumber(row.misdemeanors) or 0,
            infractions = tonumber(row.infractions) or 0,
            expirydate = row.expirydate,
        }
        end
    end

    -- SQL and name resolution can yield while the source changes character or job.
    if src ~= nil and (not canReadWarrantData(src)
        or type(CanReadMdtReport) ~= 'function'
        or not CheckPermission(src, 'warrants_view')
        or ps.getIdentifier(src) ~= citizenid or ps.getJobName(src) ~= jobName
        or (GetMdtAccess(src) or {}).interfaceId ~= interfaceId) then return {} end
    for _, warrant in ipairs(results) do
        if src ~= nil and (not canReadWarrantData(src)
            or not CheckPermission(src, 'warrants_view')
            or not CanReadMdtReport(src, warrant.reportid)) then return {} end
    end
    if src ~= nil and (ps.getIdentifier(src) ~= citizenid
        or ps.getJobName(src) ~= jobName
        or (GetMdtAccess(src) or {}).interfaceId ~= interfaceId) then return {} end
    return results
end

-- Send actual records only to their authorized server-side audience. Client
-- visibility checks cannot protect a payload already broadcast to everyone.
function BroadcastActiveWarrants()
    for _, playerSource in pairs(GetPlayers()) do
        local target = tonumber(playerSource)
        if target and target > 0 and target % 1 == 0
            and canReadWarrantData(target)
            and CheckPermission(target, 'warrants_view') then
            TriggerClientEvent(resourceName .. ':client:updateActiveWarrants', target, GetActiveWarrantsData(target))
        end
    end
end

ps.registerCallback(resourceName .. ':server:getActiveWarrants', function(source)
    local src = source
    if not canReadWarrantData(src) then return {} end
    if not CheckPermission(src, 'warrants_view') then return {} end
    return GetActiveWarrantsData(src)
end)

ps.registerCallback(resourceName .. ':server:issueWarrant', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if type(requesterCitizenId) ~= 'string' or not requesterCitizenId:find('%S')
        or #requesterCitizenId > 64 or requesterCitizenId:find('%z')
        or type(requesterJob) ~= 'string' or not requesterJob:find('%S')
        or #requesterJob > 64 or requesterJob:find('%z') then
        return { success = false, error = 'Unauthorized' }
    end
    if IsMdtAttorneyGeneral(src) then return { success = false, error = 'Prosecution access cannot issue warrants' } end
    if not CheckPermission(src, 'warrants_issue') then
        return { success = false, error = 'Insufficient permissions' }
    end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid warrant request' } end
    local reportId = tonumber(data.reportId)
    local citizenid = data.citizenid
    local expiryValue = validateExpiry(data.expirydate)
    local expiryDate = getExpiryDate(expiryValue)
    if data.expirydate ~= nil and not expiryDate then
        return { success = false, error = 'Invalid warrant expiry' }
    end
    if expiryDate and expiryDate <= os.date('%Y-%m-%d %H:%M:%S') then
        return { success = false, error = 'Warrant expiry must be in the future' }
    end
    if data.expirydate ~= nil and not expiryDate then
        return { success = false, error = 'Invalid warrant expiry' }
    end
    if not expiryDate then
        local defaultDays = (Config and Config.Warrants and Config.Warrants.DefaultExpiryDays) or 7
        defaultDays = tonumber(defaultDays)
        if not defaultDays or defaultDays ~= defaultDays or defaultDays == math.huge
            or defaultDays == -math.huge or defaultDays < 1
            or defaultDays > 3650 then defaultDays = 7 end
        expiryDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + (defaultDays * 24 * 60 * 60))
    end

    -- A newly issued warrant must have a future expiration when supplied as a timestamp.
    local numericExpiry = tonumber(expiryValue)
    if numericExpiry then
        local seconds = numericExpiry > 100000000000 and numericExpiry / 1000 or numericExpiry
        if seconds <= os.time() then
            return { success = false, error = 'Warrant expiry must be in the future' }
        end
    end

    if not reportId or reportId ~= reportId or reportId == math.huge
        or reportId == -math.huge or reportId <= 0 or reportId % 1 ~= 0
        or type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then
        return { success = false, error = 'Missing required fields' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue') then
        return { success = false, error = 'Unauthorized warrant role' }
    end
    if not warrantReportExists(reportId) then
        return { success = false, error = 'Report not found' }
    end
    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report access denied' }
    end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }
    )
    if owner and owner ~= ps.getJobName(src) then
        return { success = false, error = 'Report belongs to another agency' }
    end

    -- Database lookups yield; confirm the issuer still holds the same role and report access.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or not CanReadMdtReport(src, reportId)
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob
        or (owner and owner ~= ps.getJobName(src)) then
        return { success = false, error = 'Warrant authorization changed' }
    end

    -- One warrant per report: refuse if this report already has any active
    -- (non-expired) warrant, regardless of which subject it targets.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or type(CanReadMdtReport) ~= 'function'
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local activeForReport = MySQL.single.await('SELECT 1 AS x FROM mdt_reports_warrants WHERE reportid = ? AND expirydate >= NOW() LIMIT 1', { reportId })
    if activeForReport then
        return { success = false, error = 'This report already has an active warrant' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local existing = MySQL.single.await('SELECT reportid FROM mdt_reports_warrants WHERE reportid = ? AND citizenid = ?', { reportId, citizenid })
    if existing and existing.reportid then
        return { success = false, error = 'An active warrant already exists for this subject on this report' }
    else
        if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
            or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
            or not CanReadMdtReport(src, reportId) then
            return { success = false, error = 'Warrant authorization changed' }
        end
        local inserted = MySQL.insert.await([[
            INSERT INTO mdt_reports_warrants (reportid, citizenid, felonies, misdemeanors, infractions, expirydate)
            SELECT r.id, ?, 0, 0, 0, ?
            FROM mdt_reports r WHERE r.id = ?
              AND NOT EXISTS (
                  SELECT 1 FROM mdt_reports_restrictions o
                  WHERE o.reportid = r.id AND o.type = 'owner' AND o.identifier <> ?
              )
              AND NOT EXISTS (
                  SELECT 1 FROM mdt_reports_warrants existing
                  WHERE existing.reportid = r.id AND existing.expirydate >= NOW()
              )
        ]], { citizenid, expiryDate, reportId, ps.getJobName(src) })
        if type(inserted) ~= 'number' or inserted ~= inserted
            or inserted == math.huge or inserted == -math.huge or inserted <= 0 then
            return { success = false, error = 'Report not found or inaccessible' }
        end
    end

    if ps.auditLog then
        ps.auditLog(src, 'warrant_issued', 'warrant', reportId, {
            citizenid = citizenid,
            expirydate = expiryDate
        })
    end

    BroadcastActiveWarrants()
    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:closeWarrant', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if type(requesterCitizenId) ~= 'string' or not requesterCitizenId:find('%S')
        or #requesterCitizenId > 64 or requesterCitizenId:find('%z')
        or type(requesterJob) ~= 'string' or not requesterJob:find('%S')
        or #requesterJob > 64 or requesterJob:find('%z') then
        return { success = false, error = 'Unauthorized' }
    end
    if IsMdtAttorneyGeneral(src) then return { success = false, error = 'Prosecution access cannot close warrants' } end
    if not CheckPermission(src, 'warrants_close') then
        return { success = false, error = 'Insufficient permissions' }
    end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid warrant request' } end
    local reportId = tonumber(data.reportId)
    local citizenid = data.citizenid
    if not reportId or reportId ~= reportId or reportId == math.huge
        or reportId == -math.huge or reportId <= 0 or reportId % 1 ~= 0
        or type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then
        return { success = false, error = 'Missing required fields' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close') then
        return { success = false, error = 'Unauthorized warrant role' }
    end
    if not warrantReportExists(reportId) then
        return { success = false, error = 'Report not found' }
    end
    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report access denied' }
    end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }
    )
    if owner and owner ~= ps.getJobName(src) then
        return { success = false, error = 'Report belongs to another agency' }
    end

    -- Do not close a warrant after the requester's authority has changed.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close')
        or not CanReadMdtReport(src, reportId)
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob
        or (owner and owner ~= ps.getJobName(src)) then
        return { success = false, error = 'Warrant authorization changed' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local updated = MySQL.update.await([[
        UPDATE mdt_reports_warrants
        SET expirydate = NOW()
        WHERE reportid = ? AND citizenid = ? AND expirydate > NOW()
          AND NOT EXISTS (SELECT 1 FROM mdt_reports_restrictions o
              WHERE o.reportid = ? AND o.type = 'owner' AND o.identifier <> ?)
    ]], { reportId, citizenid, reportId, ps.getJobName(src) })

    if type(updated) == 'number' and updated ~= math.huge
        and updated ~= -math.huge and updated > 0 then
        -- Closing the warrant also removes any hearing it placed on the calendar.
        if RemoveWarrantHearingsForReport then
            RemoveWarrantHearingsForReport(reportId)
        end
        if ps.auditLog then
            ps.auditLog(src, 'warrant_closed', 'warrant', reportId, {
                citizenid = citizenid
            })
        end
        BroadcastActiveWarrants()
        return { success = true }
    end

    return { success = false, error = 'Warrant not found' }
end)
) then
            local year, month, day, hour, minute, second = trimmed:match('^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)
    end
    return nil
end

local function toTimestamp(value)
    local numeric = tonumber(value)
    if not numeric or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then return nil end
    if numeric > 100000000000 then return math.floor(numeric / 1000) end
    return numeric
end

local function getExpiryDate(value)
    local ts = toTimestamp(value)
    if ts then return os.date('%Y-%m-%d %H:%M:%S', ts) end
    if type(value) == 'string' and value:match('^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$') then
        return value
    end
    return nil
end

-- Exposed as a global so the dashboard aggregate (server/backend/dashboard.lua)
-- can reuse it without a second round-trip.
function GetActiveWarrantsData(src)
    if src ~= nil and (not canReadWarrantData(src) or not CheckPermission(src, 'warrants_view')
        or type(CanReadMdtReport) ~= 'function') then
        return {}
    end
    local citizenid = src ~= nil and ps.getIdentifier(src) or nil
    local jobName = src ~= nil and ps.getJobName(src) or nil
    if src ~= nil and (type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z')
        or type(jobName) ~= 'string' or not jobName:find('%S')
        or #jobName > 64 or jobName:find('%z')) then return {} end
    local access = src ~= nil and GetMdtAccess(src) or nil
    local interfaceId = access and access.interfaceId or nil
    local rows = MySQL.query.await([[
        SELECT
            w.reportid,
            w.citizenid,
            w.felonies,
            w.misdemeanors,
            w.infractions,
            w.expirydate,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')) AS firstname,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname')) AS lastname
        FROM mdt_reports_warrants w
        LEFT JOIN players p ON p.citizenid COLLATE utf8mb4_general_ci = w.citizenid COLLATE utf8mb4_general_ci
        WHERE w.expirydate >= NOW()
        ORDER BY w.expirydate ASC, w.reportid ASC, w.citizenid ASC
    ]])

    if type(rows) ~= 'table' then return {} end
    if src ~= nil and (not canReadWarrantData(src)
        or not CheckPermission(src, 'warrants_view')) then return {} end
    for _, row in ipairs(rows) do
        local id = type(row) == 'table' and tonumber(row.reportid) or nil
        if not id or id ~= id or id == math.huge or id == -math.huge
            or id <= 0 or id % 1 ~= 0 or type(row.citizenid) ~= 'string'
            or not row.citizenid:find('%S') or #row.citizenid > 64
            or row.citizenid:find('%z') then return {} end
    end
    local results = {}
    for _, row in ipairs(rows) do
        if type(row) == 'table' and (src == nil or (type(CanReadMdtReport) == 'function' and CanReadMdtReport(src, row.reportid))) then
        local first = type(row.firstname) == 'string' and row.firstname or ''
        local last = type(row.lastname) == 'string' and row.lastname or ''
        local name = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+
        if name == '' then
            local fallback = ps.getPlayerNameByIdentifier(row.citizenid)
            name = type(fallback) == 'string' and fallback ~= '' and fallback or 'Unknown'
        end
        results[#results + 1] = {
            reportid = row.reportid,
            citizenid = row.citizenid,
            name = name,
            felonies = tonumber(row.felonies) or 0,
            misdemeanors = tonumber(row.misdemeanors) or 0,
            infractions = tonumber(row.infractions) or 0,
            expirydate = row.expirydate,
        }
        end
    end

    -- SQL and name resolution can yield while the source changes character or job.
    if src ~= nil and (not canReadWarrantData(src)
        or type(CanReadMdtReport) ~= 'function'
        or not CheckPermission(src, 'warrants_view')
        or ps.getIdentifier(src) ~= citizenid or ps.getJobName(src) ~= jobName
        or (GetMdtAccess(src) or {}).interfaceId ~= interfaceId) then return {} end
    return results
end

-- Send actual records only to their authorized server-side audience. Client
-- visibility checks cannot protect a payload already broadcast to everyone.
function BroadcastActiveWarrants()
    for _, playerSource in pairs(GetPlayers()) do
        local target = tonumber(playerSource)
        if target and target > 0 and target % 1 == 0
            and canReadWarrantData(target)
            and CheckPermission(target, 'warrants_view') then
            TriggerClientEvent(resourceName .. ':client:updateActiveWarrants', target, GetActiveWarrantsData(target))
        end
    end
end

ps.registerCallback(resourceName .. ':server:getActiveWarrants', function(source)
    local src = source
    if not canReadWarrantData(src) then return {} end
    if not CheckPermission(src, 'warrants_view') then return {} end
    return GetActiveWarrantsData(src)
end)

ps.registerCallback(resourceName .. ':server:issueWarrant', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if type(requesterCitizenId) ~= 'string' or not requesterCitizenId:find('%S')
        or #requesterCitizenId > 64 or requesterCitizenId:find('%z')
        or type(requesterJob) ~= 'string' or not requesterJob:find('%S')
        or #requesterJob > 64 or requesterJob:find('%z') then
        return { success = false, error = 'Unauthorized' }
    end
    if IsMdtAttorneyGeneral(src) then return { success = false, error = 'Prosecution access cannot issue warrants' } end
    if not CheckPermission(src, 'warrants_issue') then
        return { success = false, error = 'Insufficient permissions' }
    end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid warrant request' } end
    local reportId = tonumber(data.reportId)
    local citizenid = data.citizenid
    local expiryValue = validateExpiry(data.expirydate)
    local expiryDate = getExpiryDate(expiryValue)
    if data.expirydate ~= nil and not expiryDate then
        return { success = false, error = 'Invalid warrant expiry' }
    end
    if expiryDate and expiryDate <= os.date('%Y-%m-%d %H:%M:%S') then
        return { success = false, error = 'Warrant expiry must be in the future' }
    end
    if data.expirydate ~= nil and not expiryDate then
        return { success = false, error = 'Invalid warrant expiry' }
    end
    if not expiryDate then
        local defaultDays = (Config and Config.Warrants and Config.Warrants.DefaultExpiryDays) or 7
        defaultDays = tonumber(defaultDays)
        if not defaultDays or defaultDays ~= defaultDays or defaultDays == math.huge
            or defaultDays == -math.huge or defaultDays < 1
            or defaultDays > 3650 then defaultDays = 7 end
        expiryDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + (defaultDays * 24 * 60 * 60))
    end

    -- A newly issued warrant must have a future expiration when supplied as a timestamp.
    local numericExpiry = tonumber(expiryValue)
    if numericExpiry then
        local seconds = numericExpiry > 100000000000 and numericExpiry / 1000 or numericExpiry
        if seconds <= os.time() then
            return { success = false, error = 'Warrant expiry must be in the future' }
        end
    end

    if not reportId or reportId ~= reportId or reportId == math.huge
        or reportId == -math.huge or reportId <= 0 or reportId % 1 ~= 0
        or type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then
        return { success = false, error = 'Missing required fields' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue') then
        return { success = false, error = 'Unauthorized warrant role' }
    end
    if not warrantReportExists(reportId) then
        return { success = false, error = 'Report not found' }
    end
    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report access denied' }
    end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }
    )
    if owner and owner ~= ps.getJobName(src) then
        return { success = false, error = 'Report belongs to another agency' }
    end

    -- Database lookups yield; confirm the issuer still holds the same role and report access.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or not CanReadMdtReport(src, reportId)
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob
        or (owner and owner ~= ps.getJobName(src)) then
        return { success = false, error = 'Warrant authorization changed' }
    end

    -- One warrant per report: refuse if this report already has any active
    -- (non-expired) warrant, regardless of which subject it targets.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or type(CanReadMdtReport) ~= 'function'
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local activeForReport = MySQL.single.await('SELECT 1 AS x FROM mdt_reports_warrants WHERE reportid = ? AND expirydate >= NOW() LIMIT 1', { reportId })
    if activeForReport then
        return { success = false, error = 'This report already has an active warrant' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local existing = MySQL.single.await('SELECT reportid FROM mdt_reports_warrants WHERE reportid = ? AND citizenid = ?', { reportId, citizenid })
    if existing and existing.reportid then
        return { success = false, error = 'An active warrant already exists for this subject on this report' }
    else
        if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
            or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
            or not CanReadMdtReport(src, reportId) then
            return { success = false, error = 'Warrant authorization changed' }
        end
        local inserted = MySQL.insert.await([[
            INSERT INTO mdt_reports_warrants (reportid, citizenid, felonies, misdemeanors, infractions, expirydate)
            SELECT r.id, ?, 0, 0, 0, ?
            FROM mdt_reports r WHERE r.id = ?
              AND NOT EXISTS (
                  SELECT 1 FROM mdt_reports_restrictions o
                  WHERE o.reportid = r.id AND o.type = 'owner' AND o.identifier <> ?
              )
              AND NOT EXISTS (
                  SELECT 1 FROM mdt_reports_warrants existing
                  WHERE existing.reportid = r.id AND existing.expirydate >= NOW()
              )
        ]], { citizenid, expiryDate, reportId, ps.getJobName(src) })
        if type(inserted) ~= 'number' or inserted ~= inserted
            or inserted == math.huge or inserted == -math.huge or inserted <= 0 then
            return { success = false, error = 'Report not found or inaccessible' }
        end
    end

    if ps.auditLog then
        ps.auditLog(src, 'warrant_issued', 'warrant', reportId, {
            citizenid = citizenid,
            expirydate = expiryDate
        })
    end

    BroadcastActiveWarrants()
    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:closeWarrant', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if type(requesterCitizenId) ~= 'string' or not requesterCitizenId:find('%S')
        or #requesterCitizenId > 64 or requesterCitizenId:find('%z')
        or type(requesterJob) ~= 'string' or not requesterJob:find('%S')
        or #requesterJob > 64 or requesterJob:find('%z') then
        return { success = false, error = 'Unauthorized' }
    end
    if IsMdtAttorneyGeneral(src) then return { success = false, error = 'Prosecution access cannot close warrants' } end
    if not CheckPermission(src, 'warrants_close') then
        return { success = false, error = 'Insufficient permissions' }
    end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid warrant request' } end
    local reportId = tonumber(data.reportId)
    local citizenid = data.citizenid
    if not reportId or reportId ~= reportId or reportId == math.huge
        or reportId == -math.huge or reportId <= 0 or reportId % 1 ~= 0
        or type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then
        return { success = false, error = 'Missing required fields' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close') then
        return { success = false, error = 'Unauthorized warrant role' }
    end
    if not warrantReportExists(reportId) then
        return { success = false, error = 'Report not found' }
    end
    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report access denied' }
    end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }
    )
    if owner and owner ~= ps.getJobName(src) then
        return { success = false, error = 'Report belongs to another agency' }
    end

    -- Do not close a warrant after the requester's authority has changed.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close')
        or not CanReadMdtReport(src, reportId)
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob
        or (owner and owner ~= ps.getJobName(src)) then
        return { success = false, error = 'Warrant authorization changed' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local updated = MySQL.update.await([[
        UPDATE mdt_reports_warrants
        SET expirydate = NOW()
        WHERE reportid = ? AND citizenid = ? AND expirydate > NOW()
          AND NOT EXISTS (SELECT 1 FROM mdt_reports_restrictions o
              WHERE o.reportid = ? AND o.type = 'owner' AND o.identifier <> ?)
    ]], { reportId, citizenid, reportId, ps.getJobName(src) })

    if type(updated) == 'number' and updated ~= math.huge
        and updated ~= -math.huge and updated > 0 then
        -- Closing the warrant also removes any hearing it placed on the calendar.
        if RemoveWarrantHearingsForReport then
            RemoveWarrantHearingsForReport(reportId)
        end
        if ps.auditLog then
            ps.auditLog(src, 'warrant_closed', 'warrant', reportId, {
                citizenid = citizenid
            })
        end
        BroadcastActiveWarrants()
        return { success = true }
    end

    return { success = false, error = 'Warrant not found' }
end)
)
            year, month, day = tonumber(year), tonumber(month), tonumber(day)
            hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)
            local leap = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
            local daysInMonth = ({31, leap and 29 or 28, 31, 30, 31, 30,
                31, 31, 30, 31, 30, 31})[month]
            if year >= 1970 and year <= 2100 and daysInMonth
                and day >= 1 and day <= daysInMonth
                and hour <= 23 and minute <= 59 and second <= 59 then
                return trimmed
            end
        end
    end
    return nil
end

local function toTimestamp(value)
    local numeric = tonumber(value)
    if not numeric or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then return nil end
    if numeric > 100000000000 then return math.floor(numeric / 1000) end
    return numeric
end

local function getExpiryDate(value)
    local ts = toTimestamp(value)
    if ts then return os.date('%Y-%m-%d %H:%M:%S', ts) end
    if type(value) == 'string' and value:match('^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$') then
        return value
    end
    return nil
end

-- Exposed as a global so the dashboard aggregate (server/backend/dashboard.lua)
-- can reuse it without a second round-trip.
function GetActiveWarrantsData(src)
    if src ~= nil and (not canReadWarrantData(src) or not CheckPermission(src, 'warrants_view')
        or type(CanReadMdtReport) ~= 'function') then
        return {}
    end
    local citizenid = src ~= nil and ps.getIdentifier(src) or nil
    local jobName = src ~= nil and ps.getJobName(src) or nil
    if src ~= nil and (type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z')
        or type(jobName) ~= 'string' or not jobName:find('%S')
        or #jobName > 64 or jobName:find('%z')) then return {} end
    local access = src ~= nil and GetMdtAccess(src) or nil
    local interfaceId = access and access.interfaceId or nil
    local rows = MySQL.query.await([[
        SELECT
            w.reportid,
            w.citizenid,
            w.felonies,
            w.misdemeanors,
            w.infractions,
            w.expirydate,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')) AS firstname,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname')) AS lastname
        FROM mdt_reports_warrants w
        LEFT JOIN players p ON p.citizenid COLLATE utf8mb4_general_ci = w.citizenid COLLATE utf8mb4_general_ci
        WHERE w.expirydate >= NOW()
        ORDER BY w.expirydate ASC, w.reportid ASC, w.citizenid ASC
    ]])

    if type(rows) ~= 'table' then return {} end
    if src ~= nil and (not canReadWarrantData(src)
        or not CheckPermission(src, 'warrants_view')) then return {} end
    for _, row in ipairs(rows) do
        local id = type(row) == 'table' and tonumber(row.reportid) or nil
        if not id or id ~= id or id == math.huge or id == -math.huge
            or id <= 0 or id % 1 ~= 0 or type(row.citizenid) ~= 'string'
            or not row.citizenid:find('%S') or #row.citizenid > 64
            or row.citizenid:find('%z') then return {} end
    end
    local results = {}
    for _, row in ipairs(rows) do
        if type(row) == 'table' and (src == nil or (type(CanReadMdtReport) == 'function' and CanReadMdtReport(src, row.reportid))) then
        local first = type(row.firstname) == 'string' and row.firstname or ''
        local last = type(row.lastname) == 'string' and row.lastname or ''
        local name = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+
        if name == '' then
            local fallback = ps.getPlayerNameByIdentifier(row.citizenid)
            name = type(fallback) == 'string' and fallback ~= '' and fallback or 'Unknown'
        end
        results[#results + 1] = {
            reportid = row.reportid,
            citizenid = row.citizenid,
            name = name,
            felonies = tonumber(row.felonies) or 0,
            misdemeanors = tonumber(row.misdemeanors) or 0,
            infractions = tonumber(row.infractions) or 0,
            expirydate = row.expirydate,
        }
        end
    end

    -- SQL and name resolution can yield while the source changes character or job.
    if src ~= nil and (not canReadWarrantData(src)
        or type(CanReadMdtReport) ~= 'function'
        or not CheckPermission(src, 'warrants_view')
        or ps.getIdentifier(src) ~= citizenid or ps.getJobName(src) ~= jobName
        or (GetMdtAccess(src) or {}).interfaceId ~= interfaceId) then return {} end
    return results
end

-- Send actual records only to their authorized server-side audience. Client
-- visibility checks cannot protect a payload already broadcast to everyone.
function BroadcastActiveWarrants()
    for _, playerSource in pairs(GetPlayers()) do
        local target = tonumber(playerSource)
        if target and target > 0 and target % 1 == 0
            and canReadWarrantData(target)
            and CheckPermission(target, 'warrants_view') then
            TriggerClientEvent(resourceName .. ':client:updateActiveWarrants', target, GetActiveWarrantsData(target))
        end
    end
end

ps.registerCallback(resourceName .. ':server:getActiveWarrants', function(source)
    local src = source
    if not canReadWarrantData(src) then return {} end
    if not CheckPermission(src, 'warrants_view') then return {} end
    return GetActiveWarrantsData(src)
end)

ps.registerCallback(resourceName .. ':server:issueWarrant', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if type(requesterCitizenId) ~= 'string' or not requesterCitizenId:find('%S')
        or #requesterCitizenId > 64 or requesterCitizenId:find('%z')
        or type(requesterJob) ~= 'string' or not requesterJob:find('%S')
        or #requesterJob > 64 or requesterJob:find('%z') then
        return { success = false, error = 'Unauthorized' }
    end
    if IsMdtAttorneyGeneral(src) then return { success = false, error = 'Prosecution access cannot issue warrants' } end
    if not CheckPermission(src, 'warrants_issue') then
        return { success = false, error = 'Insufficient permissions' }
    end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid warrant request' } end
    local reportId = tonumber(data.reportId)
    local citizenid = data.citizenid
    local expiryValue = validateExpiry(data.expirydate)
    local expiryDate = getExpiryDate(expiryValue)
    if data.expirydate ~= nil and not expiryDate then
        return { success = false, error = 'Invalid warrant expiry' }
    end
    if expiryDate and expiryDate <= os.date('%Y-%m-%d %H:%M:%S') then
        return { success = false, error = 'Warrant expiry must be in the future' }
    end
    if data.expirydate ~= nil and not expiryDate then
        return { success = false, error = 'Invalid warrant expiry' }
    end
    if not expiryDate then
        local defaultDays = (Config and Config.Warrants and Config.Warrants.DefaultExpiryDays) or 7
        defaultDays = tonumber(defaultDays)
        if not defaultDays or defaultDays ~= defaultDays or defaultDays == math.huge
            or defaultDays == -math.huge or defaultDays < 1
            or defaultDays > 3650 then defaultDays = 7 end
        expiryDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + (defaultDays * 24 * 60 * 60))
    end

    -- A newly issued warrant must have a future expiration when supplied as a timestamp.
    local numericExpiry = tonumber(expiryValue)
    if numericExpiry then
        local seconds = numericExpiry > 100000000000 and numericExpiry / 1000 or numericExpiry
        if seconds <= os.time() then
            return { success = false, error = 'Warrant expiry must be in the future' }
        end
    end

    if not reportId or reportId ~= reportId or reportId == math.huge
        or reportId == -math.huge or reportId <= 0 or reportId % 1 ~= 0
        or type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then
        return { success = false, error = 'Missing required fields' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue') then
        return { success = false, error = 'Unauthorized warrant role' }
    end
    if not warrantReportExists(reportId) then
        return { success = false, error = 'Report not found' }
    end
    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report access denied' }
    end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }
    )
    if owner and owner ~= ps.getJobName(src) then
        return { success = false, error = 'Report belongs to another agency' }
    end

    -- Database lookups yield; confirm the issuer still holds the same role and report access.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or not CanReadMdtReport(src, reportId)
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob
        or (owner and owner ~= ps.getJobName(src)) then
        return { success = false, error = 'Warrant authorization changed' }
    end

    -- One warrant per report: refuse if this report already has any active
    -- (non-expired) warrant, regardless of which subject it targets.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or type(CanReadMdtReport) ~= 'function'
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local activeForReport = MySQL.single.await('SELECT 1 AS x FROM mdt_reports_warrants WHERE reportid = ? AND expirydate >= NOW() LIMIT 1', { reportId })
    if activeForReport then
        return { success = false, error = 'This report already has an active warrant' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local existing = MySQL.single.await('SELECT reportid FROM mdt_reports_warrants WHERE reportid = ? AND citizenid = ?', { reportId, citizenid })
    if existing and existing.reportid then
        return { success = false, error = 'An active warrant already exists for this subject on this report' }
    else
        if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
            or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
            or not CanReadMdtReport(src, reportId) then
            return { success = false, error = 'Warrant authorization changed' }
        end
        local inserted = MySQL.insert.await([[
            INSERT INTO mdt_reports_warrants (reportid, citizenid, felonies, misdemeanors, infractions, expirydate)
            SELECT r.id, ?, 0, 0, 0, ?
            FROM mdt_reports r WHERE r.id = ?
              AND NOT EXISTS (
                  SELECT 1 FROM mdt_reports_restrictions o
                  WHERE o.reportid = r.id AND o.type = 'owner' AND o.identifier <> ?
              )
              AND NOT EXISTS (
                  SELECT 1 FROM mdt_reports_warrants existing
                  WHERE existing.reportid = r.id AND existing.expirydate >= NOW()
              )
        ]], { citizenid, expiryDate, reportId, ps.getJobName(src) })
        if type(inserted) ~= 'number' or inserted ~= inserted
            or inserted == math.huge or inserted == -math.huge or inserted <= 0 then
            return { success = false, error = 'Report not found or inaccessible' }
        end
    end

    if ps.auditLog then
        ps.auditLog(src, 'warrant_issued', 'warrant', reportId, {
            citizenid = citizenid,
            expirydate = expiryDate
        })
    end

    BroadcastActiveWarrants()
    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:closeWarrant', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if type(requesterCitizenId) ~= 'string' or not requesterCitizenId:find('%S')
        or #requesterCitizenId > 64 or requesterCitizenId:find('%z')
        or type(requesterJob) ~= 'string' or not requesterJob:find('%S')
        or #requesterJob > 64 or requesterJob:find('%z') then
        return { success = false, error = 'Unauthorized' }
    end
    if IsMdtAttorneyGeneral(src) then return { success = false, error = 'Prosecution access cannot close warrants' } end
    if not CheckPermission(src, 'warrants_close') then
        return { success = false, error = 'Insufficient permissions' }
    end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid warrant request' } end
    local reportId = tonumber(data.reportId)
    local citizenid = data.citizenid
    if not reportId or reportId ~= reportId or reportId == math.huge
        or reportId == -math.huge or reportId <= 0 or reportId % 1 ~= 0
        or type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then
        return { success = false, error = 'Missing required fields' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close') then
        return { success = false, error = 'Unauthorized warrant role' }
    end
    if not warrantReportExists(reportId) then
        return { success = false, error = 'Report not found' }
    end
    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report access denied' }
    end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }
    )
    if owner and owner ~= ps.getJobName(src) then
        return { success = false, error = 'Report belongs to another agency' }
    end

    -- Do not close a warrant after the requester's authority has changed.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close')
        or not CanReadMdtReport(src, reportId)
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob
        or (owner and owner ~= ps.getJobName(src)) then
        return { success = false, error = 'Warrant authorization changed' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local updated = MySQL.update.await([[
        UPDATE mdt_reports_warrants
        SET expirydate = NOW()
        WHERE reportid = ? AND citizenid = ? AND expirydate > NOW()
          AND NOT EXISTS (SELECT 1 FROM mdt_reports_restrictions o
              WHERE o.reportid = ? AND o.type = 'owner' AND o.identifier <> ?)
    ]], { reportId, citizenid, reportId, ps.getJobName(src) })

    if type(updated) == 'number' and updated ~= math.huge
        and updated ~= -math.huge and updated > 0 then
        -- Closing the warrant also removes any hearing it placed on the calendar.
        if RemoveWarrantHearingsForReport then
            RemoveWarrantHearingsForReport(reportId)
        end
        if ps.auditLog then
            ps.auditLog(src, 'warrant_closed', 'warrant', reportId, {
                citizenid = citizenid
            })
        end
        BroadcastActiveWarrants()
        return { success = true }
    end

    return { success = false, error = 'Warrant not found' }
end)
)
        and validateExpiry(value) == value then
        return value
    end
    return nil
end

-- Exposed as a global so the dashboard aggregate (server/backend/dashboard.lua)
-- can reuse it without a second round-trip.
function GetActiveWarrantsData(src)
    if src ~= nil and (not canReadWarrantData(src) or not CheckPermission(src, 'warrants_view')
        or type(CanReadMdtReport) ~= 'function') then
        return {}
    end
    local citizenid = src ~= nil and ps.getIdentifier(src) or nil
    local jobName = src ~= nil and ps.getJobName(src) or nil
    if src ~= nil and (type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z')
        or type(jobName) ~= 'string' or not jobName:find('%S')
        or #jobName > 64 or jobName:find('%z')) then return {} end
    local access = src ~= nil and GetMdtAccess(src) or nil
    local interfaceId = access and access.interfaceId or nil
    local rows = MySQL.query.await([[
        SELECT
            w.reportid,
            w.citizenid,
            w.felonies,
            w.misdemeanors,
            w.infractions,
            w.expirydate,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')) AS firstname,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname')) AS lastname
        FROM mdt_reports_warrants w
        LEFT JOIN players p ON p.citizenid COLLATE utf8mb4_general_ci = w.citizenid COLLATE utf8mb4_general_ci
        WHERE w.expirydate >= NOW()
        ORDER BY w.expirydate ASC, w.reportid ASC, w.citizenid ASC
    ]])

    if type(rows) ~= 'table' then return {} end
    if src ~= nil and (not canReadWarrantData(src)
        or not CheckPermission(src, 'warrants_view')) then return {} end
    for _, row in ipairs(rows) do
        local id = type(row) == 'table' and tonumber(row.reportid) or nil
        if not id or id ~= id or id == math.huge or id == -math.huge
            or id <= 0 or id % 1 ~= 0 or type(row.citizenid) ~= 'string'
            or not row.citizenid:find('%S') or #row.citizenid > 64
            or row.citizenid:find('%z') then return {} end
    end
    local results = {}
    for _, row in ipairs(rows) do
        if type(row) == 'table' and (src == nil or (type(CanReadMdtReport) == 'function' and CanReadMdtReport(src, row.reportid))) then
        local first = type(row.firstname) == 'string' and row.firstname or ''
        local last = type(row.lastname) == 'string' and row.lastname or ''
        local name = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+
        if name == '' then
            local fallback = ps.getPlayerNameByIdentifier(row.citizenid)
            name = type(fallback) == 'string' and fallback ~= '' and fallback or 'Unknown'
        end
        results[#results + 1] = {
            reportid = row.reportid,
            citizenid = row.citizenid,
            name = name,
            felonies = tonumber(row.felonies) or 0,
            misdemeanors = tonumber(row.misdemeanors) or 0,
            infractions = tonumber(row.infractions) or 0,
            expirydate = row.expirydate,
        }
        end
    end

    -- SQL and name resolution can yield while the source changes character or job.
    if src ~= nil and (not canReadWarrantData(src)
        or type(CanReadMdtReport) ~= 'function'
        or not CheckPermission(src, 'warrants_view')
        or ps.getIdentifier(src) ~= citizenid or ps.getJobName(src) ~= jobName
        or (GetMdtAccess(src) or {}).interfaceId ~= interfaceId) then return {} end
    return results
end

-- Send actual records only to their authorized server-side audience. Client
-- visibility checks cannot protect a payload already broadcast to everyone.
function BroadcastActiveWarrants()
    for _, playerSource in pairs(GetPlayers()) do
        local target = tonumber(playerSource)
        if target and target > 0 and target % 1 == 0
            and canReadWarrantData(target)
            and CheckPermission(target, 'warrants_view') then
            TriggerClientEvent(resourceName .. ':client:updateActiveWarrants', target, GetActiveWarrantsData(target))
        end
    end
end

ps.registerCallback(resourceName .. ':server:getActiveWarrants', function(source)
    local src = source
    if not canReadWarrantData(src) then return {} end
    if not CheckPermission(src, 'warrants_view') then return {} end
    return GetActiveWarrantsData(src)
end)

ps.registerCallback(resourceName .. ':server:issueWarrant', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if type(requesterCitizenId) ~= 'string' or not requesterCitizenId:find('%S')
        or #requesterCitizenId > 64 or requesterCitizenId:find('%z')
        or type(requesterJob) ~= 'string' or not requesterJob:find('%S')
        or #requesterJob > 64 or requesterJob:find('%z') then
        return { success = false, error = 'Unauthorized' }
    end
    if IsMdtAttorneyGeneral(src) then return { success = false, error = 'Prosecution access cannot issue warrants' } end
    if not CheckPermission(src, 'warrants_issue') then
        return { success = false, error = 'Insufficient permissions' }
    end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid warrant request' } end
    local reportId = tonumber(data.reportId)
    local citizenid = data.citizenid
    local expiryValue = validateExpiry(data.expirydate)
    local expiryDate = getExpiryDate(expiryValue)
    if data.expirydate ~= nil and not expiryDate then
        return { success = false, error = 'Invalid warrant expiry' }
    end
    if expiryDate and expiryDate <= os.date('%Y-%m-%d %H:%M:%S') then
        return { success = false, error = 'Warrant expiry must be in the future' }
    end
    if data.expirydate ~= nil and not expiryDate then
        return { success = false, error = 'Invalid warrant expiry' }
    end
    if not expiryDate then
        local defaultDays = (Config and Config.Warrants and Config.Warrants.DefaultExpiryDays) or 7
        defaultDays = tonumber(defaultDays)
        if not defaultDays or defaultDays ~= defaultDays or defaultDays == math.huge
            or defaultDays == -math.huge or defaultDays < 1
            or defaultDays > 3650 then defaultDays = 7 end
        expiryDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + (defaultDays * 24 * 60 * 60))
    end

    -- A newly issued warrant must have a future expiration when supplied as a timestamp.
    local numericExpiry = tonumber(expiryValue)
    if numericExpiry then
        local seconds = numericExpiry > 100000000000 and numericExpiry / 1000 or numericExpiry
        if seconds <= os.time() then
            return { success = false, error = 'Warrant expiry must be in the future' }
        end
    end

    if not reportId or reportId ~= reportId or reportId == math.huge
        or reportId == -math.huge or reportId <= 0 or reportId % 1 ~= 0
        or type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then
        return { success = false, error = 'Missing required fields' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue') then
        return { success = false, error = 'Unauthorized warrant role' }
    end
    if not warrantReportExists(reportId) then
        return { success = false, error = 'Report not found' }
    end
    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report access denied' }
    end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }
    )
    if owner and owner ~= ps.getJobName(src) then
        return { success = false, error = 'Report belongs to another agency' }
    end

    -- Database lookups yield; confirm the issuer still holds the same role and report access.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or not CanReadMdtReport(src, reportId)
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob
        or (owner and owner ~= ps.getJobName(src)) then
        return { success = false, error = 'Warrant authorization changed' }
    end

    -- One warrant per report: refuse if this report already has any active
    -- (non-expired) warrant, regardless of which subject it targets.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or type(CanReadMdtReport) ~= 'function'
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local activeForReport = MySQL.single.await('SELECT 1 AS x FROM mdt_reports_warrants WHERE reportid = ? AND expirydate >= NOW() LIMIT 1', { reportId })
    if activeForReport then
        return { success = false, error = 'This report already has an active warrant' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local existing = MySQL.single.await('SELECT reportid FROM mdt_reports_warrants WHERE reportid = ? AND citizenid = ?', { reportId, citizenid })
    if existing and existing.reportid then
        return { success = false, error = 'An active warrant already exists for this subject on this report' }
    else
        if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
            or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
            or not CanReadMdtReport(src, reportId) then
            return { success = false, error = 'Warrant authorization changed' }
        end
        local inserted = MySQL.insert.await([[
            INSERT INTO mdt_reports_warrants (reportid, citizenid, felonies, misdemeanors, infractions, expirydate)
            SELECT r.id, ?, 0, 0, 0, ?
            FROM mdt_reports r WHERE r.id = ?
              AND NOT EXISTS (
                  SELECT 1 FROM mdt_reports_restrictions o
                  WHERE o.reportid = r.id AND o.type = 'owner' AND o.identifier <> ?
              )
              AND NOT EXISTS (
                  SELECT 1 FROM mdt_reports_warrants existing
                  WHERE existing.reportid = r.id AND existing.expirydate >= NOW()
              )
        ]], { citizenid, expiryDate, reportId, ps.getJobName(src) })
        if type(inserted) ~= 'number' or inserted ~= inserted
            or inserted == math.huge or inserted == -math.huge or inserted <= 0 then
            return { success = false, error = 'Report not found or inaccessible' }
        end
    end

    if ps.auditLog then
        ps.auditLog(src, 'warrant_issued', 'warrant', reportId, {
            citizenid = citizenid,
            expirydate = expiryDate
        })
    end

    BroadcastActiveWarrants()
    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:closeWarrant', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if type(requesterCitizenId) ~= 'string' or not requesterCitizenId:find('%S')
        or #requesterCitizenId > 64 or requesterCitizenId:find('%z')
        or type(requesterJob) ~= 'string' or not requesterJob:find('%S')
        or #requesterJob > 64 or requesterJob:find('%z') then
        return { success = false, error = 'Unauthorized' }
    end
    if IsMdtAttorneyGeneral(src) then return { success = false, error = 'Prosecution access cannot close warrants' } end
    if not CheckPermission(src, 'warrants_close') then
        return { success = false, error = 'Insufficient permissions' }
    end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid warrant request' } end
    local reportId = tonumber(data.reportId)
    local citizenid = data.citizenid
    if not reportId or reportId ~= reportId or reportId == math.huge
        or reportId == -math.huge or reportId <= 0 or reportId % 1 ~= 0
        or type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then
        return { success = false, error = 'Missing required fields' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close') then
        return { success = false, error = 'Unauthorized warrant role' }
    end
    if not warrantReportExists(reportId) then
        return { success = false, error = 'Report not found' }
    end
    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report access denied' }
    end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }
    )
    if owner and owner ~= ps.getJobName(src) then
        return { success = false, error = 'Report belongs to another agency' }
    end

    -- Do not close a warrant after the requester's authority has changed.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close')
        or not CanReadMdtReport(src, reportId)
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob
        or (owner and owner ~= ps.getJobName(src)) then
        return { success = false, error = 'Warrant authorization changed' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local updated = MySQL.update.await([[
        UPDATE mdt_reports_warrants
        SET expirydate = NOW()
        WHERE reportid = ? AND citizenid = ? AND expirydate > NOW()
          AND NOT EXISTS (SELECT 1 FROM mdt_reports_restrictions o
              WHERE o.reportid = ? AND o.type = 'owner' AND o.identifier <> ?)
    ]], { reportId, citizenid, reportId, ps.getJobName(src) })

    if type(updated) == 'number' and updated ~= math.huge
        and updated ~= -math.huge and updated > 0 then
        -- Closing the warrant also removes any hearing it placed on the calendar.
        if RemoveWarrantHearingsForReport then
            RemoveWarrantHearingsForReport(reportId)
        end
        if ps.auditLog then
            ps.auditLog(src, 'warrant_closed', 'warrant', reportId, {
                citizenid = citizenid
            })
        end
        BroadcastActiveWarrants()
        return { success = true }
    end

    return { success = false, error = 'Warrant not found' }
end)
) then
            local year, month, day, hour, minute, second = trimmed:match('^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)
    end
    return nil
end

local function toTimestamp(value)
    local numeric = tonumber(value)
    if not numeric or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then return nil end
    if numeric > 100000000000 then return math.floor(numeric / 1000) end
    return numeric
end

local function getExpiryDate(value)
    local ts = toTimestamp(value)
    if ts then return os.date('%Y-%m-%d %H:%M:%S', ts) end
    if type(value) == 'string' and value:match('^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$') then
        return value
    end
    return nil
end

-- Exposed as a global so the dashboard aggregate (server/backend/dashboard.lua)
-- can reuse it without a second round-trip.
function GetActiveWarrantsData(src)
    if src ~= nil and (not canReadWarrantData(src) or not CheckPermission(src, 'warrants_view')
        or type(CanReadMdtReport) ~= 'function') then
        return {}
    end
    local citizenid = src ~= nil and ps.getIdentifier(src) or nil
    local jobName = src ~= nil and ps.getJobName(src) or nil
    if src ~= nil and (type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z')
        or type(jobName) ~= 'string' or not jobName:find('%S')
        or #jobName > 64 or jobName:find('%z')) then return {} end
    local access = src ~= nil and GetMdtAccess(src) or nil
    local interfaceId = access and access.interfaceId or nil
    local rows = MySQL.query.await([[
        SELECT
            w.reportid,
            w.citizenid,
            w.felonies,
            w.misdemeanors,
            w.infractions,
            w.expirydate,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')) AS firstname,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname')) AS lastname
        FROM mdt_reports_warrants w
        LEFT JOIN players p ON p.citizenid COLLATE utf8mb4_general_ci = w.citizenid COLLATE utf8mb4_general_ci
        WHERE w.expirydate >= NOW()
        ORDER BY w.expirydate ASC, w.reportid ASC, w.citizenid ASC
    ]])

    if type(rows) ~= 'table' then return {} end
    if src ~= nil and (not canReadWarrantData(src)
        or not CheckPermission(src, 'warrants_view')) then return {} end
    for _, row in ipairs(rows) do
        local id = type(row) == 'table' and tonumber(row.reportid) or nil
        if not id or id ~= id or id == math.huge or id == -math.huge
            or id <= 0 or id % 1 ~= 0 or type(row.citizenid) ~= 'string'
            or not row.citizenid:find('%S') or #row.citizenid > 64
            or row.citizenid:find('%z') then return {} end
    end
    local results = {}
    for _, row in ipairs(rows) do
        if type(row) == 'table' and (src == nil or (type(CanReadMdtReport) == 'function' and CanReadMdtReport(src, row.reportid))) then
        local first = type(row.firstname) == 'string' and row.firstname or ''
        local last = type(row.lastname) == 'string' and row.lastname or ''
        local name = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+
        if name == '' then
            local fallback = ps.getPlayerNameByIdentifier(row.citizenid)
            name = type(fallback) == 'string' and fallback ~= '' and fallback or 'Unknown'
        end
        results[#results + 1] = {
            reportid = row.reportid,
            citizenid = row.citizenid,
            name = name,
            felonies = tonumber(row.felonies) or 0,
            misdemeanors = tonumber(row.misdemeanors) or 0,
            infractions = tonumber(row.infractions) or 0,
            expirydate = row.expirydate,
        }
        end
    end

    -- SQL and name resolution can yield while the source changes character or job.
    if src ~= nil and (not canReadWarrantData(src)
        or type(CanReadMdtReport) ~= 'function'
        or not CheckPermission(src, 'warrants_view')
        or ps.getIdentifier(src) ~= citizenid or ps.getJobName(src) ~= jobName
        or (GetMdtAccess(src) or {}).interfaceId ~= interfaceId) then return {} end
    return results
end

-- Send actual records only to their authorized server-side audience. Client
-- visibility checks cannot protect a payload already broadcast to everyone.
function BroadcastActiveWarrants()
    for _, playerSource in pairs(GetPlayers()) do
        local target = tonumber(playerSource)
        if target and target > 0 and target % 1 == 0
            and canReadWarrantData(target)
            and CheckPermission(target, 'warrants_view') then
            TriggerClientEvent(resourceName .. ':client:updateActiveWarrants', target, GetActiveWarrantsData(target))
        end
    end
end

ps.registerCallback(resourceName .. ':server:getActiveWarrants', function(source)
    local src = source
    if not canReadWarrantData(src) then return {} end
    if not CheckPermission(src, 'warrants_view') then return {} end
    return GetActiveWarrantsData(src)
end)

ps.registerCallback(resourceName .. ':server:issueWarrant', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if type(requesterCitizenId) ~= 'string' or not requesterCitizenId:find('%S')
        or #requesterCitizenId > 64 or requesterCitizenId:find('%z')
        or type(requesterJob) ~= 'string' or not requesterJob:find('%S')
        or #requesterJob > 64 or requesterJob:find('%z') then
        return { success = false, error = 'Unauthorized' }
    end
    if IsMdtAttorneyGeneral(src) then return { success = false, error = 'Prosecution access cannot issue warrants' } end
    if not CheckPermission(src, 'warrants_issue') then
        return { success = false, error = 'Insufficient permissions' }
    end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid warrant request' } end
    local reportId = tonumber(data.reportId)
    local citizenid = data.citizenid
    local expiryValue = validateExpiry(data.expirydate)
    local expiryDate = getExpiryDate(expiryValue)
    if data.expirydate ~= nil and not expiryDate then
        return { success = false, error = 'Invalid warrant expiry' }
    end
    if expiryDate and expiryDate <= os.date('%Y-%m-%d %H:%M:%S') then
        return { success = false, error = 'Warrant expiry must be in the future' }
    end
    if data.expirydate ~= nil and not expiryDate then
        return { success = false, error = 'Invalid warrant expiry' }
    end
    if not expiryDate then
        local defaultDays = (Config and Config.Warrants and Config.Warrants.DefaultExpiryDays) or 7
        defaultDays = tonumber(defaultDays)
        if not defaultDays or defaultDays ~= defaultDays or defaultDays == math.huge
            or defaultDays == -math.huge or defaultDays < 1
            or defaultDays > 3650 then defaultDays = 7 end
        expiryDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + (defaultDays * 24 * 60 * 60))
    end

    -- A newly issued warrant must have a future expiration when supplied as a timestamp.
    local numericExpiry = tonumber(expiryValue)
    if numericExpiry then
        local seconds = numericExpiry > 100000000000 and numericExpiry / 1000 or numericExpiry
        if seconds <= os.time() then
            return { success = false, error = 'Warrant expiry must be in the future' }
        end
    end

    if not reportId or reportId ~= reportId or reportId == math.huge
        or reportId == -math.huge or reportId <= 0 or reportId % 1 ~= 0
        or type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then
        return { success = false, error = 'Missing required fields' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue') then
        return { success = false, error = 'Unauthorized warrant role' }
    end
    if not warrantReportExists(reportId) then
        return { success = false, error = 'Report not found' }
    end
    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report access denied' }
    end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }
    )
    if owner and owner ~= ps.getJobName(src) then
        return { success = false, error = 'Report belongs to another agency' }
    end

    -- Database lookups yield; confirm the issuer still holds the same role and report access.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or not CanReadMdtReport(src, reportId)
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob
        or (owner and owner ~= ps.getJobName(src)) then
        return { success = false, error = 'Warrant authorization changed' }
    end

    -- One warrant per report: refuse if this report already has any active
    -- (non-expired) warrant, regardless of which subject it targets.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or type(CanReadMdtReport) ~= 'function'
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local activeForReport = MySQL.single.await('SELECT 1 AS x FROM mdt_reports_warrants WHERE reportid = ? AND expirydate >= NOW() LIMIT 1', { reportId })
    if activeForReport then
        return { success = false, error = 'This report already has an active warrant' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local existing = MySQL.single.await('SELECT reportid FROM mdt_reports_warrants WHERE reportid = ? AND citizenid = ?', { reportId, citizenid })
    if existing and existing.reportid then
        return { success = false, error = 'An active warrant already exists for this subject on this report' }
    else
        if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
            or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
            or not CanReadMdtReport(src, reportId) then
            return { success = false, error = 'Warrant authorization changed' }
        end
        local inserted = MySQL.insert.await([[
            INSERT INTO mdt_reports_warrants (reportid, citizenid, felonies, misdemeanors, infractions, expirydate)
            SELECT r.id, ?, 0, 0, 0, ?
            FROM mdt_reports r WHERE r.id = ?
              AND NOT EXISTS (
                  SELECT 1 FROM mdt_reports_restrictions o
                  WHERE o.reportid = r.id AND o.type = 'owner' AND o.identifier <> ?
              )
              AND NOT EXISTS (
                  SELECT 1 FROM mdt_reports_warrants existing
                  WHERE existing.reportid = r.id AND existing.expirydate >= NOW()
              )
        ]], { citizenid, expiryDate, reportId, ps.getJobName(src) })
        if type(inserted) ~= 'number' or inserted ~= inserted
            or inserted == math.huge or inserted == -math.huge or inserted <= 0 then
            return { success = false, error = 'Report not found or inaccessible' }
        end
    end

    if ps.auditLog then
        ps.auditLog(src, 'warrant_issued', 'warrant', reportId, {
            citizenid = citizenid,
            expirydate = expiryDate
        })
    end

    BroadcastActiveWarrants()
    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:closeWarrant', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if type(requesterCitizenId) ~= 'string' or not requesterCitizenId:find('%S')
        or #requesterCitizenId > 64 or requesterCitizenId:find('%z')
        or type(requesterJob) ~= 'string' or not requesterJob:find('%S')
        or #requesterJob > 64 or requesterJob:find('%z') then
        return { success = false, error = 'Unauthorized' }
    end
    if IsMdtAttorneyGeneral(src) then return { success = false, error = 'Prosecution access cannot close warrants' } end
    if not CheckPermission(src, 'warrants_close') then
        return { success = false, error = 'Insufficient permissions' }
    end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid warrant request' } end
    local reportId = tonumber(data.reportId)
    local citizenid = data.citizenid
    if not reportId or reportId ~= reportId or reportId == math.huge
        or reportId == -math.huge or reportId <= 0 or reportId % 1 ~= 0
        or type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then
        return { success = false, error = 'Missing required fields' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close') then
        return { success = false, error = 'Unauthorized warrant role' }
    end
    if not warrantReportExists(reportId) then
        return { success = false, error = 'Report not found' }
    end
    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report access denied' }
    end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }
    )
    if owner and owner ~= ps.getJobName(src) then
        return { success = false, error = 'Report belongs to another agency' }
    end

    -- Do not close a warrant after the requester's authority has changed.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close')
        or not CanReadMdtReport(src, reportId)
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob
        or (owner and owner ~= ps.getJobName(src)) then
        return { success = false, error = 'Warrant authorization changed' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local updated = MySQL.update.await([[
        UPDATE mdt_reports_warrants
        SET expirydate = NOW()
        WHERE reportid = ? AND citizenid = ? AND expirydate > NOW()
          AND NOT EXISTS (SELECT 1 FROM mdt_reports_restrictions o
              WHERE o.reportid = ? AND o.type = 'owner' AND o.identifier <> ?)
    ]], { reportId, citizenid, reportId, ps.getJobName(src) })

    if type(updated) == 'number' and updated ~= math.huge
        and updated ~= -math.huge and updated > 0 then
        -- Closing the warrant also removes any hearing it placed on the calendar.
        if RemoveWarrantHearingsForReport then
            RemoveWarrantHearingsForReport(reportId)
        end
        if ps.auditLog then
            ps.auditLog(src, 'warrant_closed', 'warrant', reportId, {
                citizenid = citizenid
            })
        end
        BroadcastActiveWarrants()
        return { success = true }
    end

    return { success = false, error = 'Warrant not found' }
end)
)
            year, month, day = tonumber(year), tonumber(month), tonumber(day)
            hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)
            local leap = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
            local daysInMonth = ({31, leap and 29 or 28, 31, 30, 31, 30,
                31, 31, 30, 31, 30, 31})[month]
            if year >= 1970 and year <= 2100 and daysInMonth
                and day >= 1 and day <= daysInMonth
                and hour <= 23 and minute <= 59 and second <= 59 then
                return trimmed
            end
        end
    end
    return nil
end

local function toTimestamp(value)
    local numeric = tonumber(value)
    if not numeric or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then return nil end
    if numeric > 100000000000 then return math.floor(numeric / 1000) end
    return numeric
end

local function getExpiryDate(value)
    local ts = toTimestamp(value)
    if ts then return os.date('%Y-%m-%d %H:%M:%S', ts) end
    if type(value) == 'string' and value:match('^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$') then
        return value
    end
    return nil
end

-- Exposed as a global so the dashboard aggregate (server/backend/dashboard.lua)
-- can reuse it without a second round-trip.
function GetActiveWarrantsData(src)
    if src ~= nil and (not canReadWarrantData(src) or not CheckPermission(src, 'warrants_view')
        or type(CanReadMdtReport) ~= 'function') then
        return {}
    end
    local citizenid = src ~= nil and ps.getIdentifier(src) or nil
    local jobName = src ~= nil and ps.getJobName(src) or nil
    if src ~= nil and (type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z')
        or type(jobName) ~= 'string' or not jobName:find('%S')
        or #jobName > 64 or jobName:find('%z')) then return {} end
    local access = src ~= nil and GetMdtAccess(src) or nil
    local interfaceId = access and access.interfaceId or nil
    local rows = MySQL.query.await([[
        SELECT
            w.reportid,
            w.citizenid,
            w.felonies,
            w.misdemeanors,
            w.infractions,
            w.expirydate,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')) AS firstname,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname')) AS lastname
        FROM mdt_reports_warrants w
        LEFT JOIN players p ON p.citizenid COLLATE utf8mb4_general_ci = w.citizenid COLLATE utf8mb4_general_ci
        WHERE w.expirydate >= NOW()
        ORDER BY w.expirydate ASC, w.reportid ASC, w.citizenid ASC
    ]])

    if type(rows) ~= 'table' then return {} end
    if src ~= nil and (not canReadWarrantData(src)
        or not CheckPermission(src, 'warrants_view')) then return {} end
    for _, row in ipairs(rows) do
        local id = type(row) == 'table' and tonumber(row.reportid) or nil
        if not id or id ~= id or id == math.huge or id == -math.huge
            or id <= 0 or id % 1 ~= 0 or type(row.citizenid) ~= 'string'
            or not row.citizenid:find('%S') or #row.citizenid > 64
            or row.citizenid:find('%z') then return {} end
    end
    local results = {}
    for _, row in ipairs(rows) do
        if type(row) == 'table' and (src == nil or (type(CanReadMdtReport) == 'function' and CanReadMdtReport(src, row.reportid))) then
        local first = type(row.firstname) == 'string' and row.firstname or ''
        local last = type(row.lastname) == 'string' and row.lastname or ''
        local name = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+
        if name == '' then
            local fallback = ps.getPlayerNameByIdentifier(row.citizenid)
            name = type(fallback) == 'string' and fallback ~= '' and fallback or 'Unknown'
        end
        results[#results + 1] = {
            reportid = row.reportid,
            citizenid = row.citizenid,
            name = name,
            felonies = tonumber(row.felonies) or 0,
            misdemeanors = tonumber(row.misdemeanors) or 0,
            infractions = tonumber(row.infractions) or 0,
            expirydate = row.expirydate,
        }
        end
    end

    -- SQL and name resolution can yield while the source changes character or job.
    if src ~= nil and (not canReadWarrantData(src)
        or type(CanReadMdtReport) ~= 'function'
        or not CheckPermission(src, 'warrants_view')
        or ps.getIdentifier(src) ~= citizenid or ps.getJobName(src) ~= jobName
        or (GetMdtAccess(src) or {}).interfaceId ~= interfaceId) then return {} end
    return results
end

-- Send actual records only to their authorized server-side audience. Client
-- visibility checks cannot protect a payload already broadcast to everyone.
function BroadcastActiveWarrants()
    for _, playerSource in pairs(GetPlayers()) do
        local target = tonumber(playerSource)
        if target and target > 0 and target % 1 == 0
            and canReadWarrantData(target)
            and CheckPermission(target, 'warrants_view') then
            TriggerClientEvent(resourceName .. ':client:updateActiveWarrants', target, GetActiveWarrantsData(target))
        end
    end
end

ps.registerCallback(resourceName .. ':server:getActiveWarrants', function(source)
    local src = source
    if not canReadWarrantData(src) then return {} end
    if not CheckPermission(src, 'warrants_view') then return {} end
    return GetActiveWarrantsData(src)
end)

ps.registerCallback(resourceName .. ':server:issueWarrant', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if type(requesterCitizenId) ~= 'string' or not requesterCitizenId:find('%S')
        or #requesterCitizenId > 64 or requesterCitizenId:find('%z')
        or type(requesterJob) ~= 'string' or not requesterJob:find('%S')
        or #requesterJob > 64 or requesterJob:find('%z') then
        return { success = false, error = 'Unauthorized' }
    end
    if IsMdtAttorneyGeneral(src) then return { success = false, error = 'Prosecution access cannot issue warrants' } end
    if not CheckPermission(src, 'warrants_issue') then
        return { success = false, error = 'Insufficient permissions' }
    end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid warrant request' } end
    local reportId = tonumber(data.reportId)
    local citizenid = data.citizenid
    local expiryValue = validateExpiry(data.expirydate)
    local expiryDate = getExpiryDate(expiryValue)
    if data.expirydate ~= nil and not expiryDate then
        return { success = false, error = 'Invalid warrant expiry' }
    end
    if expiryDate and expiryDate <= os.date('%Y-%m-%d %H:%M:%S') then
        return { success = false, error = 'Warrant expiry must be in the future' }
    end
    if data.expirydate ~= nil and not expiryDate then
        return { success = false, error = 'Invalid warrant expiry' }
    end
    if not expiryDate then
        local defaultDays = (Config and Config.Warrants and Config.Warrants.DefaultExpiryDays) or 7
        defaultDays = tonumber(defaultDays)
        if not defaultDays or defaultDays ~= defaultDays or defaultDays == math.huge
            or defaultDays == -math.huge or defaultDays < 1
            or defaultDays > 3650 then defaultDays = 7 end
        expiryDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + (defaultDays * 24 * 60 * 60))
    end

    -- A newly issued warrant must have a future expiration when supplied as a timestamp.
    local numericExpiry = tonumber(expiryValue)
    if numericExpiry then
        local seconds = numericExpiry > 100000000000 and numericExpiry / 1000 or numericExpiry
        if seconds <= os.time() then
            return { success = false, error = 'Warrant expiry must be in the future' }
        end
    end

    if not reportId or reportId ~= reportId or reportId == math.huge
        or reportId == -math.huge or reportId <= 0 or reportId % 1 ~= 0
        or type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then
        return { success = false, error = 'Missing required fields' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue') then
        return { success = false, error = 'Unauthorized warrant role' }
    end
    if not warrantReportExists(reportId) then
        return { success = false, error = 'Report not found' }
    end
    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report access denied' }
    end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }
    )
    if owner and owner ~= ps.getJobName(src) then
        return { success = false, error = 'Report belongs to another agency' }
    end

    -- Database lookups yield; confirm the issuer still holds the same role and report access.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or not CanReadMdtReport(src, reportId)
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob
        or (owner and owner ~= ps.getJobName(src)) then
        return { success = false, error = 'Warrant authorization changed' }
    end

    -- One warrant per report: refuse if this report already has any active
    -- (non-expired) warrant, regardless of which subject it targets.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or type(CanReadMdtReport) ~= 'function'
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local activeForReport = MySQL.single.await('SELECT 1 AS x FROM mdt_reports_warrants WHERE reportid = ? AND expirydate >= NOW() LIMIT 1', { reportId })
    if activeForReport then
        return { success = false, error = 'This report already has an active warrant' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local existing = MySQL.single.await('SELECT reportid FROM mdt_reports_warrants WHERE reportid = ? AND citizenid = ?', { reportId, citizenid })
    if existing and existing.reportid then
        return { success = false, error = 'An active warrant already exists for this subject on this report' }
    else
        if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_issue')
            or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
            or not CanReadMdtReport(src, reportId) then
            return { success = false, error = 'Warrant authorization changed' }
        end
        local inserted = MySQL.insert.await([[
            INSERT INTO mdt_reports_warrants (reportid, citizenid, felonies, misdemeanors, infractions, expirydate)
            SELECT r.id, ?, 0, 0, 0, ?
            FROM mdt_reports r WHERE r.id = ?
              AND NOT EXISTS (
                  SELECT 1 FROM mdt_reports_restrictions o
                  WHERE o.reportid = r.id AND o.type = 'owner' AND o.identifier <> ?
              )
              AND NOT EXISTS (
                  SELECT 1 FROM mdt_reports_warrants existing
                  WHERE existing.reportid = r.id AND existing.expirydate >= NOW()
              )
        ]], { citizenid, expiryDate, reportId, ps.getJobName(src) })
        if type(inserted) ~= 'number' or inserted ~= inserted
            or inserted == math.huge or inserted == -math.huge or inserted <= 0 then
            return { success = false, error = 'Report not found or inaccessible' }
        end
    end

    if ps.auditLog then
        ps.auditLog(src, 'warrant_issued', 'warrant', reportId, {
            citizenid = citizenid,
            expirydate = expiryDate
        })
    end

    BroadcastActiveWarrants()
    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:closeWarrant', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false, error = 'Unauthorized' } end
    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if type(requesterCitizenId) ~= 'string' or not requesterCitizenId:find('%S')
        or #requesterCitizenId > 64 or requesterCitizenId:find('%z')
        or type(requesterJob) ~= 'string' or not requesterJob:find('%S')
        or #requesterJob > 64 or requesterJob:find('%z') then
        return { success = false, error = 'Unauthorized' }
    end
    if IsMdtAttorneyGeneral(src) then return { success = false, error = 'Prosecution access cannot close warrants' } end
    if not CheckPermission(src, 'warrants_close') then
        return { success = false, error = 'Insufficient permissions' }
    end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid warrant request' } end
    local reportId = tonumber(data.reportId)
    local citizenid = data.citizenid
    if not reportId or reportId ~= reportId or reportId == math.huge
        or reportId == -math.huge or reportId <= 0 or reportId % 1 ~= 0
        or type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or citizenid:find('%z') then
        return { success = false, error = 'Missing required fields' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close') then
        return { success = false, error = 'Unauthorized warrant role' }
    end
    if not warrantReportExists(reportId) then
        return { success = false, error = 'Report not found' }
    end
    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report access denied' }
    end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }
    )
    if owner and owner ~= ps.getJobName(src) then
        return { success = false, error = 'Report belongs to another agency' }
    end

    -- Do not close a warrant after the requester's authority has changed.
    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close')
        or not CanReadMdtReport(src, reportId)
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob
        or (owner and owner ~= ps.getJobName(src)) then
        return { success = false, error = 'Warrant authorization changed' }
    end

    if not canReadWarrantData(src) or not CheckPermission(src, 'warrants_close')
        or ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Warrant authorization changed' }
    end
    local updated = MySQL.update.await([[
        UPDATE mdt_reports_warrants
        SET expirydate = NOW()
        WHERE reportid = ? AND citizenid = ? AND expirydate > NOW()
          AND NOT EXISTS (SELECT 1 FROM mdt_reports_restrictions o
              WHERE o.reportid = ? AND o.type = 'owner' AND o.identifier <> ?)
    ]], { reportId, citizenid, reportId, ps.getJobName(src) })

    if type(updated) == 'number' and updated ~= math.huge
        and updated ~= -math.huge and updated > 0 then
        -- Closing the warrant also removes any hearing it placed on the calendar.
        if RemoveWarrantHearingsForReport then
            RemoveWarrantHearingsForReport(reportId)
        end
        if ps.auditLog then
            ps.auditLog(src, 'warrant_closed', 'warrant', reportId, {
                citizenid = citizenid
            })
        end
        BroadcastActiveWarrants()
        return { success = true }
    end

    return { success = false, error = 'Warrant not found' }
end)
