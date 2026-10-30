local resourceName = tostring(GetCurrentResourceName())

local function getEffectiveJobType(src)
    -- Match the authenticated MDT interface instead of relying on a QBCore
    -- job type alone. Fire and hospital records remain separate domains.
    local access = GetMdtAccess(src)
    if not access or not access.authorized or access.isCivilian then return nil end
    local domain = (Config.Interfaces or {})[access.interfaceId]
    if not domain or domain.Enabled ~= true then return nil end
    if domain.JobType == 'leo' or domain.JobType == 'doj'
        or domain.JobType == 'ems' or domain.JobType == 'fire' then
        return domain.JobType
    end
    return nil
end

-- A new report may carry an originating agency ('owner') restriction.
-- Legacy reports without one continue to use their original access policy.
-- Explicit citizen/job sharing overrides the owner; generic jobtype does not.
local ownerScope = [[
    (NOT EXISTS (SELECT 1 FROM mdt_reports_restrictions o WHERE o.reportid = mr.id AND o.type = 'owner')
     OR EXISTS (SELECT 1 FROM mdt_reports_restrictions o WHERE o.reportid = mr.id AND o.type = 'owner' AND o.identifier = ?)
     OR EXISTS (SELECT 1 FROM mdt_reports_restrictions g WHERE g.reportid = mr.id
        AND ((g.type = 'citizenid' AND g.identifier = ?) OR (g.type = 'job' AND g.identifier = ?))))
]]

local function collectCitizenIds(reportData)
    local citizenids = {}

    if reportData.involved then
        for _, involved in ipairs(reportData.involved) do
            if involved.citizenid then
                citizenids[involved.citizenid] = true
            end
        end
    end

    if reportData.charges then
        for _, charge in ipairs(reportData.charges) do
            if charge.citizenid then
                citizenids[charge.citizenid] = true
            end
        end
    end

    return citizenids
end

-- A named Stage 4 disclosure is read-only; it never grants report writes.
local function hasReportDisclosure(src, reportId)
    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return false end
    local cid, job=ps.getIdentifier(src), ps.getJobName(src)
    if not cid or not job then return false end
    local ok, row=pcall(MySQL.single.await, [[
        SELECT id FROM mdt_report_disclosures
        WHERE report_id = ? AND recipient_citizenid = ? AND recipient_job = ?
          AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())
        LIMIT 1
    ]], {reportId,cid,job})
    return ok and row ~= nil and CheckAuth(src)
        and CheckPermission(src,'reports_view') and ps.getIdentifier(src)==cid
        and ps.getJobName(src)==job
end

local function checkReportAccess(src, reportId)
    if not src or not reportId then
        return false
    end

    local identifier = ps.getIdentifier(src)
    local job = ps.getJobName(src)
    local jobType = getEffectiveJobType(src)

    if not identifier or not jobType then
        return false
    end
    if hasReportDisclosure(src,reportId) then return true end

    -- DOJ may read ordinary operational reports, but not restricted fire or
    -- hospital reports merely by knowing the report ID. Explicitly shared
    -- reports remain accessible through the normal restriction checks.
    local hasAccess = MySQL.query.await([[
        SELECT mr.id
        FROM mdt_reports mr
        LEFT JOIN mdt_reports_restrictions mrr_check ON mr.id = mrr_check.reportid
        WHERE mr.id = ?
        AND (
            (? = 'doj' AND NOT EXISTS (
                SELECT 1 FROM mdt_reports_restrictions mrr_private
                WHERE mrr_private.reportid = mr.id
                  AND mrr_private.type = 'jobtype'
                  AND mrr_private.identifier IN ('ems', 'fire')
            ))
            -- Match the report-list default: an unrestricted report is
            -- visible only to operational LEO/EMS families, never an
            -- arbitrary authenticated interface (including DOJ).
            OR (mrr_check.reportid IS NULL AND (? = 'leo' OR ? = 'ems' OR ? = 'fire'))
            OR (mrr_check.type = 'citizenid' AND mrr_check.identifier = ?)
            OR (mrr_check.type = 'job' AND mrr_check.identifier = ?)
            OR (mrr_check.type = 'jobtype' AND mrr_check.identifier = ?)
        )
        AND ]] .. ownerScope .. [[
        GROUP BY mr.id
    ]], {reportId, jobType, jobType, jobType, jobType, identifier, job, jobType, job, identifier, job})

    return hasAccess and hasAccess[1] ~= nil
end

-- A disclosed report can be read but cannot be rewritten or deleted.
-- New records belong to their originating agency; older records without an
-- owner marker keep legacy team editing until their owner is reconciled.
-- Shared read guard for related LEO workflows such as warrant issuance.
-- Keep report-specific disclosure and owner restrictions in one place.
function CanReadMdtReport(src, reportId)
    local id = tonumber(reportId)
    if not id or id <= 0 or id % 1 ~= 0 then return false end
    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return false end
    return checkReportAccess(src, id)
        and CheckAuth(src) and CheckPermission(src, 'reports_view')
end

local function checkReportWriteAccess(src, reportId, action)
    if not CheckAuth(src) or not CheckPermission(src, action) then return false end
    if reportId == nil then return true end
    if not checkReportAccess(src, reportId) then return false end
    local owner = MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId })
    if owner ~= nil and owner ~= ps.getJobName(src) then return false end
    return CheckAuth(src) and CheckPermission(src, action)
end

local function buildFullName(firstname, lastname, citizenid)
    local first = firstname and tostring(firstname) or ''
    local last = lastname and tostring(lastname) or ''
    local full = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', '')
    if full ~= '' then
        return full
    end
    return ps.getPlayerNameByIdentifier(citizenid) or 'Unknown'
end




local function normalizeDateFilter(value)
    if not value then
        return nil
    end
    local year, month, day = tostring(value):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if not year then
        return nil
    end
    return ('%s-%s-%s'):format(year, month, day)
end

