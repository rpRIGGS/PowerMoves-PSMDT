local resourceName = tostring(GetCurrentResourceName())

local function canEditEvidenceRecord(source, evidenceId)
    local id = tonumber(evidenceId)
    if not id or id ~= id or id == math.huge or id <= 0 or id % 1 ~= 0 then return false end
    local row = MySQL.single.await('SELECT case_id, created_by FROM mdt_evidence_items WHERE id = ?', { id })
    if not row then return false end
    if row.case_id then
        return CheckAuth(source) and CheckPermission(source, 'cases_view')
            and CanAccessMdtCase(source, row.case_id)
    end
    -- No reliable historic employer marker exists on unlinked evidence.
    -- Fail closed for another creator rather than expose unknown agency records.
    local cid = ps.getIdentifier(source)
    local access = GetMdtAccess(source)
    return cid ~= nil and row.created_by == cid and access ~= nil and access.authorized == true
end

-- SQL read guard: evidence linked to a case belongs to its assigned
-- department; unlinked legacy evidence has no dependable employer marker,
-- so only the original collecting citizen can view it by default.
local evidenceReadScope = [[
    ((mdt_evidence_items.case_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM mdt_cases scoped_case
        WHERE scoped_case.id = mdt_evidence_items.case_id
          AND (scoped_case.assigned_department = ? OR ? = 1)
    )) OR (mdt_evidence_items.case_id IS NULL AND mdt_evidence_items.created_by = ?))
]]

local function evidenceReadParams(source)
    local access = GetMdtAccess(source)
    if not access or not access.authorized or type(access.agency) ~= 'string'
        or access.agency == '' then return nil end
    local citizenid = ps.getIdentifier(source)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    return { access.agency, access.interfaceId == 'sadoj' and 1 or 0, citizenid }
end

local function unchangedEvidenceReadScope(source, original)
    local current = evidenceReadParams(source)
    return current ~= nil and original ~= nil
        and current[1] == original[1] and current[2] == original[2]
        and current[3] == original[3]
end

