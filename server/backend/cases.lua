local resourceName = tostring(GetCurrentResourceName())

local function getCaseScope(source)
    local access = GetMdtAccess(source)
    if not access or not access.authorized or type(access.agency) ~= 'string'
        or access.agency == '' then return nil end
    -- Court staff may read statewide case files; ordinary departmental MDT
    -- access does not imply visibility into another employer's cases.
    if access.interfaceId == 'sadoj' and access.jobType == 'doj' then
        return { statewide = true, agency = access.agency }
    end
    return { statewide = false, agency = access.agency }
end

local function canAccessCaseId(source, caseId)
    local id = tonumber(caseId)
    local scope = getCaseScope(source)
    if not id or id ~= id or id == math.huge or id <= 0 or id % 1 ~= 0 or not scope then return false end
    local row = MySQL.single.await('SELECT assigned_department FROM mdt_cases WHERE id = ?', { id })
    if not row then return false end
    local current = getCaseScope(source)
    return current ~= nil and current.agency == scope.agency
        and current.statewide == scope.statewide
        and (current.statewide or row.assigned_department == current.agency)
end

local function hasCaseDisclosure(source, caseId)
    local actor, employer = ps.getIdentifier(source), ps.getJobName(source)
    local access = GetMdtAccess(source)
    if type(actor) ~= 'string' or actor == ''
        or type(employer) ~= 'string' or employer == ''
        or not access or not access.authorized
        or not CheckAuth(source) or not CheckPermission(source, 'cases_view') then return false end
    local row = MySQL.single.await([[
        SELECT id FROM mdt_case_disclosures
        WHERE case_id = ? AND recipient_citizenid = ? AND recipient_job = ?
          AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())
        LIMIT 1
    ]], {caseId, actor, employer})
    return row ~= nil and CheckAuth(source)
        and CheckPermission(source, 'cases_view') and ps.getIdentifier(source) == actor
        and ps.getJobName(source) == employer
end

local function buildCaseNumber(id)
    local year = os.date('%Y')
    return ('CASE-%s-%05d'):format(year, id)
end

local function normalizeStatus(status)
    local value = status and tostring(status):lower() or 'open'
    if value == 'open' or value == 'in_progress' or value == 'closed' then
        return value
    end
    if value == 'in progress' then
        return 'in_progress'
    end
    return 'open'
end

local function getOfficerDisplayName(src)
    local callsign = ps.getMetadata(src, 'callsign')
    local name = ps.getPlayerName(src) or 'Unknown'
    if callsign and callsign ~= '' then
        return callsign .. ' ' .. name
    end
    return name
end

ps.registerCallback(resourceName .. ':server:createCase', function(source, payload)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_create') then return { success = false, error = 'Unauthorized' } end

    if type(payload) ~= 'table' then return { success = false, error = 'Invalid case payload' } end
    local title = payload.title or 'Untitled Case'
    local summary = payload.summary or ''
    if type(title) ~= 'string' or not title:find('%S') or #title > 255
        or type(summary) ~= 'string' or #summary > 20000 then
        return { success = false, error = 'Invalid case title or summary' }
    end
    if payload.status ~= nil and type(payload.status) ~= 'string' then
        return { success = false, error = 'Invalid case status' }
    end
    local status = normalizeStatus(payload.status)
    local priority = payload.priority or 'medium'
    if type(priority) ~= 'string' or not ({ low = true, medium = true, high = true, critical = true })[priority] then
        return { success = false, error = 'Invalid case priority' }
    end
    local scope = getCaseScope(src)
    if not scope then return { success = false, error = 'Unauthorized' } end
    local department = scope.statewide and (payload.department or scope.agency) or scope.agency
    if type(department) ~= 'string' or not department:find('%S') or #department > 64 then
        return { success = false, error = 'Invalid department' }
    end

    local citizenid = ps.getIdentifier(src)
    if type(citizenid) ~= 'string' or citizenid == '' then
        return { success = false, error = 'Missing citizen id' }
    end

    local createdByName = getOfficerDisplayName(src)

    local caseId = MySQL.insert.await([[INSERT INTO mdt_cases
        (case_number, title, summary, status, priority, assigned_department, created_by, created_by_name)
        VALUES ('', ?, ?, ?, ?, ?, ?, ?)
    ]], { title, summary, status, priority, department, citizenid, createdByName })

    if not caseId or tonumber(caseId) <= 0 then
        return { success = false, error = 'Failed to create case' }
    end

    local caseNumber = buildCaseNumber(caseId)
    local numbered = MySQL.update.await('UPDATE mdt_cases SET case_number = ? WHERE id = ?', { caseNumber, caseId })
    if not numbered or numbered < 1 then
        return { success = false, error = 'Failed to assign case number' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_created', 'case', caseId, {
            title = title,
            status = status,
            priority = priority
        })
    end

    return {
        success = true,
        caseId = caseId,
        caseNumber = caseNumber
    }
end)