local function buildReportFilterClause(filters)
    local clauses = {}
    local values = {}
    if not filters then
        return '', values
    end

    local function hasValue(value)
        if value == nil then return false end
        if json and value == json.null then return false end
        if type(value) == 'string' then return value:gsub('%s+', '') ~= '' end
        return true
    end

    if hasValue(filters.search) then
        local likeQuery = '%' .. tostring(filters.search) .. '%'
        clauses[#clauses + 1] = [[
            (
                mr.title LIKE ?
                OR CAST(mr.id AS CHAR) LIKE ?
                OR mr.authorplaintext LIKE ?
                OR mr.type LIKE ?
                OR EXISTS (
                    SELECT 1 FROM mdt_reports_tags mrt2
                    WHERE mrt2.reportid = mr.id AND mrt2.tag LIKE ?
                )
            )
        ]]
        values[#values + 1] = likeQuery
        values[#values + 1] = likeQuery
        values[#values + 1] = likeQuery
        values[#values + 1] = likeQuery
        values[#values + 1] = likeQuery
    end

    if hasValue(filters.type) then
        clauses[#clauses + 1] = 'mr.type = ?'
        values[#values + 1] = filters.type
    end

    if hasValue(filters.author) then
        local likeQuery = '%' .. tostring(filters.author) .. '%'
        clauses[#clauses + 1] = '(mr.authorplaintext LIKE ? OR mr.author LIKE ?)'
        values[#values + 1] = likeQuery
        values[#values + 1] = likeQuery
    end

    local startDate = normalizeDateFilter(filters.startDate)
    if startDate then
        clauses[#clauses + 1] = 'mr.datecreated >= CONCAT(?, " 00:00:00")'
        values[#values + 1] = startDate
    end

    local endDate = normalizeDateFilter(filters.endDate)
    if endDate then
        clauses[#clauses + 1] = 'mr.datecreated <= CONCAT(?, " 23:59:59")'
        values[#values + 1] = endDate
    end

    if #clauses == 0 then
        return '', values
    end

    return ' AND ' .. table.concat(clauses, ' AND '), values
end

local function buildReportAnalyticsClause(filters)
	local clauses = {}
	local values = {}
	if not filters then
		return '', values
	end

	local function hasValue(value)
		if value == nil then
			return false
		end
		if json and value == json.null then
			return false
		end
		if type(value) == 'string' then
			return value:gsub('%s+', '') ~= ''
		end
		return true
	end

	if hasValue(filters.author) then
		local likeQuery = '%' .. tostring(filters.author) .. '%'
		clauses[#clauses + 1] = '(mr.authorplaintext LIKE ? OR mr.author LIKE ?)'
		values[#values + 1] = likeQuery
		values[#values + 1] = likeQuery
	end

    local startDate = normalizeDateFilter(filters.startDate)
    if startDate then
        clauses[#clauses + 1] = 'mr.datecreated >= CONCAT(?, " 00:00:00")'
        values[#values + 1] = startDate
    end

    local endDate = normalizeDateFilter(filters.endDate)
    if endDate then
        clauses[#clauses + 1] = 'mr.datecreated <= CONCAT(?, " 23:59:59")'
        values[#values + 1] = endDate
    end

    if #clauses == 0 then
        return '', values
    end

    return ' AND ' .. table.concat(clauses, ' AND '), values
end

local function buildReportAccessClause()
    return [[
        (
            (? = 'doj' AND NOT EXISTS(
                SELECT 1 FROM mdt_reports_restrictions mrr_ems
                WHERE mrr_ems.reportid = mr.id AND mrr_ems.type = 'jobtype' AND mrr_ems.identifier IN ('ems', 'fire')
            ))
            OR (mrr.reportid IS NULL AND (? = 'leo' OR ? IN ('ems', 'fire')))
            OR (mrr.type = 'citizenid' AND mrr.identifier = ?)
            OR (mrr.type = 'job' AND mrr.identifier = ?)
            OR (mrr.type = 'jobtype' AND mrr.identifier = ?)
        ) AND ]] .. ownerScope
end


ps.registerCallback(resourceName .. ':server:getReports', function(source, page, filters)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then
        return { reports = {}, total = 0 }
    end

    local identifier = ps.getIdentifier(src)
    local job = ps.getJobName(src)
    local jobType = getEffectiveJobType(src)
    if not identifier or not job or not jobType then return { reports = {}, total = 0 } end

    if type(filters) ~= 'table' then filters = nil end
    local requestedPage = tonumber(page) or 1
    if requestedPage ~= requestedPage or requestedPage == math.huge or requestedPage == -math.huge then requestedPage = 1 end
    local requestedLimit = tonumber(filters and filters.limit) or 20
    if requestedLimit ~= requestedLimit or requestedLimit == math.huge or requestedLimit == -math.huge then requestedLimit = 20 end
    local pageNumber = math.floor(math.max(1, math.min(requestedPage, 10000)))
    local limit = math.floor(math.max(1, math.min(requestedLimit, 100)))
    local offset = (pageNumber - 1) * limit

    local filterClause, filterValues = buildReportFilterClause(filters)
    filterClause = filterClause or ''

    local accessClause = buildReportAccessClause()
    local baseParams = { jobType, jobType, jobType, identifier, job, jobType, job, identifier, job }

    local queryParams = {}
    for _, v in ipairs(baseParams) do queryParams[#queryParams + 1] = v end
    for _, v in ipairs(filterValues or {}) do queryParams[#queryParams + 1] = v end

    local countQuery = ([[
        SELECT COUNT(DISTINCT mr.id) AS total
        FROM mdt_reports AS mr
        LEFT JOIN mdt_reports_restrictions AS mrr ON mr.id = mrr.reportid
        WHERE %s%s
    ]]):format(accessClause, filterClause)

    local countRow = MySQL.single.await(countQuery, queryParams)
    local total = tonumber(countRow and countRow.total) or 0

    local reportsQuery = ([[
        SELECT
            mr.id,
            mr.id as reportId,
            mr.title,
            mr.type,
            mr.contentyjs,
            mr.contentplaintext,
            mr.author,
            mr.authorplaintext,
            mr.datecreated,
            mr.dateupdated,
            (SELECT mrt.tag FROM mdt_reports_tags mrt WHERE mrt.reportid = mr.id LIMIT 1) as tag,
            (SELECT COUNT(*) FROM mdt_reports_tags mrt WHERE mrt.reportid = mr.id) as tagCount
        FROM mdt_reports AS mr
        LEFT JOIN mdt_reports_restrictions AS mrr ON mr.id = mrr.reportid
        WHERE %s%s
        GROUP BY mr.id
        ORDER BY mr.id DESC
        LIMIT %d OFFSET %d
    ]]):format(accessClause, filterClause, limit, offset)

    local reportsParams = {}
    for _, v in ipairs(baseParams) do reportsParams[#reportsParams + 1] = v end
    for _, v in ipairs(filterValues or {}) do reportsParams[#reportsParams + 1] = v end

    local reports = MySQL.query.await(reportsQuery, reportsParams)
    -- The count and list queries may yield across a duty/job/character switch.
    -- Never return confidential results from the old source identity.
    if not CheckAuth(src) or ps.getIdentifier(src) ~= identifier
        or ps.getJobName(src) ~= job or getEffectiveJobType(src) ~= jobType
        or not CheckPermission(src, 'reports_view') then
        return { reports = {}, total = 0 }
    end

    return { reports = reports or {}, total = total }
end)

ps.registerCallback(resourceName..':server:getReport', function(source, reportid)
    local src = source
    if not CanReadMdtReport(src, reportid) then return nil end

	local identifier = ps.getIdentifier(src)
    local job = ps.getJobName(src)
    local jobType = getEffectiveJobType(src)

    local result = MySQL.query.await([[
        SELECT
            mr.*,
            (SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'citizenid', mri.citizenid,
                    'type', mri.type,
                    'notes', mri.notes,
                    'warrantActive', CASE
                        WHEN mri.type = 'suspect' AND EXISTS(
                            SELECT 1 FROM mdt_reports_warrants mw
                            WHERE mw.reportid = mr.id AND mw.citizenid = mri.citizenid AND mw.expirydate >= NOW()
                        ) THEN true
                        ELSE false
                    END
                )
            ) FROM mdt_reports_involved mri WHERE mri.reportid = mr.id) as involved,
            (SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'citizenid', mrc.citizenid,
                    'charge', mrc.charge,
                    'count', mrc.count,
                    'time', mrc.time,
                    'fine', mrc.fine
                )
            ) FROM mdt_reports_charges mrc WHERE mrc.reportid = mr.id) as charges,
            (SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'title', mre.title,
                    'type', mre.type,
                    'content', mre.content,
                    'note', mre.note,
                    'stored', mre.stored,
                    'images', CASE
                        WHEN mre.images IS NOT NULL AND mre.images != ''
                        THEN JSON_EXTRACT(mre.images, '$')
                        ELSE JSON_ARRAY()
                    END
                )
            ) FROM mdt_reports_evidence mre WHERE mre.reportid = mr.id) as evidence,
            (SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'type', mrr.type,
                    'identifier', mrr.identifier
                )
            ) FROM mdt_reports_restrictions mrr WHERE mrr.reportid = mr.id) as restrictions,
            (SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'tag', mrt.tag
                )
            ) FROM mdt_reports_tags mrt WHERE mrt.reportid = mr.id) as tags,
            (SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'plate', mrv.plate,
                    'vehicle_label', mrv.vehicle_label,
                    'owner_name', mrv.owner_name,
                    'owner_citizenid', mrv.owner_citizenid
                )
            ) FROM mdt_report_vehicles mrv WHERE mrv.reportid = mr.id) as vehicles
        FROM mdt_reports mr
        WHERE mr.id = ?
    ]], {reportid})

    local report = result[1] or nil
    if not report then return nil end

    -- Post-process: resolve names and profile images for involved persons
    local enrichOk, enrichErr = pcall(function()
        local involved = report.involved
        if type(involved) == 'string' then
            local ok, decoded = pcall(json.decode, involved)
            if ok then involved = decoded end
        end

        if type(involved) ~= 'table' or #involved == 0 then return end

        -- Collect unique citizenids
        local cids = {}
        for _, entry in ipairs(involved) do
            if entry and entry.citizenid and entry.citizenid ~= '' then
                cids[entry.citizenid] = true
            end
        end

        local cidList = {}
        for cid in pairs(cids) do
            cidList[#cidList + 1] = cid
        end

        if #cidList > 0 then
            local placeholders = string.rep('?,', #cidList):sub(1, -2)
            local lookupQuery = ([[
                SELECT
                    p.citizenid,
                    CONCAT(
                        JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')),
                        ' ',
                        JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname'))
                    ) as fullname,
                    mp.profilepicture as image,
                    JSON_UNQUOTE(JSON_EXTRACT(p.metadata, '$.fingerprint')) as fingerprint
                FROM players p
                LEFT JOIN mdt_profiles mp ON mp.citizenid COLLATE utf8mb4_general_ci = p.citizenid COLLATE utf8mb4_general_ci
                WHERE p.citizenid COLLATE utf8mb4_general_ci IN (%s)
            ]]):format(placeholders)

            local lookupRows = MySQL.query.await(lookupQuery, cidList)
            local cidInfo = {}
            for _, row in ipairs(lookupRows) do
                cidInfo[row.citizenid] = {
                    name = row.fullname,
                    image = row.image,
                    fingerprint = (row.fingerprint and row.fingerprint ~= 'null') and row.fingerprint or nil
                }
            end

            for _, entry in ipairs(involved) do
                if entry and entry.citizenid and cidInfo[entry.citizenid] then
                    local info = cidInfo[entry.citizenid]
                    entry.name = info.name or entry.name
                    entry.image = info.image
                    entry.fingerprint = info.fingerprint
                end
            end
        end

        report.involved = json.encode(involved)
    end)

    if not enrichOk then
        ps.warn(('[getReport] Failed to enrich involved data: %s'):format(tostring(enrichErr)))
    end

    -- Report enrichment may yield across permission revocation or job changes.
    if not CheckAuth(src) or ps.getIdentifier(src) ~= identifier
        or ps.getJobName(src) ~= job
        or not CanReadMdtReport(src, reportid) then return nil end
    if ps.auditLog and hasReportDisclosure(src, tonumber(reportid)) then
        ps.auditLog(src,'report_disclosure_accessed','report',tonumber(reportid),
            {recipient=identifier})
    end
    return report
end)

ps.registerCallback(resourceName .. ':server:searchPlayers', function(source, query)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return {} end

    local norm, likeQuery = NormalizeSearch(query)
    if not likeQuery or not norm or #norm < 2 then return {} end

    if ps.auditLog then
        ps.auditLog(src, 'search_players', 'search', nil, {
            query = norm
        })
    end

    -- No COLLATE cast on the join key (shared utf8mb4_general_ci) so the
    -- mdt_profiles index stays usable instead of degrading to a full scan.
    local rows = MySQL.query.await([[
        SELECT
            p.citizenid,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')) as firstname,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname')) as lastname,
            JSON_UNQUOTE(JSON_EXTRACT(p.metadata, '$.fingerprint')) as fingerprint,
            mp.profilepicture
        FROM players p
        LEFT JOIN mdt_profiles mp ON mp.citizenid = p.citizenid
        WHERE (
            LOWER(p.citizenid) LIKE ?
            OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname'))) LIKE ?
            OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname'))) LIKE ?
            OR LOWER(CONCAT(
                JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')),
                ' ',
                JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname'))
            )) LIKE ?
        )
        LIMIT 25
    ]], { likeQuery, likeQuery, likeQuery, likeQuery })

    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return {} end
    local results = {}
    for _, row in ipairs(rows or {}) do
        local fullName = buildFullName(row.firstname, row.lastname, row.citizenid)
        local fingerprint = (row.fingerprint and row.fingerprint ~= 'null') and row.fingerprint or nil
        table.insert(results, {
            id = row.citizenid,
            citizenid = row.citizenid,
            fullName = fullName,
            fingerprint = fingerprint,
            image = row.profilepicture or nil,
        })
    end

    return results
end)

ps.registerCallback(resourceName .. ':server:searchOfficers', function(source, query)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return {} end

    local norm, likeQuery = NormalizeSearch(query)
    if not likeQuery or #norm < 2 then
        return {}
    end

    if ps.auditLog then
        ps.auditLog(src, 'search_officers', 'search', nil, {
            query = norm
        })
    end

    -- Build the police-job filter as SQL (from Config.PoliceJobType / PoliceJobs)
    -- instead of fetching arbitrary players and filtering in Lua afterwards.
    -- The old approach took 50 random matches then dropped non-police, so on a
    -- busy server an officer could be missing entirely. Filtering in SQL also
    -- shrinks the scanned set dramatically.
    local jobClauses, jobParams = {}, {}
    if Config and Config.PoliceJobType then
        jobClauses[#jobClauses + 1] = "JSON_UNQUOTE(JSON_EXTRACT(p.job, '$.type')) = ?"
        jobParams[#jobParams + 1] = tostring(Config.PoliceJobType)
    end
    if Config and Config.PoliceJobs and #Config.PoliceJobs > 0 then
        local ph = {}
        for _, job in ipairs(Config.PoliceJobs) do
            ph[#ph + 1] = '?'
            jobParams[#jobParams + 1] = tostring(job)
        end
        jobClauses[#jobClauses + 1] =
            "JSON_UNQUOTE(JSON_EXTRACT(p.job, '$.name')) IN (" .. table.concat(ph, ',') .. ")"
    end
    local jobFilter = #jobClauses > 0
        and (' AND (' .. table.concat(jobClauses, ' OR ') .. ')')
        or ''

    local params = { likeQuery, likeQuery, likeQuery, likeQuery, likeQuery }
    for _, p in ipairs(jobParams) do params[#params + 1] = p end

    local rows = MySQL.query.await([[
        SELECT
            p.citizenid,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')) as firstname,
            JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname')) as lastname,
            JSON_UNQUOTE(JSON_EXTRACT(p.job, '$.grade.name')) as jobgrade,
            mp.callsign as callsign
        FROM players p
        LEFT JOIN mdt_profiles mp ON mp.citizenid = p.citizenid
        WHERE (
            LOWER(p.citizenid) LIKE ?
            OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname'))) LIKE ?
            OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname'))) LIKE ?
            OR LOWER(CONCAT(
                JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')),
                ' ',
                JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname'))
            )) LIKE ?
            OR LOWER(mp.callsign) LIKE ?
        )]] .. jobFilter .. [[
        LIMIT 50
    ]], params)

    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return {} end
    local results = {}
    for _, row in ipairs(rows or {}) do
        local fullName = buildFullName(row.firstname, row.lastname, row.citizenid)
        table.insert(results, {
            id = row.citizenid,
            citizenid = row.citizenid,
            fullName = fullName,
            badgeId = row.callsign or nil,
            rank = row.jobgrade or nil
        })
    end

    return results
end)

ps.registerCallback(resourceName .. ':server:searchVehiclesForReport', function(source, query)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return {} end

    -- Consistent, case/space-insensitive normalisation (see NormalizeSearch).
    local _, likePat, plateLike = NormalizeSearch(query)
    if not likePat or type(query) ~= 'string' or #query:gsub('%s+', '') < 2 then return {} end

    local vehicleShared = nil
    local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and core and core.Shared and core.Shared.Vehicles then
        vehicleShared = core.Shared.Vehicles
    end

    -- NOTE: no COLLATE cast on the join key — players.citizenid and
    -- player_vehicles.citizenid share utf8mb4_general_ci, so casting only
    -- defeated the PK index and forced a quadratic nested-loop (the 10s timeout).
    local rows = MySQL.query.await([[
        SELECT
            pv.plate,
            pv.vehicle,
            pv.citizenid,
            COALESCE(
                NULLIF(
                    CONCAT(
                        COALESCE(JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')), ''),
                        ' ',
                        COALESCE(JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname')), '')
                    ),
                    ' '
                ),
                'Unknown'
            ) as owner_name
        FROM player_vehicles pv
        LEFT JOIN players p ON p.citizenid = pv.citizenid
        WHERE (
            REPLACE(LOWER(pv.plate), ' ', '') LIKE ?
            OR LOWER(CONCAT(
                COALESCE(JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.firstname')), ''),
                ' ',
                COALESCE(JSON_UNQUOTE(JSON_EXTRACT(p.charinfo, '$.lastname')), '')
            )) LIKE ?
            OR LOWER(pv.citizenid) LIKE ?
        )
        ORDER BY pv.plate ASC
        LIMIT 25
    ]], { plateLike, likePat, likePat })

    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return {} end
    local results = {}
    for _, row in ipairs(rows or {}) do
        local vehicleData = vehicleShared and vehicleShared[row.vehicle] or nil
        table.insert(results, {
            plate = row.plate and string.upper(row.plate):gsub('%s+', '') or 'UNKNOWN',
            vehicle_label = vehicleData and vehicleData.name or row.vehicle or 'Unknown',
            owner_name = row.owner_name or 'Unknown',
            owner_citizenid = row.citizenid or nil,
        })
    end

    return results
end)

ps.registerCallback(resourceName..':server:saveReport', function(source, reportData)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'reports_create') then
        return { success = false, error = 'Report editing not permitted' }
    end

    local identifier = ps.getIdentifier(src)
    local originatingJob = ps.getJobName(src)
    local playerName = ps.getPlayerName(src)
    local callsign = ps.getMetadata(src, 'callsign')
    if not identifier or not originatingJob then
        return { success = false, error = 'Officer identity unavailable' }
    end

    if type(reportData) ~= 'table' or type(reportData.report) ~= 'table' then
        return { success = false, error = 'Invalid report data' }
    end
    local title = reportData.report and reportData.report.title
    if not title or title == "" then
        ps.notify(src, 'Failed to save Report: Needs a title', 'error')
        ps.warn('Report with missing/empty title from player: ' .. src .. ' Name: ' .. playerName)
        return { success = false, error = 'Report needs a title' }
    end

    local content = reportData.report and reportData.report.content
    if not content or content == "" then
        ps.notify(src, 'Failed to save Report: Needs content', 'error')
        ps.warn('Report with missing/empty content from player: ' .. src .. ' Name: ' .. playerName)
        return { success = false, error = 'Report needs content' }
    end

    -- Tags are required
    local tags = reportData.tags
    if not tags or type(tags) ~= 'table' or #tags == 0 then
        ps.notify(src, 'Failed to save Report: At least one tag is required', 'error')
        return { success = false, message = 'At least one tag is required' }
    end

    local reportId = reportData.report and tonumber(reportData.report.id) or nil
    local reportType = reportData.report and reportData.report.type or 'Incident Report'
    local creatorEmployer = originatingJob
    if type(creatorEmployer) ~= 'string' or creatorEmployer == '' then
        return { success = false, error = 'Missing employing agency' }
    end
    local newReport = reportId == nil
    -- An explicitly shared editor must not transfer the original owner.
    local existingOwner = reportId and MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",
        { reportId }) or nil

    if not CheckAuth(src) or not CheckPermission(src, 'reports_create')
        or ps.getIdentifier(src) ~= identifier or ps.getJobName(src) ~= originatingJob then
        return { success = false, error = 'Report author authorization changed' }
    end
    local citizenids = collectCitizenIds(reportData)

    for citizenid, _ in pairs(citizenids) do
        if not EnsureProfileExists(citizenid) then
            -- Profile creation failed but don't block the save - the citizen
            -- may be offline or from a different framework. The report can still
            -- reference them by citizenid and the profile will be created when
            -- they are next looked up.
            ps.warn(('[Profile Auto-Create Skipped] Player [%s] %s saving report with citizen %s who has no profile yet')
                :format(src, playerName, citizenid))
        end
    end

    if reportId then
        if not checkReportWriteAccess(src, reportId, 'reports_create') then
            ps.notify(src, 'Failed to save Report: Not found or no access', 'error')
            ps.warn(('[Failed to save] Player [%s] %s tried to save a report (%s), but it was not found or they do not have access.')
                :format(src, playerName, reportId))
            return { success = false, error = "Report not found or access denied" }
        end
    end

    if not CheckAuth(src) or not CheckPermission(src, 'reports_create')
        or ps.getIdentifier(src) ~= identifier or ps.getJobName(src) ~= originatingJob then
        return { success = false, error = 'Report author authorization changed' }
    end
    if reportId and not checkReportWriteAccess(src, reportId, 'reports_create') then
        return { success = false, error = 'Report edit authorization changed' }
    end
    if not reportId then
        local insertResult = MySQL.insert.await([[
            INSERT INTO mdt_reports (title, type, contentyjs, contentplaintext, author, authorplaintext)
            VALUES (?, ?, ?, ?, ?, ?)
        ]], {
            title,
            reportType,
            json.encode(content),
            type(content) == "string" and content or json.encode(content),
            identifier,
            (callsign or '') .. ' ' .. (playerName or 'Unknown')
        })

        if not insertResult then
            ps.notify(src, 'Failed to save Report', 'error')
            ps.warn(('[Failed to save] Player [%s] %s tried to save a report (new). Insert failed.')
                :format(src, playerName))
            return { success = false, error = 'Failed to insert report' }
        end
        reportId = insertResult
    else
        local updateSuccess = MySQL.update.await([[
            UPDATE mdt_reports
            SET title = ?, type = ?, contentyjs = ?, contentplaintext = ?, author = ?, authorplaintext = ?, dateupdated = CURRENT_TIMESTAMP
            WHERE id = ?
        ]], {
            title,
            reportType,
            json.encode(content),
            type(content) == "string" and content or json.encode(content),
            identifier,
            (callsign or '') .. ' ' .. (playerName or 'Unknown'),
            reportId
        })

        if not updateSuccess or updateSuccess == 0 then
            ps.notify(src, 'Failed to save Report', 'error')
            ps.warn(('[Failed to save] Player [%s] %s tried to save a report (%s). Update failed.')
                :format(src, playerName, reportId))
            return { success = false, error = 'Failed to update report' }
        end

        local cleanupQueries = {
            { query = "DELETE FROM mdt_reports_involved WHERE reportid = ?", values = { reportId } },
            { query = "DELETE FROM mdt_reports_charges WHERE reportid = ?", values = { reportId } },
            { query = "DELETE FROM mdt_reports_evidence WHERE reportid = ?", values = { reportId } },
            { query = "DELETE FROM mdt_reports_restrictions WHERE reportid = ?", values = { reportId } },
            { query = "DELETE FROM mdt_reports_tags WHERE reportid = ?", values = { reportId } },
            { query = "DELETE FROM mdt_report_vehicles WHERE reportid = ?", values = { reportId } },
            { query = "DELETE FROM mdt_arrests WHERE reportid = ?", values = { reportId } }
        }

        local cleanupOk, cleanupErr = pcall(function()
            return MySQL.transaction.await(cleanupQueries)
        end)
        if not cleanupOk then
            ps.warn(('[Cleanup Transaction Error] Report %s: %s'):format(reportId, tostring(cleanupErr)))
            return { success = false, error = "Failed to clean up old report data: " .. tostring(cleanupErr) }
        end
    end

    local attachmentQueries = {}
    local warrantCitizenIds = {}

    if reportData.involved and #reportData.involved > 0 then
        for _, involved in ipairs(reportData.involved) do
            table.insert(attachmentQueries, {
                query = "INSERT INTO mdt_reports_involved (reportid, citizenid, type, notes) VALUES (?, ?, ?, ?)",
                values = { reportId, involved.citizenid, involved.type, involved.notes }
            })
        end
    end

    if reportData.charges and #reportData.charges > 0 then
        for _, charge in ipairs(reportData.charges) do
            table.insert(attachmentQueries, {
                query = "INSERT INTO mdt_reports_charges (reportid, citizenid, charge, count, time, fine) VALUES (?, ?, ?, ?, ?, ?)",
                values = { reportId, charge.citizenid, charge.charge, charge.count or 1, charge.time, charge.fine }
            })
            if charge.warrant == true and charge.citizenid then
                warrantCitizenIds[charge.citizenid] = true
            end
        end
    end

    if reportData.evidence and #reportData.evidence > 0 then
        for _, evidence in ipairs(reportData.evidence) do
            local imagesJson = nil
            if evidence.images and type(evidence.images) == 'table' and #evidence.images > 0 then
                imagesJson = json.encode(evidence.images)
            end
            table.insert(attachmentQueries, {
                query = "INSERT INTO mdt_reports_evidence (reportid, title, type, content, note, stored, images) VALUES (?, ?, ?, ?, ?, ?, ?)",
                values = {
                    reportId,
                    evidence.title or '',
                    evidence.type or 'Physical',
                    evidence.content or '',
                    evidence.note or '',
                    evidence.stored or 0,
                    imagesJson
                }
            })
        end
    end

    if reportData.restrictions and #reportData.restrictions > 0 then
        for _, restriction in ipairs(reportData.restrictions) do
            -- Ownership comes from the server, never an edited client payload.
            if restriction.type ~= 'owner' then
                table.insert(attachmentQueries, {
                    query = "INSERT INTO mdt_reports_restrictions (reportid, type, identifier) VALUES (?, ?, ?)",
                    values = { reportId, restriction.type, restriction.identifier }
                })
            end
        end
    end

    if newReport or existingOwner then
        table.insert(attachmentQueries, {
            query = "INSERT INTO mdt_reports_restrictions (reportid, type, identifier) VALUES (?, 'owner', ?)",
            values = { reportId, existingOwner or creatorEmployer }
        })
    end

    -- Auto-add jobtype restriction so reports are only visible to the same job type
    local creatorJobType = ps.getJobType(src)
    if creatorJobType then
        table.insert(attachmentQueries, {
            query = "INSERT INTO mdt_reports_restrictions (reportid, type, identifier) VALUES (?, ?, ?)",
            values = { reportId, 'jobtype', creatorJobType }
        })
    end

    if reportData.tags and #reportData.tags > 0 then
        for _, tag in ipairs(reportData.tags) do
            table.insert(attachmentQueries, {
                query = "INSERT INTO mdt_reports_tags (reportid, tag) VALUES (?, ?)",
                values = { reportId, tag.tag }
            })
        end
    end

    if reportData.vehicles and #reportData.vehicles > 0 then
        for _, vehicle in ipairs(reportData.vehicles) do
            table.insert(attachmentQueries, {
                query = "INSERT INTO mdt_report_vehicles (reportid, plate, vehicle_label, owner_name, owner_citizenid) VALUES (?, ?, ?, ?, ?)",
                values = { reportId, vehicle.plate, vehicle.vehicle_label, vehicle.owner_name, vehicle.owner_citizenid }
            })
        end
    end

    if #attachmentQueries > 0 then
        local attachOk, attachResult = pcall(function()
            return MySQL.transaction.await(attachmentQueries)
        end)
        if not attachOk or not attachResult then
            ps.warn(('[Attachment Transaction Error] Report %s: %s'):format(reportId, tostring(attachResult)))
            return { success = false, error = "Failed to save report attachments: " .. tostring(attachResult) }
        end
    end

    if reportId and reportType == 'Arrest Report' and reportData.involved and #reportData.involved > 0 then
        local officerId = ps.getIdentifier(src)
        local officerName = (callsign or '') .. ' ' .. (playerName or '')
        officerName = officerName:gsub('^%s+', ''):gsub('%s+$', '')
        local arrestQueries = {}
        for _, involved in ipairs(reportData.involved) do
            if involved.type == 'suspect' and involved.citizenid then
                table.insert(arrestQueries, {
                    query = [[
                        INSERT INTO mdt_arrests (reportid, citizenid, officer_citizenid, officer_name)
                        VALUES (?, ?, ?, ?)
                    ]],
                    values = { reportId, involved.citizenid, officerId, officerName }
                })
            end
        end
        if #arrestQueries > 0 then
            MySQL.transaction.await(arrestQueries)
            if ps.auditLog then
                for _, involved in ipairs(reportData.involved) do
                    if involved.type == 'suspect' and involved.citizenid then
                        ps.auditLog(src, 'arrest_logged', 'arrest', reportId, {
                            citizenid = involved.citizenid,
                            reportId = reportId
                        })
                    end
                end
            end
        end
    end

    if reportId and next(warrantCitizenIds) ~= nil then
        local expiryDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + (7 * 24 * 60 * 60))
        local warrantQueries = {}
        for citizenid, _ in pairs(warrantCitizenIds) do
            table.insert(warrantQueries, {
                query = [[
                    INSERT INTO mdt_reports_warrants (reportid, citizenid, felonies, misdemeanors, infractions, expirydate)
                    VALUES (?, ?, 0, 0, 0, ?)
                    ON DUPLICATE KEY UPDATE expirydate = VALUES(expirydate)
                ]],
                values = { reportId, citizenid, expiryDate }
            })
        end
        MySQL.transaction.await(warrantQueries)
    end

    Cache.invalidatePrefix('reports:analytics:')

    if ps.auditLog then
        local action = reportId and reportData.report and reportData.report.id and 'report_updated' or 'report_created'
        ps.auditLog(src, action, 'report', reportId, {
            title = title,
            type = reportType
        })
    end

    Cache.invalidate('dashboard:reportStats')
    Cache.invalidate('dashboard:usageMetrics')
    return {
        success = true,
        reportId = reportId,
        message = reportId and "Report updated successfully" or "Report created successfully"
    }
end)

ps.registerCallback(resourceName..':server:updateReportContent', function(source, reportid, content, reportData)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'reports_create') then
        return { success = false, error = 'Report editing not permitted' }
    end

    if not content then
        return { success = false, error = "Missing content" }
    end

    local reportId = reportid and tonumber(reportid) or nil
    local title = (reportData and reportData.title) or "Draft Report"
    local reportType = (reportData and reportData.type) or "Incident Report"

    local identifier = ps.getIdentifier(src)
    local playerName = ps.getPlayerName(src)
    local callsign = ps.getMetadata(src, 'callsign')

    if not identifier then return { success = false, error = "Player not found" } end

    if reportId then
        if not checkReportWriteAccess(src, reportId, 'reports_create') then
            return { success = false, error = 'Report editing not permitted' }
        end
    end

    if not reportId then
        local insertResult = MySQL.insert.await([[
            INSERT INTO mdt_reports (title, type, contentyjs, contentplaintext, author, authorplaintext)
            VALUES (?, ?, ?, ?, ?, ?)
        ]], {
            title,
            reportType,
            json.encode(content),
            type(content) == "string" and content or json.encode(content),
            identifier,
            callsign .. ' ' .. playerName
        })

        if not insertResult then
            return { success = false, error = "Failed to save content" }
        end

        -- Draft creation is also report creation. Apply the employer marker
        -- and original jobtype visibility together, or discard this new draft.
        local employer = ps.getJobName(src)
        local frameworkType = ps.getJobType(src)
        if not employer or employer == '' or not frameworkType then
            MySQL.update.await('DELETE FROM mdt_reports WHERE id = ?', { insertResult })
            return { success = false, error = 'Missing agency or job type' }
        end
        local saved = MySQL.transaction.await({
            { query = "INSERT INTO mdt_reports_restrictions (reportid, type, identifier) VALUES (?, 'owner', ?)",
              values = { insertResult, employer } },
            { query = "INSERT INTO mdt_reports_restrictions (reportid, type, identifier) VALUES (?, 'jobtype', ?)",
              values = { insertResult, frameworkType } },
        })
        if not saved then
            MySQL.update.await('DELETE FROM mdt_reports WHERE id = ?', { insertResult })
            return { success = false, error = 'Failed to secure new report' }
        end

        return {
            success = true,
            reportId = insertResult,
            message = "Content saved successfully",
            isNewReport = true
        }
    end

    local updateSuccess = MySQL.update.await([[
        UPDATE mdt_reports
        SET contentyjs = ?, contentplaintext = ?, dateupdated = CURRENT_TIMESTAMP
        WHERE id = ?
    ]], {
        json.encode(content),
        type(content) == "string" and content or json.encode(content),
        reportId
    })

    if updateSuccess and updateSuccess > 0 then
        return {
            success = true,
            reportId = reportId,
            message = "Content saved successfully",
            isNewReport = false
        }
    end

    return { success = false, error = "Failed to save content" }
end)

ps.registerCallback(resourceName..':server:deleteReport', function(source, reportId)
    local src = source
    if not CheckAuth(src) then return end

    reportId = tonumber(reportId)
    if not reportId or reportId < 1 or reportId % 1 ~= 0 then
        return { success = false, error = "Missing/Invalid report ID" }
    end

    local playerName = ps.getPlayerName(src)

    if not checkReportWriteAccess(src, reportId, 'reports_delete') then
        ps.notify(src, 'Failed to delete Report: Not found or no access', 'error')
        ps.warn(('[Failed to delete] Player [%s] %s tried to delete a report (%s), but it was not found or they do not have access.')
            :format(src, playerName, reportId))
        return { success = false, error = "Report not found or access denied" }
    end

    local reportInfo = MySQL.query.await("SELECT title FROM mdt_reports WHERE id = ?", { reportId })
    local reportTitle = reportInfo and reportInfo[1] and reportInfo[1].title or "Unknown"

    if not checkReportWriteAccess(src, reportId, 'reports_delete') then return { success = false, error = 'Authorization changed' } end
    local deleted = MySQL.update.await("DELETE FROM mdt_reports WHERE id = ?", { reportId })

    if deleted and deleted > 0 then
        Cache.invalidate('dashboard:reportStats')
        Cache.invalidate('dashboard:usageMetrics')
        ps.notify(src, 'Report deleted successfully', 'success')
        ps.debug(('[Report Deleted] Player [%s] %s successfully deleted report (%s): "%s"')
            :format(src, playerName, reportId, reportTitle))

        if ps.auditLog then
            ps.auditLog(src, 'report_deleted', 'report', reportId, {
                title = reportTitle
            })
        end

        return {
            success = true,
            message = "Report deleted successfully",
            reportId = reportId
        }
    else
        ps.notify(src, 'Failed to delete report', 'error')
        ps.warn(('[Failed to delete] Player [%s] %s tried to delete report (%s). Database query failed.')
            :format(src, playerName, reportId))

        return {
            success = false,
            error = "Failed to delete report from database"
        }
    end
end)

ps.registerCallback(resourceName..':server:getAvailableTags', function(source, playerJobType)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return {} end

    local jt = getEffectiveJobType(src)
    if not jt then return {} end

    -- Pull from master mdt_tags table (report tags) filtered by job_type
    local tags = MySQL.query.await([[
        SELECT t.name, t.color, t.description,
               (SELECT COUNT(*) FROM mdt_reports_tags rt WHERE rt.tag = t.name) AS usage_count
        FROM mdt_tags t
        WHERE t.type = 'report'
          AND (t.job_type = ? OR t.job_type = 'all')
        ORDER BY t.name ASC
    ]], { jt })

    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') or getEffectiveJobType(src) ~= jt then return {} end
    return tags or {}
end)

-- Available citizen tags for the citizen-profile picker, scoped to the viewer's
-- domain (EMS sees ems + shared, police sees leo + shared).
ps.registerCallback(resourceName..':server:getCitizenTags', function(source, playerJobType)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return {} end

    -- Return the full citizen-tag dictionary (with job_type) so the UI can
    -- colour every tag; the client gates which ones a domain may add/remove.
    local tags = MySQL.query.await([[
        SELECT t.name, t.color, t.job_type, t.description
        FROM mdt_tags t
        WHERE t.type = 'citizen'
        ORDER BY t.name ASC
    ]])

    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return {} end
    return tags or {}
end)

ps.registerCallback(resourceName..':server:generateReportId', function(source)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'reports_create') then return { success = false, error = 'Unauthorized' } end

    return {
        success = true,
        reportId = nil
    }
end)

ps.registerCallback(resourceName..':server:getReportAnalytics', function(source, filters)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return { success = false, error = 'Unauthorized' } end

    local identifier = ps.getIdentifier(src)
    local job = ps.getJobName(src)
    local jobType = getEffectiveJobType(src)
    if not identifier or not job or not jobType then return { success = false, error = 'Unauthorized' } end
    if type(filters) ~= 'table' then filters = nil end

    local filterClause, filterValues = buildReportFilterClause(filters)
    filterClause = filterClause or ''

	local accessClause = buildReportAccessClause()
    local cacheKeyParts = {
        identifier or '',
        job or '',
        jobType or '',
        filters and tostring(filters.startDate) or '',
        filters and tostring(filters.endDate) or '',
        filters and tostring(filters.author) or '',
    }
    local cacheKey = 'reports:analytics:' .. table.concat(cacheKeyParts, '|')

    local cached = Cache.get(cacheKey)
    if cached then
        if not CheckAuth(src) or not CheckPermission(src, 'reports_view')
            or ps.getIdentifier(src) ~= identifier or ps.getJobName(src) ~= job
            or getEffectiveJobType(src) ~= jobType then return { success = false, error = 'Unauthorized' } end
        return { success = true, data = cached }
    end

	local incidentQuery = ([[
        SELECT COUNT(DISTINCT mr.id) AS total
        FROM mdt_reports AS mr
        LEFT JOIN mdt_reports_restrictions AS mrr ON mr.id = mrr.reportid
        WHERE %s%s
          AND mr.type = 'Incident Report'
	]]):format(accessClause, filterClause)
	local incidentParams = { jobType, jobType, jobType, identifier, job, jobType, job, identifier, job }
	for _, value in ipairs(filterValues or {}) do
		incidentParams[#incidentParams + 1] = value
	end
	local incidentRow = MySQL.single.await(incidentQuery, incidentParams)

	local arrestQuery = ([[
        SELECT COUNT(DISTINCT ma.id) AS total
        FROM mdt_arrests AS ma
        INNER JOIN mdt_reports AS mr ON mr.id = ma.reportid
        LEFT JOIN mdt_reports_restrictions AS mrr ON mr.id = mrr.reportid
        WHERE %s%s
	]]):format(accessClause, filterClause)
	local arrestParams = { jobType, jobType, jobType, identifier, job, jobType, job, identifier, job }
	for _, value in ipairs(filterValues or {}) do
		arrestParams[#arrestParams + 1] = value
	end
	local arrestRow = MySQL.single.await(arrestQuery, arrestParams)

	local warrantQuery = ([[
        SELECT COUNT(*) AS total
        FROM mdt_reports_warrants AS mw
        INNER JOIN mdt_reports AS mr ON mr.id = mw.reportid
        LEFT JOIN mdt_reports_restrictions AS mrr ON mr.id = mrr.reportid
        WHERE %s%s
          AND mw.expirydate >= NOW()
	]]):format(accessClause, filterClause)
	local warrantParams = { jobType, jobType, jobType, identifier, job, jobType, job, identifier, job }
	for _, value in ipairs(filterValues or {}) do
		warrantParams[#warrantParams + 1] = value
	end
	local warrantRow = MySQL.single.await(warrantQuery, warrantParams)

    local data = {
        incidents = tonumber(incidentRow and incidentRow.total) or 0,
        arrests = tonumber(arrestRow and arrestRow.total) or 0,
        warrants = tonumber(warrantRow and warrantRow.total) or 0,
    }

    if not CheckAuth(src) or not CheckPermission(src, 'reports_view')
        or ps.getIdentifier(src) ~= identifier or ps.getJobName(src) ~= job
        or getEffectiveJobType(src) ~= jobType then return { success = false, error = 'Unauthorized' } end
    Cache.set(cacheKey, data, 15)

    return {
        success = true,
        data = data
    }
end)

ps.registerCallback(resourceName .. ':server:getReportsByPlate', function(source, plate)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'reports_view') then return {} end

    if type(plate) ~= 'string' or plate == '' then
        return {}
    end

    local requesterCitizenId = ps.getIdentifier(src)
    local requesterJob = ps.getJobName(src)
    if not requesterCitizenId or not requesterJob then return {} end
    local rows = MySQL.query.await([[
        SELECT
            mr.id,
            mr.title,
            mr.type,
            mr.datecreated,
            mr.authorplaintext
        FROM mdt_report_vehicles mrv
        INNER JOIN mdt_reports mr ON mr.id = mrv.reportid
        WHERE mrv.plate = ?
        ORDER BY mr.datecreated DESC
        LIMIT 20
    ]], { plate })

    if ps.getIdentifier(src) ~= requesterCitizenId or ps.getJobName(src) ~= requesterJob then return {} end
    local visible = {}
    for _, row in ipairs(rows or {}) do
        if CanReadMdtReport(src, row.id) then visible[#visible + 1] = row end
    end
    if not CheckAuth(src) or not CheckPermission(src, 'reports_view')
        or ps.getIdentifier(src) ~= requesterCitizenId
        or ps.getJobName(src) ~= requesterJob then return {} end
    return visible
end)

-- Stage 4 discovery: named report grants are managed only by the report's
-- originating employer. Ownerless legacy reports require reconciliation.
ps.registerCallback(resourceName .. ':server:grantReportDisclosure', function(source, reportId, recipientCid, purpose)
    local src,id=source,tonumber(reportId)
    if not id or type(recipientCid)~='string' or #recipientCid<2 or #recipientCid>64
        or type(purpose)~='string' or #purpose<10 or #purpose>255 then
        return {success=false,error='Valid report, recipient and purpose required'}
    end
    if not CheckAuth(src) or not CheckPermission(src,'reports_delete') then
        return {success=false,error='Unauthorized'}
    end
    local actor,employer=ps.getIdentifier(src),ps.getJobName(src)
    if not actor or not employer then return {success=false,error='Unauthorized'} end
    local owner=MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",{id})
    if not owner or owner~=employer then return {success=false,error='Originating employer required'} end
    local recipientJob=MySQL.scalar.await([[
        SELECT JSON_UNQUOTE(JSON_EXTRACT(job, '$.name'))
        FROM players WHERE citizenid = ? LIMIT 1
    ]],{recipientCid})
    if not recipientJob or recipientJob=='' or not CheckAuth(src) or not CheckPermission(src,'reports_delete')
        or ps.getIdentifier(src)~=actor or ps.getJobName(src)~=employer then
        return {success=false,error='Authorization changed'}
    end
    local ok,grantId=pcall(MySQL.insert.await,[[
        INSERT INTO mdt_report_disclosures
            (report_id,recipient_citizenid,recipient_job,purpose,granted_by_citizenid,granted_by_job)
        SELECT r.id, ?, ?, ?, ?, ?
        FROM mdt_reports r WHERE r.id = ?
          AND EXISTS (SELECT 1 FROM mdt_reports_restrictions o
            WHERE o.reportid = r.id AND o.type = 'owner' AND o.identifier = ?)
    ]],{recipientCid,recipientJob,purpose,actor,employer,id,employer})
    if not ok or not tonumber(grantId) or tonumber(grantId) <= 0 then return {success=false,error='Disclosure storage unavailable'} end
    if ps.auditLog then ps.auditLog(src,'report_disclosure_granted','report',id,
        {grant_id=grantId,recipient=recipientCid,purpose=purpose}) end
    return {success=true,grantId=grantId}
end)

ps.registerCallback(resourceName .. ':server:revokeReportDisclosure', function(source, grantId)
    local src,id=source,tonumber(grantId)
    if not id or not CheckAuth(src) or not CheckPermission(src,'reports_delete') then
        return {success=false,error='Unauthorized'}
    end
    local actor,employer=ps.getIdentifier(src),ps.getJobName(src)
    if not actor or not employer then return {success=false,error='Unauthorized'} end
    local ok,count=pcall(MySQL.update.await,[[
        UPDATE mdt_report_disclosures g
        INNER JOIN mdt_reports_restrictions o ON o.reportid = g.report_id
          AND o.type = 'owner'
        SET g.revoked_at = NOW(), g.revoked_by_citizenid = ?
        WHERE g.id = ? AND o.identifier = ? AND g.revoked_at IS NULL
    ]],{actor,id,employer})
    if not ok or tonumber(count)~=1 then return {success=false,error='Grant not found or inaccessible'} end
    if ps.auditLog then ps.auditLog(src,'report_disclosure_revoked','report_disclosure',id,{employer=employer}) end
    return {success=true}
end)

ps.registerCallback(resourceName .. ':server:getDisclosedReports', function(source)
    local src=source
    if not CheckAuth(src) or not CheckPermission(src,'reports_view') then return {} end
    local actor,employer=ps.getIdentifier(src),ps.getJobName(src)
    if not actor or not employer then return {} end
    local ok,rows=pcall(MySQL.query.await,[[
        SELECT r.id,r.title,r.type,r.datecreated,g.purpose,g.granted_at
        FROM mdt_report_disclosures g
        INNER JOIN mdt_reports r ON r.id = g.report_id
        WHERE g.recipient_citizenid = ? AND g.recipient_job = ? AND g.revoked_at IS NULL
          AND (g.expires_at IS NULL OR g.expires_at > NOW())
        ORDER BY g.granted_at DESC LIMIT 100
    ]],{actor,employer})
    if not CheckAuth(src) or not CheckPermission(src,'reports_view')
        or ps.getIdentifier(src)~=actor or ps.getJobName(src)~=employer then return {} end
    return ok and rows or {}
end)

ps.registerCallback(resourceName .. ':server:getReportDisclosures', function(source, reportId)
    local src,id=source,tonumber(reportId)
    if not id or not CheckAuth(src) or not CheckPermission(src,'reports_delete') then return {} end
    local actor,employer=ps.getIdentifier(src),ps.getJobName(src)
    local owner=MySQL.scalar.await(
        "SELECT identifier FROM mdt_reports_restrictions WHERE reportid = ? AND type = 'owner' LIMIT 1",{id})
    if not employer or owner~=employer then return {} end
    local ok,rows=pcall(MySQL.query.await,[[
        SELECT id,recipient_citizenid,purpose,granted_at,expires_at,revoked_at
        FROM mdt_report_disclosures WHERE report_id = ?
        ORDER BY granted_at DESC LIMIT 100
    ]],{id})
    if not CheckAuth(src) or not CheckPermission(src,'reports_delete')
        or ps.getIdentifier(src)~=actor or ps.getJobName(src)~=employer then return {} end
    return ok and rows or {}
end)