ps.registerCallback(resourceName .. ':server:getEvidenceItems', function(source, page, limit, filters)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_view') then return { success = false, error = 'Unauthorized' } end

    page, limit = tonumber(page) or 1, tonumber(limit) or 20
    if page ~= page or page == math.huge or page == -math.huge then page = 1 end
    if limit ~= limit or limit == math.huge or limit == -math.huge then limit = 20 end
    page = math.floor(math.max(1, math.min(page, 100000)))
    limit = math.floor(math.max(1, math.min(limit, 100)))
    local offset = (page - 1) * limit

    if filters ~= nil and type(filters) ~= 'table' then
        return { success = false, error = 'Invalid evidence filters' }
    end
    local scopeParams = evidenceReadParams(src)
    if not scopeParams then return { success = false, error = 'Unauthorized' } end
    local queryParts = { evidenceReadScope }
    local values = scopeParams

    if filters and filters.caseId then
        local id = tonumber(filters.caseId)
        if not id or id ~= id or id == math.huge or id <= 0 or id % 1 ~= 0 then
            return { success = false, error = 'Invalid case filter' }
        end
        queryParts[#queryParts + 1] = 'case_id = ?'
        values[#values + 1] = id
    end

    if filters and filters.type and filters.type ~= '' then
        if type(filters.type) ~= 'string' or #filters.type > 100 then
            return { success = false, error = 'Invalid evidence type filter' }
        end
        queryParts[#queryParts + 1] = 'type = ?'
        values[#values + 1] = tostring(filters.type)
    end

    if filters and filters.stored ~= nil and filters.stored ~= '' then
        if type(filters.stored) ~= 'boolean' then
            return { success = false, error = 'Invalid stored filter' }
        end
        queryParts[#queryParts + 1] = 'stored = ?'
        values[#values + 1] = filters.stored and 1 or 0
    end

    local whereClause = table.concat(queryParts, ' AND ')
    local totalRow = MySQL.single.await(('SELECT COUNT(id) as total FROM mdt_evidence_items WHERE %s'):format(whereClause), values)
    local total = totalRow and totalRow.total or 0

    local listValues = { table.unpack(values) }
    listValues[#listValues + 1] = limit
    listValues[#listValues + 1] = offset

    local evidence = MySQL.query.await(([[
        SELECT id, case_id, report_id, title, type, serial, notes, location, stash_id, stored, last_holder, created_by, created_at, updated_at
        FROM mdt_evidence_items
        WHERE %s
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ]]):format(whereClause), listValues)

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

    -- Never return another employer's results after a yielding query.
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_view')
        or not unchangedEvidenceReadScope(src, scopeParams) then
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

ps.registerCallback(resourceName .. ':server:searchEvidenceItems', function(source, query, page, limit)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_view') then return { success = false, error = 'Unauthorized' } end

    local _, likeQuery = NormalizeSearch(query)
    page, limit = tonumber(page) or 1, tonumber(limit) or 20
    if page ~= page or page == math.huge or page == -math.huge then page = 1 end
    if limit ~= limit or limit == math.huge or limit == -math.huge then limit = 20 end
    page = math.floor(math.max(1, math.min(page, 100000)))
    limit = math.floor(math.max(1, math.min(limit, 100)))
    if not likeQuery then
        return { success = true, data = { items = {}, total = 0, page = 1, limit = limit } }
    end
    local offset = (page - 1) * limit

    local scopeParams = evidenceReadParams(src)
    if not scopeParams then return { success = false, error = 'Unauthorized' } end
    local searchParams = { likeQuery, likeQuery, likeQuery, likeQuery, likeQuery }
    for _, param in ipairs(scopeParams) do searchParams[#searchParams + 1] = param end
    local totalRow = MySQL.single.await(([[
        SELECT COUNT(id) as total
        FROM mdt_evidence_items
        WHERE (title LIKE ? OR serial LIKE ? OR notes LIKE ? OR location LIKE ? OR stash_id LIKE ?)
          AND %s
    ]]):format(evidenceReadScope), searchParams)

    local total = totalRow and totalRow.total or 0

    local pagedParams = { table.unpack(searchParams) }
    pagedParams[#pagedParams + 1], pagedParams[#pagedParams + 2] = limit, offset
    local evidence = MySQL.query.await(([[
        SELECT id, case_id, report_id, title, type, serial, notes, location, stash_id, stored, last_holder, created_by, created_at, updated_at
        FROM mdt_evidence_items
        WHERE (title LIKE ? OR serial LIKE ? OR notes LIKE ? OR location LIKE ? OR stash_id LIKE ?)
          AND %s
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ]]):format(evidenceReadScope), pagedParams)

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

    -- Never return another employer's results after a yielding query.
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_view')
        or not unchangedEvidenceReadScope(src, scopeParams) then
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

ps.registerCallback(resourceName .. ':server:addEvidenceItem', function(source, payload)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_create') then return { success = false, error = 'Unauthorized' } end

    if type(payload) ~= 'table' then return { success = false, error = 'Invalid evidence request' } end
    local evidence = payload.evidence or payload

    if type(evidence) ~= 'table' or type(evidence.title) ~= 'string'
        or not evidence.title:find('%S') or #evidence.title > 255 then
        return { success = false, error = 'Invalid evidence: title is required' }
    end

    local caseId = nil
    if payload.caseId and tostring(payload.caseId) ~= '' then
        local n = tonumber(payload.caseId)
        if not n or n ~= n or n == math.huge or n <= 0 or n % 1 ~= 0 then
            return { success = false, error = 'Invalid case reference' }
        end
        if n then
            if not CanAccessMdtCase(src, n) or not CheckPermission(src, 'cases_edit') then
                return { success = false, error = 'Case not found or inaccessible' }
            end
            local row = MySQL.single.await('SELECT id FROM mdt_cases WHERE id = ?', { n })
            if not row then
                return { success = false, error = 'Case #' .. tostring(n) .. ' doesnt exist' }
            end
            caseId = n
        end
    end

    local reportId = nil
    if payload.reportId and tostring(payload.reportId) ~= '' then
        local n = tonumber(payload.reportId)
        if not n or n ~= n or n == math.huge or n <= 0 or n % 1 ~= 0 then
            return { success = false, error = 'Invalid report reference' }
        end
        if n then
            local row = MySQL.single.await('SELECT id FROM mdt_reports WHERE id = ?', { n })
            if not row then
                return { success = false, error = 'Report #' .. tostring(n) .. ' doesnt exist' }
            end
            if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, n) then
                return { success = false, error = 'Report not accessible' }
            end
            reportId = n
        end
    end

    if evidence.stored ~= nil and type(evidence.stored) ~= 'boolean' then
        return { success = false, error = 'Invalid stored flag' }
    end
    for _, field in ipairs({ 'type', 'serial', 'notes', 'location', 'stashId' }) do
        local value = evidence[field]
        if value ~= nil and (type(value) ~= 'string' or #value > (field == 'notes' and 20000 or 255)) then
            return { success = false, error = 'Invalid evidence ' .. field }
        end
    end
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_create')
        or (caseId and not CanAccessMdtCase(src, caseId))
        or (reportId and (type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId))) then
        return { success = false, error = 'Evidence authorization changed' }
    end
    local collector = ps.getIdentifier(src)
    if type(collector) ~= 'string' or collector == '' then
        return { success = false, error = 'Missing collector identity' }
    end
    local evidenceId = MySQL.insert.await([[
        INSERT INTO mdt_evidence_items
        (case_id, report_id, title, type, serial, notes, location, stash_id, stored, last_holder, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        caseId,
        reportId,
        evidence.title,
        evidence.type or 'Evidence',
        evidence.serial or '',
        evidence.notes or '',
        evidence.location or '',
        evidence.stashId or '',
        evidence.stored and 1 or 0,
        collector,
        collector
    })

    if not evidenceId then
        return { success = false, error = 'Failed to add evidence' }
    end

    local custodyOk, custodyId = pcall(MySQL.insert.await, [[
        INSERT INTO mdt_evidence_custody (evidence_id, from_citizenid, to_citizenid, action, notes)
        VALUES (?, ?, ?, 'collected', ?)
    ]], { evidenceId, nil, collector, evidence.notes or '' })
    if not custodyOk or not custodyId then
        MySQL.update.await('DELETE FROM mdt_evidence_items WHERE id = ? AND created_by = ?', { evidenceId, collector })
        return { success = false, error = 'Evidence custody record could not be created' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'evidence_added', 'evidence', evidenceId, evidence)
    end

    return { success = true, id = evidenceId }
end)

ps.registerCallback(resourceName .. ':server:updateEvidenceItem', function(source, evidenceId, evidence)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_transfer') then return { success = false, error = 'Unauthorized' } end

    evidenceId = tonumber(evidenceId)
    if not canEditEvidenceRecord(src, evidenceId) then return { success = false, error = 'Evidence not found or inaccessible' } end
    if not evidenceId or type(evidence) ~= 'table' then
        return { success = false, error = 'Invalid evidence' }
    end

    if evidence.stored ~= nil and type(evidence.stored) ~= 'boolean' then
        return { success = false, error = 'Invalid stored flag' }
    end
    for _, field in ipairs({ 'title', 'type', 'serial', 'notes', 'location', 'stashId' }) do
        local value = evidence[field]
        if value ~= nil and (type(value) ~= 'string' or #value > (field == 'notes' and 20000 or 255)
            or (field == 'title' and not value:find('%S'))) then
            return { success = false, error = 'Invalid evidence ' .. field }
        end
    end
    local updates = {}
    local values = {}

    if evidence.title then
        updates[#updates + 1] = 'title = ?'
        values[#values + 1] = evidence.title
    end
    if evidence.type then
        updates[#updates + 1] = 'type = ?'
        values[#values + 1] = evidence.type
    end
    if evidence.serial then
        updates[#updates + 1] = 'serial = ?'
        values[#values + 1] = evidence.serial
    end
    if evidence.notes then
        updates[#updates + 1] = 'notes = ?'
        values[#values + 1] = evidence.notes
    end
    if evidence.location then
        updates[#updates + 1] = 'location = ?'
        values[#values + 1] = evidence.location
    end
    if evidence.stashId then
        updates[#updates + 1] = 'stash_id = ?'
        values[#values + 1] = evidence.stashId
    end
    if evidence.stored ~= nil then
        updates[#updates + 1] = 'stored = ?'
        values[#values + 1] = evidence.stored and 1 or 0
    end

    if evidence.caseId then
        local caseId = tonumber(evidence.caseId)
        if not caseId or caseId ~= caseId or caseId == math.huge or caseId <= 0 or caseId % 1 ~= 0
            or not CanAccessMdtCase(src, caseId) then
            return { success = false, error = 'Case not accessible' }
        end
        updates[#updates + 1] = 'case_id = ?'
        values[#values + 1] = tonumber(evidence.caseId)
    end

    if evidence.reportId then
        local reportId = tonumber(evidence.reportId)
        if not reportId or reportId ~= reportId or reportId == math.huge or reportId <= 0 or reportId % 1 ~= 0
            or type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
            return { success = false, error = 'Report not accessible' }
        end
        updates[#updates + 1] = 'report_id = ?'
        values[#values + 1] = tonumber(evidence.reportId)
    end

    if #updates == 0 then
        return { success = false, error = 'No updates provided' }
    end

    if not CheckAuth(src) or not CheckPermission(src, 'evidence_transfer')
        or not canEditEvidenceRecord(src, evidenceId)
        or (evidence.caseId and not CanAccessMdtCase(src, tonumber(evidence.caseId)))
        or (evidence.reportId and not CanReadMdtReport(src, tonumber(evidence.reportId))) then
        return { success = false, error = 'Evidence authorization changed' }
    end
    values[#values + 1] = evidenceId
    local success = MySQL.update.await(('UPDATE mdt_evidence_items SET %s WHERE id = ?'):format(table.concat(updates, ', ')), values)

    if not success or success < 1 then
        return { success = false, error = 'Evidence not found or unchanged' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'evidence_updated', 'evidence', evidenceId, evidence)
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:deleteEvidenceItem', function(source, evidenceId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_transfer') then return { success = false, error = 'Unauthorized' } end

    evidenceId = tonumber(evidenceId)
    if not canEditEvidenceRecord(src, evidenceId) then return { success = false, error = 'Evidence not found or inaccessible' } end
    if not evidenceId then
        return { success = false, error = 'Invalid evidence id' }
    end

    if not CheckAuth(src) or not CheckPermission(src, 'evidence_transfer')
        or not canEditEvidenceRecord(src, evidenceId) then
        return { success = false, error = 'Evidence authorization changed' }
    end
    local success = MySQL.update.await('DELETE FROM mdt_evidence_items WHERE id = ?', { evidenceId })
    if not success or success < 1 then
        return { success = false, error = 'Evidence not found' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'evidence_deleted', 'evidence', evidenceId, {})
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:transferEvidenceItem', function(source, evidenceId, toCitizenId, notes)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_transfer') then return { success = false, error = 'Unauthorized' } end

    evidenceId = tonumber(evidenceId)
    if not canEditEvidenceRecord(src, evidenceId) then return { success = false, error = 'Evidence not found or inaccessible' } end
    if not evidenceId or type(toCitizenId) ~= 'string' or toCitizenId == ''
        or #toCitizenId > 64 then
        return { success = false, error = 'Invalid evidence transfer' }
    end

    if notes ~= nil and (type(notes) ~= 'string' or #notes > 20000) then
        return { success = false, error = 'Invalid transfer notes' }
    end
    if toCitizenId == ps.getIdentifier(src) then
        return { success = false, error = 'Recipient is the current officer' }
    end
    local fromCitizenId = ps.getIdentifier(src)
    if type(fromCitizenId) ~= 'string' or fromCitizenId == '' then
        return { success = false, error = 'Missing transferring officer identity' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_transfer')
        or not canEditEvidenceRecord(src, evidenceId) then
        return { success = false, error = 'Evidence authorization changed' }
    end
    if not MySQL.transaction or not MySQL.transaction.await then
        return { success = false, error = 'Database transaction unavailable' }
    end
    local ok, committed = pcall(MySQL.transaction.await, {
        {
            query = 'UPDATE mdt_evidence_items SET last_holder = ? WHERE id = ?',
            values = { toCitizenId, evidenceId }
        },
        {
            query = [[
                INSERT INTO mdt_evidence_custody (evidence_id, from_citizenid, to_citizenid, action, notes)
                VALUES (?, ?, ?, 'transferred', ?)
            ]],
            values = { evidenceId, fromCitizenId, toCitizenId, notes or '' }
        }
    })
    if not ok or not committed then
        return { success = false, error = 'Evidence transfer not saved' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'evidence_transferred', 'evidence', evidenceId, {
            fromCitizenId = fromCitizenId,
            toCitizenId = toCitizenId
        })
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:getEvidenceCustody', function(source, evidenceId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_view') then return {} end

    evidenceId = tonumber(evidenceId)
    if not evidenceId or evidenceId ~= evidenceId or evidenceId == math.huge
        or evidenceId <= 0 or evidenceId % 1 ~= 0 then return {} end
    if not canEditEvidenceRecord(src, evidenceId) then return {} end

    local custody = MySQL.query.await([[
        SELECT id, evidence_id, from_citizenid, to_citizenid, action, notes, created_at
        FROM mdt_evidence_custody
        WHERE evidence_id = ?
        ORDER BY created_at DESC
    ]], { evidenceId })

    if not CheckAuth(src) or not CheckPermission(src, 'evidence_view')
        or not canEditEvidenceRecord(src, evidenceId) then return {} end
    return custody or {}
end)

ps.registerCallback(resourceName .. ':server:logEvidenceViewed', function(source, evidenceId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_view') then return { success = false } end

    evidenceId = tonumber(evidenceId)
    if not canEditEvidenceRecord(src, evidenceId) then return { success = false, error = 'Evidence not found or inaccessible' } end
    if not evidenceId or evidenceId ~= evidenceId or evidenceId == math.huge
        or evidenceId <= 0 or evidenceId % 1 ~= 0 then return { success = false } end

    local citizenid = ps.getIdentifier(src)
    if type(citizenid) ~= 'string' or citizenid == '' then
        return { success = false, error = 'Missing viewer identity' }
    end

    local custodyId = MySQL.insert.await([[
        INSERT INTO mdt_evidence_custody (evidence_id, from_citizenid, to_citizenid, action, notes)
        VALUES (?, NULL, ?, 'viewed', '')
    ]], { evidenceId, citizenid })
    if not custodyId then return { success = false, error = 'Failed to log evidence view' } end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:addEvidenceImage', function(source, evidenceId, image)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_upload') then return { success = false, error = 'Unauthorized' } end

    evidenceId = tonumber(evidenceId)
    if not canEditEvidenceRecord(src, evidenceId) then return { success = false, error = 'Evidence not found or inaccessible' } end
    if not evidenceId or type(image) ~= 'table' then
        return { success = false, error = 'Invalid image' }
    end

    local url = image.url or image.data or ''
    local label = image.label or ''

    if type(url) ~= 'string' or url == '' or #url > 4096
        or type(label) ~= 'string' or #label > 255 then
        return { success = false, error = 'Invalid image metadata' }
    end

    local uploader = ps.getIdentifier(src)
    if type(uploader) ~= 'string' or uploader == '' then
        return { success = false, error = 'Missing uploader identity' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_upload')
        or not canEditEvidenceRecord(src, evidenceId) then
        return { success = false, error = 'Authorization changed' }
    end
    local imageId = MySQL.insert.await([[
        INSERT INTO mdt_evidence_images (evidence_id, url, label, uploaded_by)
        VALUES (?, ?, ?, ?)
    ]], { evidenceId, url, label, uploader })

    if not imageId then
        return { success = false, error = 'Failed to add image' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'evidence_image_added', 'evidence', evidenceId, {
            url = url,
            label = label
        })
    end

    return { success = true, id = imageId, url = url }
end)

ps.registerCallback(resourceName .. ':server:removeEvidenceImage', function(source, imageId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_transfer') then return { success = false, error = 'Unauthorized' } end

    imageId = tonumber(imageId)
    if not imageId or imageId ~= imageId or imageId == math.huge
        or imageId <= 0 or imageId % 1 ~= 0 then
        return { success = false, error = 'Invalid image id' }
    end

    local image = MySQL.single.await('SELECT url, evidence_id FROM mdt_evidence_images WHERE id = ?', { imageId })
    if not image or not canEditEvidenceRecord(src, image.evidence_id) then
        return { success = false, error = 'Evidence image not found or inaccessible' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_transfer')
        or not canEditEvidenceRecord(src, image.evidence_id) then
        return { success = false, error = 'Authorization changed' }
    end
    local success = MySQL.update.await('DELETE FROM mdt_evidence_images WHERE id = ?', { imageId })
    if not success or success < 1 then
        return { success = false, error = 'Evidence image not found' }
    end

    if image and type(image.url) == 'string'
        and not image.url:find('..', 1, true)
        and image.url:find('^/ps%-mdt%-v3/uploads/') then
        local path = image.url:gsub('^/ps%-mdt%-v3/', '')
        if path ~= '' then
            os.remove(path)
        end
    end

    if ps.auditLog then
        ps.auditLog(src, 'evidence_image_removed', 'evidence_image', imageId, {
            evidenceId = image and image.evidence_id or nil
        })
    end

    return { success = true }
end)

local function linkReportToCase(reportId, caseId, citizenid)
    if not reportId or not caseId then
        return
    end
    MySQL.insert.await([[
        INSERT IGNORE INTO mdt_case_reports (case_id, report_id, linked_by)
        VALUES (?, ?, ?)
    ]], { caseId, reportId, citizenid })
end

ps.registerCallback(resourceName .. ':server:linkEvidenceToCase', function(source, evidenceId, caseId, reportId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_transfer') then return { success = false, error = 'Unauthorized' } end

    evidenceId = tonumber(evidenceId)
    if not canEditEvidenceRecord(src, evidenceId) then return { success = false, error = 'Evidence not found or inaccessible' } end
    reportId = tonumber(reportId)
    if reportId and (reportId ~= reportId or reportId == math.huge
        or reportId <= 0 or reportId % 1 ~= 0) then
        return { success = false, error = 'Invalid report reference' }
    end

    local numericCaseId = tonumber(caseId)
    if not numericCaseId and type(caseId) == 'string' and caseId ~= '' then
        local row = MySQL.single.await('SELECT id FROM mdt_cases WHERE case_number = ? LIMIT 1', { caseId })
        if row then
            numericCaseId = row.id
        end
    end
    caseId = numericCaseId

    if not evidenceId or not caseId or caseId ~= caseId or caseId == math.huge
        or caseId <= 0 or caseId % 1 ~= 0 then
        return { success = false, error = 'Invalid evidence or case' }
    end

    if not CanAccessMdtCase(src, caseId) then
        return { success = false, error = 'Case not found or inaccessible' }
    end
    local caseExists = MySQL.single.await('SELECT id FROM mdt_cases WHERE id = ?', { caseId })
    if not caseExists then
        return { success = false, error = 'Case #' .. tostring(caseId) .. ' does not exist' }
    end

    if not CheckAuth(src) or not CheckPermission(src, 'evidence_transfer')
        or not canEditEvidenceRecord(src, evidenceId) or not CanAccessMdtCase(src, caseId) then
        return { success = false, error = 'Evidence authorization changed' }
    end
    local linked = MySQL.update.await('UPDATE mdt_evidence_items SET case_id = ? WHERE id = ?', { caseId, evidenceId })
    if not linked or linked < 1 then
        return { success = false, error = 'Evidence case link not saved' }
    end

    if reportId then
        local reportExists = MySQL.single.await('SELECT id FROM mdt_reports WHERE id = ?', { reportId })
        if reportExists and type(CanReadMdtReport) == 'function'
            and CanReadMdtReport(src, reportId) then
            linkReportToCase(reportId, caseId, ps.getIdentifier(src))
        end
    end

    if ps.auditLog then
        ps.auditLog(src, 'evidence_linked_case', 'evidence', evidenceId, {
            caseId = caseId,
            reportId = reportId
        })
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:linkEvidenceToReport', function(source, evidenceId, reportId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_transfer') then return { success = false, error = 'Unauthorized' } end

    evidenceId = tonumber(evidenceId)
    if not canEditEvidenceRecord(src, evidenceId) then return { success = false, error = 'Evidence not found or inaccessible' } end
    reportId = tonumber(reportId)

    if not evidenceId or not reportId or reportId ~= reportId or reportId == math.huge
        or reportId <= 0 or reportId % 1 ~= 0 then
        return { success = false, error = 'Invalid evidence or report' }
    end

    local reportExists = MySQL.single.await('SELECT id FROM mdt_reports WHERE id = ?', { reportId })
    if not reportExists then
        return { success = false, error = 'Report #' .. tostring(reportId) .. ' does not exist' }
    end

    if type(CanReadMdtReport) ~= 'function' or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Report not accessible' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'evidence_transfer')
        or not canEditEvidenceRecord(src, evidenceId)
        or not CanReadMdtReport(src, reportId) then
        return { success = false, error = 'Authorization changed' }
    end
    local linked = MySQL.update.await('UPDATE mdt_evidence_items SET report_id = ? WHERE id = ?', { reportId, evidenceId })
    if not linked or linked < 1 then
        return { success = false, error = 'Evidence report link not saved' }
    end

    if ps.auditLog then
        ps.auditLog(src, 'evidence_linked_report', 'evidence', evidenceId, {
            reportId = reportId
        })
    end

    return { success = true }
end)

ps.registerCallback(resourceName .. ':server:createCaseFromEvidence', function(source, evidenceId, reportId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'cases_create') then return { success = false, error = 'Unauthorized' } end

    evidenceId = tonumber(evidenceId)
    if not canEditEvidenceRecord(src, evidenceId) then return { success = false, error = 'Evidence not found or inaccessible' } end
    reportId = tonumber(reportId)
    if not evidenceId then
        return { success = false, error = 'Invalid evidence' }
    end

    local citizenid = ps.getIdentifier(src)
    local createdByName = (ps.getMetadata(src, 'callsign') or '') .. ' ' .. (ps.getPlayerName(src) or '')
    createdByName = createdByName:gsub('^%s+', ''):gsub('%s+$', '')

    local caseId = MySQL.insert.await([[INSERT INTO mdt_cases
        (case_number, title, summary, status, priority, assigned_department, created_by, created_by_name)
        VALUES ('', ?, ?, 'open', 'medium', ?, ?, ?)
    ]], { 'Evidence Follow-up', 'Case created from evidence link', ps.getJobName(src) or 'police', citizenid, createdByName })

    if not caseId then
        return { success = false, error = 'Failed to create case' }
    end

    local caseNumber = ('CASE-%s-%05d'):format(os.date('%Y'), caseId)
    MySQL.update.await('UPDATE mdt_cases SET case_number = ? WHERE id = ?', { caseNumber, caseId })
    MySQL.update.await('UPDATE mdt_evidence_items SET case_id = ? WHERE id = ?', { caseId, evidenceId })
    if reportId then
        linkReportToCase(reportId, caseId, citizenid)
    end

    if ps.auditLog then
        ps.auditLog(src, 'case_created_from_evidence', 'case', caseId, {
            evidenceId = evidenceId,
            reportId = reportId
        })
    end

    return { success = true, caseId = caseId, caseNumber = caseNumber }
end)

RegisterNetEvent(resourceName .. ':server:openEvidenceStash', function(stashId)
    local src = source
    if not CheckAuth(src) then return end
    if not CheckPermission(src, 'evidence_view') then return end

    if type(stashId) ~= 'string' or stashId == '' or #stashId > 128 then return end
    -- A client may request only a stash referenced by evidence they can access.
    local row = MySQL.single.await(
        'SELECT id FROM mdt_evidence_items WHERE stash_id = ? LIMIT 1',
        { stashId }
    )
    if not row or not canEditEvidenceRecord(src, row.id) then return end

    -- qb-inventory
    if GetResourceState('qb-inventory') == 'started' then
        exports['qb-inventory']:OpenInventory(src, stashId, {
            maxweight = 4000000,
            slots = 500,
        })
        return
    end

    -- ox_inventory with forceOpenInventory
    if GetResourceState('ox_inventory') == 'started' then
        
        exports.ox_inventory:RegisterStash(stashId, stashId , 500 , 4000000)

        exports.ox_inventory:forceOpenInventory(src, 'stash', stashId)
        return
    end
end)

-- Stage 4 discovery is deliberately separate from evidence mutation/stash APIs.
-- A named recipient can view redacted metadata + custody only, never transfer.
local function disclosedEvidenceScope(src, id)
    if not CheckAuth(src) or not CheckPermission(src,'evidence_view') then return false end
    local cid,job=ps.getIdentifier(src),ps.getJobName(src)
    if not cid or not job then return false end
    local ok,record=pcall(MySQL.single.await,[[
        SELECT g.id
        FROM mdt_evidence_disclosures g
        INNER JOIN mdt_evidence_items e ON e.id = g.evidence_id
        LEFT JOIN mdt_cases c ON c.id = e.case_id
        WHERE g.evidence_id = ? AND g.recipient_citizenid = ? AND g.recipient_job = ?
          AND g.revoked_at IS NULL
          AND (e.case_id IS NULL OR c.assigned_department = g.granted_by_job)
        LIMIT 1
    ]],{id,cid,job})
    return ok and record~=nil and CheckAuth(src)
        and CheckPermission(src,'evidence_view') and ps.getIdentifier(src)==cid
        and ps.getJobName(src)==job
end

ps.registerCallback(resourceName .. ':server:grantEvidenceDisclosure', function(source, evidenceId, recipientCid, purpose)
    local src,id=source,tonumber(evidenceId)
    if not id or id ~= id or id == math.huge or id <= 0 or id % 1 ~= 0 or type(recipientCid)~='string' or #recipientCid<2 or #recipientCid>64
        or type(purpose)~='string' or #purpose<10 or #purpose>255 then
        return {success=false,error='Evidence, recipient and purpose required'}
    end
    if not recipientCid:find('%S') or not purpose:find('%S') then
        return {success=false,error='Disclosure recipient and purpose required'}
    end
    if not CheckAuth(src) or not CheckPermission(src,'evidence_transfer')
        or not canEditEvidenceRecord(src,id) then return {success=false,error='Unauthorized'} end
    local actor,employer=ps.getIdentifier(src),ps.getJobName(src)
    if type(actor) ~= 'string' or actor == ''
        or type(employer) ~= 'string' or employer == '' then
        return {success=false,error='Unauthorized'}
    end
    local recipientJob=MySQL.scalar.await([[
        SELECT JSON_UNQUOTE(JSON_EXTRACT(job, '$.name'))
        FROM players WHERE citizenid = ? LIMIT 1
    ]],{recipientCid})
    if type(recipientJob) ~= 'string' or not recipientJob:find('%S')
        or #recipientJob > 64 or not CheckAuth(src)
        or not CheckPermission(src,'evidence_transfer')
        or ps.getIdentifier(src)~=actor or ps.getJobName(src)~=employer
        or not canEditEvidenceRecord(src,id) then
        return {success=false,error='Authorization changed'}
    end
    local ok,grantId=pcall(MySQL.insert.await,[[
        INSERT INTO mdt_evidence_disclosures
            (evidence_id,recipient_citizenid,recipient_job,purpose,granted_by_citizenid,granted_by_job)
        SELECT e.id, ?, ?, ?, ?, ?
        FROM mdt_evidence_items e
        LEFT JOIN mdt_cases c ON c.id = e.case_id
        WHERE e.id = ?
          AND (c.assigned_department = ? OR (e.case_id IS NULL AND e.created_by = ?))
    ]],{recipientCid,recipientJob,purpose,actor,employer,id,employer,actor})
    if not ok or not tonumber(grantId) or tonumber(grantId)<=0 then
        return {success=false,error='Could not store evidence disclosure'}
    end
    if ps.auditLog then ps.auditLog(src,'evidence_disclosure_granted','evidence',id,
        {grant_id=grantId,recipient=recipientCid,purpose=purpose}) end
    return {success=true,grantId=grantId}
end)

ps.registerCallback(resourceName .. ':server:revokeEvidenceDisclosure', function(source, grantId)
    local src,id=source,tonumber(grantId)
    if not id or not CheckAuth(src) or not CheckPermission(src,'evidence_transfer') then
        return {success=false,error='Unauthorized'}
    end
    local actor,employer=ps.getIdentifier(src),ps.getJobName(src)
    if not actor or not employer then return {success=false,error='Unauthorized'} end
    local ok,changed=pcall(MySQL.update.await,[[
        UPDATE mdt_evidence_disclosures
        SET revoked_at = NOW(), revoked_by_citizenid = ?
        WHERE id = ? AND granted_by_job = ? AND revoked_at IS NULL
    ]],{actor,id,employer})
    if not ok or tonumber(changed)~=1 then return {success=false,error='Grant not found'} end
    if ps.auditLog then ps.auditLog(src,'evidence_disclosure_revoked','evidence_disclosure',id,{employer=employer}) end
    return {success=true}
end)

ps.registerCallback(resourceName .. ':server:getDisclosedEvidence', function(source)
    local src=source
    if not CheckAuth(src) or not CheckPermission(src,'evidence_view') then return {} end
    local cid,job=ps.getIdentifier(src),ps.getJobName(src)
    if not cid or not job then return {} end
    local ok,rows=pcall(MySQL.query.await,[[
        SELECT e.id,e.case_id,e.report_id,e.title,e.type,e.serial,e.created_at,
               g.purpose,g.granted_at
        FROM mdt_evidence_disclosures g
        INNER JOIN mdt_evidence_items e ON e.id = g.evidence_id
        LEFT JOIN mdt_cases c ON c.id = e.case_id
        WHERE g.recipient_citizenid = ? AND g.recipient_job = ?
          AND g.revoked_at IS NULL
          AND (e.case_id IS NULL OR c.assigned_department = g.granted_by_job)
        ORDER BY g.granted_at DESC LIMIT 100
    ]],{cid,job})
    if not CheckAuth(src) or not CheckPermission(src,'evidence_view')
        or ps.getIdentifier(src)~=cid or ps.getJobName(src)~=job then return {} end
    return ok and rows or {}
end)

ps.registerCallback(resourceName .. ':server:getDisclosedEvidenceDetail', function(source, evidenceId)
    local src,id=source,tonumber(evidenceId)
    if not id or not disclosedEvidenceScope(src,id) then return {success=false,error='Unauthorized'} end
    local item=MySQL.single.await([[
        SELECT id,case_id,report_id,title,type,serial,notes,location,stored,last_holder,
               created_by,created_at,updated_at
        FROM mdt_evidence_items WHERE id = ?
    ]],{id})
    if not item or not disclosedEvidenceScope(src,id) then return {success=false,error='Unauthorized'} end
    local custody=MySQL.query.await([[
        SELECT id,evidence_id,from_citizenid,to_citizenid,action,notes,created_at
        FROM mdt_evidence_custody WHERE evidence_id = ? ORDER BY created_at DESC
    ]],{id})
    if not disclosedEvidenceScope(src,id) then return {success=false,error='Authorization changed'} end
    if ps.auditLog then ps.auditLog(src,'evidence_disclosure_accessed','evidence',id,
        {recipient=ps.getIdentifier(src)}) end
    return {success=true,data={item=item,custody=custody or {}}}
end)


ps.registerCallback(resourceName .. ':server:getEvidenceDisclosures', function(source, evidenceId)
    local src,id=source,tonumber(evidenceId)
    if not id or not CheckAuth(src) or not CheckPermission(src,'evidence_transfer')
        or not canEditEvidenceRecord(src,id) then return {} end
    local actor,job=ps.getIdentifier(src),ps.getJobName(src)
    if not actor or not job then return {} end
    local ok,rows=pcall(MySQL.query.await,[[
        SELECT id,recipient_citizenid,recipient_job,purpose,granted_at,revoked_at
        FROM mdt_evidence_disclosures
        WHERE evidence_id = ? AND granted_by_job = ?
        ORDER BY granted_at DESC LIMIT 100
    ]],{id,job})
    if not CheckAuth(src) or not CheckPermission(src,'evidence_transfer')
        or ps.getIdentifier(src)~=actor or ps.getJobName(src)~=job
        or not canEditEvidenceRecord(src,id) then return {} end
    return ok and rows or {}
end)