ps.registerCallback(resourceName .. ':server:getCases', function(source, page, filters)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_view') then return { cases = {}, hasMore = false } end

    page = tonumber(page) or 1
    if page ~= page or page == math.huge or page < 1 then page = 1 end
    page = math.min(math.floor(page), 10000)
    local limit = tonumber(Config.Pagination and Config.Pagination.Cases) or 20
    if limit ~= limit or limit == math.huge or limit == -math.huge then limit = 20 end
    limit = math.max(1, math.min(100, math.floor(limit)))
    local offset = (page - 1) * limit

    local scope = getCaseScope(src)
    local actorCid = ps.getIdentifier(src)
    if not scope or not actorCid then return { cases = {}, hasMore = false } end
    if type(filters) ~= 'table' then filters = {} end
    local clauses = {}
    local values = {}
    if not scope.statewide then
        clauses[#clauses + 1] = 'mc.assigned_department = ?'
        values[#values + 1] = scope.agency
    end

    if type(filters.status) == 'string' and filters.status ~= '' and #filters.status <= 40 then
        clauses[#clauses + 1] = 'mc.status = ?'
        values[#values + 1] = normalizeStatus(filters.status)
    end

    if type(filters.department) == 'string' and filters.department ~= '' and #filters.department <= 64 then
        clauses[#clauses + 1] = 'mc.assigned_department = ?'
        values[#values + 1] = filters.department
    end

    local whereClause = ''
    if #clauses > 0 then
        whereClause = 'WHERE ' .. table.concat(clauses, ' AND ')
    end

    values[#values + 1] = limit
    values[#values + 1] = offset

    local rows = MySQL.query.await(([[
        SELECT mc.id, mc.case_number, mc.title, mc.summary, mc.status, mc.priority,
               mc.assigned_department, mc.created_by, mc.created_by_name,
               mc.created_at, mc.updated_at,
               mp.fullname AS primary_officer_name,
               mp.callsign AS primary_officer_callsign
        FROM mdt_cases mc
        LEFT JOIN mdt_case_officers mco ON mco.case_id = mc.id AND mco.role = 'primary'
        LEFT JOIN mdt_profiles mp ON mp.citizenid COLLATE utf8mb4_general_ci = mco.citizenid COLLATE utf8mb4_general_ci
        %s
        ORDER BY mc.updated_at DESC
        LIMIT ? OFFSET ?
    ]]):format(whereClause), values)

    -- A source ID can change character, employer or duty while SQL is
    -- suspended. Do not return the previous department's case list.
    local current = getCaseScope(src)
    if not CheckAuth(src) or not CheckPermission(src, 'cases_view')
        or ps.getIdentifier(src) ~= actorCid
        or not current or current.agency ~= scope.agency
        or current.statewide ~= scope.statewide then
        return { cases = {}, hasMore = false }
    end
    return {
        cases = rows or {},
        hasMore = rows and #rows >= limit or false
    }
end)

ps.registerCallback(resourceName .. ':server:getCase', function(source, caseId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_view') then return { success = false, error = 'Unauthorized' } end

    caseId = tonumber(caseId)
    if not caseId or caseId ~= caseId or caseId == math.huge
        or caseId <= 0 or caseId % 1 ~= 0 then
        return { success = false, error = 'Invalid case id' }
    end

    local scope = getCaseScope(src)
    local actorCid = ps.getIdentifier(src)
    if not scope or not actorCid then return { success = false, error = 'Unauthorized' } end
    local caseRow = MySQL.single.await('SELECT * FROM mdt_cases WHERE id = ?', { caseId })
    if not caseRow or (not scope.statewide and caseRow.assigned_department ~= scope.agency
        and not hasCaseDisclosure(src, caseId)) then
        return { success = false, error = 'Case not found or inaccessible' }
    end

    local officers = MySQL.query.await([[
        SELECT mco.citizenid, mco.role, mco.assigned_by, mco.assigned_at,
               mp.fullname, mp.callsign, mp.badge_number, mp.rank, mp.department
        FROM mdt_case_officers mco
        LEFT JOIN mdt_profiles mp ON mp.citizenid COLLATE utf8mb4_general_ci = mco.citizenid COLLATE utf8mb4_general_ci
        WHERE mco.case_id = ?
        ORDER BY mco.assigned_at ASC
    ]], { caseId })

    local attachments = MySQL.query.await([[
        SELECT id, type, url, label, uploaded_by, uploaded_at
        FROM mdt_case_attachments
        WHERE case_id = ?
        ORDER BY uploaded_at DESC
    ]], { caseId })

    local reports = MySQL.query.await([[
        SELECT mr.id, mr.title, mr.type, mr.datecreated
        FROM mdt_case_reports mcr
        INNER JOIN mdt_reports mr ON mr.id = mcr.report_id
        WHERE mcr.case_id = ?
        ORDER BY mr.datecreated DESC
    ]], { caseId })

    if type(CanReadMdtReport) ~= 'function' then
        reports = {}
    else
        local readable = {}
        for _, report in ipairs(reports or {}) do
            if CanReadMdtReport(src, report.id) then readable[#readable + 1] = report end
        end
        reports = readable
    end

    local notes = MySQL.query.await([[
        SELECT id, content, author_name, created_at
        FROM mdt_case_notes
        WHERE case_id = ?
        ORDER BY created_at DESC
    ]], { caseId })

    -- Each detail section is queried separately; reject stale grants, duty
    -- loss or employer changes before returning the combined case payload.
    local current = getCaseScope(src)
    if not CheckAuth(src) or not CheckPermission(src, 'cases_view') or not current
        or ps.getIdentifier(src) ~= actorCid
        or current.agency ~= scope.agency or current.statewide ~= scope.statewide then
        return {success=false,error='Authorization changed'}
    end
    if not current.statewide and caseRow.assigned_department ~= current.agency
        and not hasCaseDisclosure(src, caseId) then
        return {success=false,error='Disclosure expired or revoked'}
    end
    if caseRow.assigned_department ~= current.agency and ps.auditLog then
        ps.auditLog(src,'case_disclosure_accessed','case',caseId,
            {recipient=ps.getIdentifier(src),originating_department=caseRow.assigned_department})
    end
    -- A named disclosure permits the case summary, NOT automatic access to
    -- internal notes, uploaded attachments, linked reports, or evidence.
    -- Each protected artifact requires its own explicit grant.
    local externalRecipient = not current.statewide
        and caseRow.assigned_department ~= current.agency
    return {
        success = true,
        data = {
            case = caseRow,
            officers = externalRecipient and {} or (officers or {}),
            attachments = externalRecipient and {} or (attachments or {}),
            evidence = {},
            reports = externalRecipient and {} or (reports or {}),
            notes = externalRecipient and {} or (notes or {})
        }
    }
end)

ps.registerCallback(resourceName .. ':server:linkReportToCase', function(source, reportId, caseId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Unauthorized' } end
    if not canAccessCaseId(src, caseId) then return { success = false, error = 'Case not found or inaccessible' } end

    reportId = tonumber(reportId)
    caseId = tonumber(caseId)
    if not reportId or not caseId or reportId ~= reportId or caseId ~= caseId
        or reportId == math.huge or caseId == math.huge
        or reportId <= 0 or caseId <= 0 or reportId % 1 ~= 0 or caseId % 1 ~= 0 then
        return { success = false, error = 'Invalid report or case' }
    end

    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report not accessible' }
    end
    -- Validate report exists before linking
    local reportExists = MySQL.single.await('SELECT id FROM mdt_reports WHERE id = ?', { reportId })
    if not reportExists then
        return { success = false, error = 'Report #' .. tostring(reportId) .. ' does not exist' }
    end

    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or not canAccessCaseId(src, caseId) or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Authorization changed' }
    end
    local actor = ps.getIdentifier(src)
    if type(actor) ~= 'string' or actor == '' then
        return { success = false, error = 'Missing report link author' }
    end
    local linked = MySQL.insert.await([[
        INSERT IGNORE INTO mdt_case_reports (case_id, report_id, linked_by)
        VALUES (?, ?, ?)
    ]], { caseId, reportId, actor })
    if linked == nil then return { success = false, error = 'Report link not saved' } end
    local exists = MySQL.scalar.await('SELECT 1 FROM mdt_case_reports WHERE case_id = ? AND report_id = ? LIMIT 1', { caseId, reportId })
    if not exists then return { success = false, error = 'Report link not saved' } end
    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:unlinkReportFromCase', function(source, reportId, caseId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Unauthorized' } end
    if not canAccessCaseId(src, caseId) then return { success = false, error = 'Case not found or inaccessible' } end

    reportId = tonumber(reportId)
    caseId = tonumber(caseId)
    if not reportId or not caseId or reportId ~= reportId or caseId ~= caseId
        or reportId == math.huge or caseId == math.huge or reportId <= 0 or caseId <= 0
        or reportId % 1 ~= 0 or caseId % 1 ~= 0 then
        return { success = false, error = 'Invalid report or case' }
    end

    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report not accessible' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or not canAccessCaseId(src, caseId) or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Authorization changed' }
    end
    local deleted = MySQL.update.await('DELETE FROM mdt_case_reports WHERE case_id = ? AND report_id = ?', { caseId, reportId })
    return { success = deleted ~= nil and deleted > 0 }
end)

ps.registerCallback(resourceName .. ':server:getCaseEvidencePage', function(source, caseId, page, limit)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_view')
        or not CheckPermission(src, 'cases_view') then return { success = false, error = 'Unauthorized' } end
    if not canAccessCaseId(src, caseId) then return { success = false, error = 'Case not found or inaccessible' } end

    caseId = tonumber(caseId)
    if not caseId or caseId ~= caseId or caseId == math.huge
        or caseId <= 0 or caseId % 1 ~= 0 then
        return { success = false, error = 'Invalid case id' }
    end

    page = tonumber(page) or 1
    limit = tonumber(limit) or 5
    if page ~= page or page == math.huge or page == -math.huge or page < 1 then page = 1 end
    if limit ~= limit or limit == math.huge or limit == -math.huge or limit < 1 then limit = 5 end
    page = math.min(10000, math.floor(page))
    limit = math.min(100, math.floor(limit))
    local offset = (page - 1) * limit

    local totalRow = MySQL.single.await('SELECT COUNT(id) as total FROM mdt_evidence_items WHERE case_id = ?', { caseId })
    local total = totalRow and totalRow.total or 0

    local evidence = MySQL.query.await([[
        SELECT id, title, type, serial, notes, location, stash_id, stored, last_holder, created_by, created_at, updated_at
        FROM mdt_evidence_items
        WHERE case_id = ?
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ]], { caseId, limit, offset })

    -- Batch-load all images for returned evidence items (avoids N+1)
    if evidence and #evidence > 0 then
        local ids = {}
        local idLookup = {}
        for _, item in ipairs(evidence) do
            ids[#ids + 1] = item.id
            idLookup[item.id] = item
            item.images = {}
        end

        local placeholders = string.rep('?,', #ids - 1) .. '?'
        local images = MySQL.query.await(([[
            SELECT id, evidence_id, url, label, uploaded_by, uploaded_at
            FROM mdt_evidence_images
            WHERE evidence_id IN (%s)
            ORDER BY uploaded_at DESC
        ]]):format(placeholders), ids)

        for _, img in ipairs(images or {}) do
            local parent = idLookup[img.evidence_id]
            if parent then
                parent.images[#parent.images + 1] = {
                    id = img.id,
                    url = img.url,
                    label = img.label,
                    uploaded_by = img.uploaded_by,
                    uploaded_at = img.uploaded_at
                }
            end
        end
    end

    if not CheckAuth(src) or not CheckPermission(src, 'evidence_view')
        or not CheckPermission(src, 'cases_view')
        or not canAccessCaseId(src, caseId) then
        return { success = false, error = 'Authorization changed' }
    end
    return {
        success = true,
        data = {
            items = evidence or {},
            total = total,
            page = page,
            limit = limit
        }
    }
end)

ps.registerCallback(resourceName .. ':server:updateCase', function(source, caseId, payload)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Unauthorized' } end

    caseId = tonumber(caseId)
    if not caseId or caseId ~= caseId or caseId == math.huge
        or caseId <= 0 or caseId % 1 ~= 0 then
        return { success = false, error = 'Invalid case id' }
    end

    local scope = getCaseScope(src)
    if not scope then return { success = false, error = 'Unauthorized' } end
    local existing = MySQL.single.await('SELECT assigned_department FROM mdt_cases WHERE id = ?', { caseId })
    if not existing or (not scope.statewide and existing.assigned_department ~= scope.agency) then
        return { success = false, error = 'Case not found or inaccessible' }
    end
    if type(payload) ~= 'table' then return { success = false, error = 'Invalid case payload' } end
    if payload.department ~= nil and (type(payload.department) ~= 'string'
        or payload.department == '' or #payload.department > 64) then
        return { success = false, error = 'Invalid department' }
    end
    if payload.department and not scope.statewide and payload.department ~= scope.agency then
        return { success = false, error = 'Cross-department reassignment denied' }
    end
    if payload.status ~= nil and type(payload.status) ~= 'string' then
        return { success = false, error = 'Invalid case status' }
    end
    local status = payload.status and normalizeStatus(payload.status) or nil
    local priority = payload.priority
    if priority ~= nil and (type(priority) ~= 'string'
        or not ({ low = true, medium = true, high = true, critical = true })[priority]) then
        return { success = false, error = 'Invalid case priority' }
    end

    local updates = {}
    local values = {}

    if payload.title ~= nil and (type(payload.title) ~= 'string' or not payload.title:find('%S') or #payload.title > 255) then
        return { success = false, error = 'Invalid case title' }
    end
    if payload.title then
        updates[#updates + 1] = 'title = ?'
        values[#values + 1] = payload.title
    end

    if payload.summary ~= nil and (type(payload.summary) ~= 'string' or #payload.summary > 20000) then
        return { success = false, error = 'Invalid case summary' }
    end
    if payload.summary then
        updates[#updates + 1] = 'summary = ?'
        values[#values + 1] = payload.summary
    end

    if status then
        updates[#updates + 1] = 'status = ?'
        values[#values + 1] = status
    end

    if priority then
        updates[#updates + 1] = 'priority = ?'
        values[#values + 1] = priority
    end

    if payload.department then
        updates[#updates + 1] = 'assigned_department = ?'
        values[#values + 1] = payload.department
    end

    if #updates == 0 then
        return { success = false, error = 'No updates provided' }
    end

    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or not canAccessCaseId(src, caseId) then
        return { success = false, error = 'Authorization changed' }
    end
    values[#values + 1] = caseId
    local success = MySQL.update.await(('UPDATE mdt_cases SET %s WHERE id = ?'):format(table.concat(updates, ', ')), values)

    if not success or success < 1 then
        return { success = false, error = 'Case update not saved' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_updated', 'case', caseId, payload)
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:deleteCase', function(source, caseId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_delete') then return { success = false, error = 'Unauthorized' } end

    caseId = tonumber(caseId)
    if not caseId or caseId ~= caseId or caseId == math.huge
        or caseId <= 0 or caseId % 1 ~= 0 then
        return { success = false, error = 'Invalid case id' }
    end

    local scope = getCaseScope(src)
    if not scope then return { success = false, error = 'Unauthorized' } end
    local caseRow = MySQL.single.await('SELECT title, assigned_department FROM mdt_cases WHERE id = ?', { caseId })
    if not caseRow or (not scope.statewide and caseRow.assigned_department ~= scope.agency) then
        return { success = false, error = 'Case not found or inaccessible' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'cases_delete')
        or not canAccessCaseId(src, caseId) then
        return { success = false, error = 'Authorization changed' }
    end
    local success = MySQL.update.await('DELETE FROM mdt_cases WHERE id = ?', { caseId })

    if not success or success < 1 then
        return { success = false, error = 'Case not found or already deleted' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_deleted', 'case', caseId, {
            title = caseRow and caseRow.title or ''
        })
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:assignCaseOfficer', function(source, caseId, officerCitizenId, role)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Unauthorized' } end
    if not canAccessCaseId(src, caseId) then return { success = false, error = 'Case not found or inaccessible' } end

    caseId = tonumber(caseId)
    if not caseId or caseId ~= caseId or caseId == math.huge or caseId == -math.huge
        or caseId <= 0 or caseId % 1 ~= 0 or type(officerCitizenId) ~= 'string'
        or not officerCitizenId:find('%S') or #officerCitizenId > 64 then
        return { success = false, error = 'Invalid case or officer' }
    end

    role = role or 'assisting'
    if type(role) ~= 'string' or #role > 40 or not role:find('%S') then
        return { success = false, error = 'Invalid officer role' }
    end

    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or not canAccessCaseId(src, caseId) then
        return { success = false, error = 'Authorization changed' }
    end
    local actor = ps.getIdentifier(src)
    if type(actor) ~= 'string' or actor == '' then
        return { success = false, error = 'Missing assigning officer identity' }
    end
    if ps.getIdentifier(src) ~= actor or not CheckAuth(src)
        or not CheckPermission(src, 'cases_edit') or not canAccessCaseId(src, caseId) then
        return { success = false, error = 'Case assignment authorization changed' }
    end
    local insertId = MySQL.insert.await([[
        INSERT INTO mdt_case_officers (case_id, citizenid, role, assigned_by)
        VALUES (?, ?, ?, ?)
    ]], { caseId, officerCitizenId, role, actor })

    if not insertId then
        return { success = false, error = 'Failed to assign officer' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_officer_assigned', 'case', caseId, {
            officer = officerCitizenId,
            role = role
        })
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:removeCaseOfficer', function(source, caseId, officerCitizenId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Unauthorized' } end
    if not canAccessCaseId(src, caseId) then return { success = false, error = 'Case not found or inaccessible' } end

    caseId = tonumber(caseId)
    if not caseId or caseId ~= caseId or caseId == math.huge
        or caseId <= 0 or caseId % 1 ~= 0 or type(officerCitizenId) ~= 'string'
        or not officerCitizenId:find('%S') or #officerCitizenId > 64 then
        return { success = false, error = 'Invalid case or officer' }
    end

    if type(officerCitizenId) ~= 'string' or not officerCitizenId:find('%S') then
        return { success = false, error = 'Invalid officer identity' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or not canAccessCaseId(src, caseId) then
        return { success = false, error = 'Authorization changed' }
    end
    local success = MySQL.update.await([[
        DELETE FROM mdt_case_officers WHERE case_id = ? AND citizenid = ?
    ]], { caseId, officerCitizenId })

    if not success or success < 1 then
        return { success = false, error = 'Officer not assigned to case' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_officer_removed', 'case', caseId, {
            officer = officerCitizenId
        })
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:addCaseAttachment', function(source, caseId, attachment)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Unauthorized' } end
    if not canAccessCaseId(src, caseId) then return { success = false, error = 'Case not found or inaccessible' } end

    caseId = tonumber(caseId)
    if not caseId or caseId ~= caseId or caseId == math.huge
        or caseId <= 0 or caseId % 1 ~= 0 or type(attachment) ~= 'table'
        or type(attachment.url) ~= 'string' or not attachment.url:find('%S')
        or #attachment.url > 2048 then
        return { success = false, error = 'Invalid attachment' }
    end

    if attachment.type ~= nil and (type(attachment.type) ~= 'string'
        or not attachment.type:find('%S') or #attachment.type > 40) then
        return { success = false, error = 'Invalid attachment type' }
    end
    if attachment.label ~= nil and (type(attachment.label) ~= 'string' or #attachment.label > 255) then
        return { success = false, error = 'Invalid attachment label' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or not canAccessCaseId(src, caseId) then
        return { success = false, error = 'Authorization changed' }
    end
    local uploader = ps.getIdentifier(src)
    if type(uploader) ~= 'string' or uploader == '' then
        return { success = false, error = 'Missing attachment uploader identity' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or not canAccessCaseId(src, caseId) then
        return { success = false, error = 'Attachment authorization changed' }
    end
    local attachmentId = MySQL.insert.await([[
        INSERT INTO mdt_case_attachments (case_id, type, url, label, uploaded_by)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        caseId,
        attachment.type or 'document',
        attachment.url,
        attachment.label or '',
        uploader
    })

    if not attachmentId then
        return { success = false, error = 'Failed to add attachment' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_attachment_added', 'case', caseId, attachment)
    end

    return { success = true, id = attachmentId }
end)

ps.registerCallback(resourceName .. ':server:addCaseAttachmentUpload', function(source, caseId, attachment)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Unauthorized' } end
    if not canAccessCaseId(src, caseId) then return { success = false, error = 'Case not found or inaccessible' } end

    caseId = tonumber(caseId)
    if not caseId or caseId ~= caseId or caseId == math.huge
        or caseId <= 0 or caseId % 1 ~= 0 or type(attachment) ~= 'table'
        or type(attachment.data) ~= 'string' or attachment.data == ''
        or type(attachment.filename) ~= 'string' or attachment.filename == '' then
        return { success = false, error = 'Invalid attachment payload' }
    end

    local data = attachment.data
    if #data > 15 * 1024 * 1024 then
        return { success = false, error = 'Attachment exceeds upload limit' }
    end
    local filename = attachment.filename
    if #filename > 255 or filename:find('%c')
        or filename:find(string.rep('.', 2), 1, true) or filename:find('[/\\]') then
        return { success = false, error = 'Invalid filename' }
    end
    local contentType = attachment.contentType or ''
    local label = attachment.label or ''
    local attachmentType = attachment.type or 'document'
    if type(contentType) ~= 'string' or #contentType > 128
        or type(label) ~= 'string' or #label > 255
        or type(attachmentType) ~= 'string' or not attachmentType:find('%S')
        or #attachmentType > 40 then
        return { success = false, error = 'Invalid attachment metadata' }
    end

    if Config.Uploads and Config.Uploads.AllowedAttachmentTypes then
        local allowed = false
        for _, mime in ipairs(Config.Uploads.AllowedAttachmentTypes) do
            if mime == contentType then
                allowed = true
                break
            end
        end
        if not allowed then
            return { success = false, error = 'Unsupported attachment type' }
        end
    end

    if not FiveManageUpload then
        return { success = false, error = 'FiveManage upload not available' }
    end

    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or not canAccessCaseId(src, caseId) then
        return { success = false, error = 'Authorization changed' }
    end
    local uploader = ps.getIdentifier(src)
    if type(uploader) ~= 'string' or uploader == '' then
        return { success = false, error = 'Missing attachment uploader identity' }
    end
    local publicUrl, uploadError = FiveManageUpload(data, filename)
    if type(publicUrl) ~= 'string' or publicUrl == '' or #publicUrl > 2048 then
        return { success = false, error = 'Upload failed: ' .. tostring(uploadError or 'Invalid URL') }
    end

    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or not canAccessCaseId(src, caseId) or ps.getIdentifier(src) ~= uploader then
        return { success = false, error = 'Authorization changed' }
    end
    local attachmentId = MySQL.insert.await([[
        INSERT INTO mdt_case_attachments (case_id, type, url, label, uploaded_by)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        caseId,
        attachmentType,
        publicUrl,
        label,
        uploader
    })

    if not attachmentId then
        return { success = false, error = 'Failed to save attachment' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_attachment_uploaded', 'case', caseId, {
            label = label,
            url = publicUrl,
            contentType = contentType
        })
    end

    return { success = true, id = attachmentId, url = publicUrl }
end)

ps.registerCallback(resourceName .. ':server:removeCaseAttachment', function(source, attachmentId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Unauthorized' } end

    attachmentId = tonumber(attachmentId)
    if not attachmentId or attachmentId ~= attachmentId or attachmentId == math.huge
        or attachmentId <= 0 or attachmentId % 1 ~= 0 then
        return { success = false, error = 'Invalid attachment id' }
    end

    local attachment = MySQL.single.await('SELECT url, case_id FROM mdt_case_attachments WHERE id = ?', { attachmentId })
    if not attachment or not canAccessCaseId(src, attachment.case_id) then
        return { success = false, error = 'Case attachment not found or inaccessible' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or not canAccessCaseId(src, attachment.case_id) then
        return { success = false, error = 'Authorization changed' }
    end
    local success = MySQL.update.await('DELETE FROM mdt_case_attachments WHERE id = ?', { attachmentId })

    if not success or success < 1 then
        return { success = false, error = 'Attachment not found' }
    end

    if attachment and type(attachment.url) == 'string'
        and attachment.url:find('^/ps%-mdt%-v3/uploads/') then
        local path = attachment.url:gsub('^/ps%-mdt%-v3/', '')
        if path ~= '' and not path:find('..', 1, true)
            and not path:find('\\', 1, true) then
            os.remove(path)
        end
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_attachment_removed', 'case_attachment', attachmentId, {
            caseId = attachment and attachment.case_id or nil
        })
    end

    return { success = true }
end)

-- :server:addEvidenceItem is registered only in server/backend/evidence.lua.

-- :server:removeEvidenceImage is registered only in server/backend/evidence.lua.

-- :server:updateEvidenceItem is registered only in server/backend/evidence.lua.

-- :server:transferEvidenceItem is registered only in server/backend/evidence.lua.

-- :server:deleteEvidenceItem is registered only in server/backend/evidence.lua.

-- :server:getEvidenceCustody is registered only in server/backend/evidence.lua.

-- Add a note to a case
ps.registerCallback(resourceName .. ':server:addCaseNote', function(source, caseId, content)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Unauthorized' } end
    if not canAccessCaseId(src, caseId) then return { success = false, error = 'Case not found or inaccessible' } end

    caseId = tonumber(caseId)
    if not caseId or caseId ~= caseId or caseId == math.huge
        or caseId <= 0 or caseId % 1 ~= 0
        or type(content) ~= 'string' or not content:find('%S') or #content > 20000 then
        return { success = false, error = 'Invalid case or empty note' }
    end

    local citizenId = ps.getIdentifier(src)
    if type(citizenId) ~= 'string' or citizenId == '' then
        return { success = false, error = 'Missing author identity' }
    end
    local profile = MySQL.single.await('SELECT fullname FROM mdt_profiles WHERE citizenid = ?', { citizenId })
    local authorName = profile and type(profile.fullname) == 'string'
        and profile.fullname ~= '' and profile.fullname or 'Unknown'
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or ps.getIdentifier(src) ~= citizenId or not canAccessCaseId(src, caseId) then
        return { success = false, error = 'Authorization changed' }
    end

    if ps.getIdentifier(src) ~= citizenId then
        return { success = false, error = 'Note author identity changed' }
    end
    local noteId = MySQL.insert.await([[
        INSERT INTO mdt_case_notes (case_id, content, author_citizenid, author_name)
        VALUES (?, ?, ?, ?)
    ]], { caseId, content, citizenId, authorName })
    if not noteId then return { success = false, error = 'Failed to save case note' } end
    return { success = true }
end)

-- Delete a note from a case
ps.registerCallback(resourceName .. ':server:deleteCaseNote', function(source, noteId, caseId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit') then return { success = false, error = 'Unauthorized' } end
    if not canAccessCaseId(src, caseId) then return { success = false, error = 'Case not found or inaccessible' } end

    noteId = tonumber(noteId)
    caseId = tonumber(caseId)
    if not noteId or not caseId or noteId ~= noteId or caseId ~= caseId
        or noteId == math.huge or caseId == math.huge or noteId <= 0 or caseId <= 0
        or noteId % 1 ~= 0 or caseId % 1 ~= 0 then
        return { success = false, error = 'Invalid note or case' }
    end

    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or not canAccessCaseId(src, caseId) then
        return { success = false, error = 'Authorization changed' }
    end
    local deleted = MySQL.update.await('DELETE FROM mdt_case_notes WHERE id = ? AND case_id = ?', { noteId, caseId })
    return { success = deleted ~= nil and deleted > 0 }
end)


-- Stage 4: a case-owning department may disclose one case detail to a
-- named character. This never grants blanket agency/case edits or evidence.
ps.registerCallback(resourceName .. ':server:grantCaseDisclosure', function(source, caseId, recipientCid, purpose)
    local src, id = source, tonumber(caseId)
    if not id or id ~= id or id == math.huge or id <= 0 or id % 1 ~= 0 or type(recipientCid) ~= 'string' or #recipientCid < 2 or #recipientCid > 64
        or type(purpose) ~= 'string' or #purpose < 10 or #purpose > 255 then
        return {success=false, error='Case, recipient and purpose are required'}
    end
    if not recipientCid:find('%S') then return {success=false,error='Disclosure recipient is required'} end
    if not purpose:find('%S') then return {success=false,error='Disclosure purpose is required'} end
    if not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or not canAccessCaseId(src, id) then return {success=false, error='Unauthorized'} end
    local actor, employer = ps.getIdentifier(src), ps.getJobName(src)
    if type(actor) ~= 'string' or actor == ''
        or type(employer) ~= 'string' or employer == '' then
        return {success=false,error='Missing disclosure author identity'}
    end
    local caseRow = MySQL.single.await('SELECT assigned_department FROM mdt_cases WHERE id = ?', {id})
    if not caseRow or caseRow.assigned_department ~= employer then
        return {success=false, error='Only originating department may disclose a case'}
    end
    local recipientJob = MySQL.scalar.await([[
        SELECT JSON_UNQUOTE(JSON_EXTRACT(job, '$.name'))
        FROM players WHERE citizenid = ? LIMIT 1
    ]], {recipientCid})
    if type(recipientJob) ~= 'string' or not recipientJob:find('%S')
        or #recipientJob > 64 or not CheckAuth(src) or not CheckPermission(src, 'cases_edit')
        or ps.getIdentifier(src) ~= actor or ps.getJobName(src) ~= employer
        or not canAccessCaseId(src, id) then return {success=false,error='Authorization changed'} end
    local ok, newId = pcall(MySQL.insert.await, [[
        INSERT INTO mdt_case_disclosures
            (case_id, recipient_citizenid, recipient_job, purpose, granted_by_citizenid, granted_by_job)
        SELECT id, ?, ?, ?, ?, assigned_department FROM mdt_cases
        WHERE id = ? AND assigned_department = ?
    ]], {recipientCid, recipientJob, purpose, actor, id, employer})
    if not ok or not tonumber(newId) or tonumber(newId) <= 0 then return {success=false,error='Disclosure storage unavailable'} end
    if ps.auditLog then ps.auditLog(src,'case_disclosure_granted','case',id,
        {grant_id=newId, recipient=recipientCid, purpose=purpose}) end
    return {success=true,grantId=newId}
end)

ps.registerCallback(resourceName .. ':server:revokeCaseDisclosure', function(source, grantId)
    local src,id=source,tonumber(grantId)
    if not id or id ~= id or id == math.huge or id <= 0 or id % 1 ~= 0
        or not CheckAuth(src) or not CheckPermission(src,'cases_edit') then
        return {success=false,error='Unauthorized'}
    end
    local actor, employer=ps.getIdentifier(src),ps.getJobName(src)
    if type(actor) ~= 'string' or actor == ''
        or type(employer) ~= 'string' or employer == '' then
        return {success=false,error='Unauthorized'}
    end
    if not CheckAuth(src) or not CheckPermission(src,'cases_edit')
        or ps.getIdentifier(src) ~= actor or ps.getJobName(src) ~= employer then
        return {success=false,error='Authorization changed'}
    end
    local ok,count=pcall(MySQL.update.await,[[
        UPDATE mdt_case_disclosures g
        INNER JOIN mdt_cases c ON c.id = g.case_id
        SET g.revoked_at = NOW(), g.revoked_by_citizenid = ?
        WHERE g.id = ? AND c.assigned_department = ? AND g.revoked_at IS NULL
    ]],{actor,id,employer})
    if not ok or tonumber(count)~=1 then return {success=false,error='Grant not found or inaccessible'} end
    if ps.auditLog then ps.auditLog(src,'case_disclosure_revoked','case_disclosure',id,{employer=employer}) end
    return {success=true}
end)

ps.registerCallback(resourceName .. ':server:getCaseDisclosures', function(source, caseId)
    local src,id=source,tonumber(caseId)
    if not id or id ~= id or id == math.huge or id <= 0 or id % 1 ~= 0
        or not CheckAuth(src) or not CheckPermission(src,'cases_edit') then return {} end
    local actor, employer=ps.getIdentifier(src),ps.getJobName(src)
    if type(actor) ~= 'string' or actor == ''
        or type(employer) ~= 'string' or employer == '' then return {} end
    local record=MySQL.single.await('SELECT assigned_department FROM mdt_cases WHERE id = ?', {id})
    if not record or record.assigned_department~=employer then return {} end
    local ok,rows=pcall(MySQL.query.await,[[
        SELECT id,recipient_citizenid,purpose,granted_at,expires_at,revoked_at
        FROM mdt_case_disclosures WHERE case_id = ? ORDER BY granted_at DESC LIMIT 100
    ]],{id})
    if not CheckAuth(src) or not CheckPermission(src,'cases_edit')
        or ps.getJobName(src)~=employer or ps.getIdentifier(src)~=actor
        or not canAccessCaseId(src,id) then return {} end
    return ok and rows or {}
end)


-- Individually disclosed cases appear only in the named character's inbox.
-- Original employer ownership remains intact and disclosures are read-only.
ps.registerCallback(resourceName .. ':server:getDisclosedCases', function(source)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_view') then return {} end
    local actor, job = ps.getIdentifier(src), ps.getJobName(src)
    if type(actor) ~= 'string' or actor == ''
        or type(job) ~= 'string' or job == '' or not getCaseScope(src) then return {} end
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT c.id, c.case_number, c.title, c.status, c.priority,
               c.assigned_department, g.purpose, g.granted_at
        FROM mdt_case_disclosures g
        INNER JOIN mdt_cases c ON c.id = g.case_id
        WHERE g.recipient_citizenid = ? AND g.recipient_job = ? AND g.revoked_at IS NULL
          AND (g.expires_at IS NULL OR g.expires_at > NOW())
        ORDER BY g.granted_at DESC LIMIT 100
    ]], {actor,job})
    if not CheckAuth(src) or not CheckPermission(src, 'cases_view')
        or ps.getIdentifier(src) ~= actor or ps.getJobName(src) ~= job
        or not getCaseScope(src) then return {} end
    return ok and rows or {}
end)
