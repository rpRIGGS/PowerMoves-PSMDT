local resourceName = tostring(GetCurrentResourceName())

-- IA complaints retain their legacy police/ems service marker AND a nullable
-- responsible agency. New civilian complaints use the accused employee's
-- verified current job when available, never the complainant's job. Older
-- complaints are left unassigned until their agency can be confirmed.
CreateThread(function()
    Wait(2500)
    if EnsureColumn then
        EnsureColumn('mdt_ia_complaints', 'job_type', "`job_type` varchar(10) NOT NULL DEFAULT 'police'")
        EnsureColumn('mdt_ia_complaints', 'agency', "`agency` varchar(40) DEFAULT NULL")
    end
end)

-- Confidential investigative records are not general MDT records.
-- State-level disclosure to agency command should use explicitly restricted
-- reports, never unrestricted access to the underlying investigation.
local function canViewIA(src)
    return CheckAuth(src) and CheckPermission(src, 'ia_view')
end

local function canManageIA(src)
    return CheckAuth(src) and CheckPermission(src, 'ia_manage')
end

-- Separate the legacy service-family marker from actual agency ownership.
-- Only the originating employer sees ordinary IA records. SADLE's authorized
-- IA roles can investigate police-family complaints statewide and triage
-- unassigned legacy police complaints; unknown EMS-era records stay withheld
-- until they are explicitly reconciled with a responsible fire/hospital agency.
local function canAccessIARecord(src, record)
    if not record or not canViewIA(src) then return false end
    if type(record.job_type) ~= 'string' or not record.job_type:find('%S')
        or record.job_type ~= GetMdtDomain(src) then return false end
    local actorJob = ps.getJobName(src)
    if type(actorJob) ~= 'string' or not actorJob:find('%S') then return false end
    return (type(record.agency) == 'string' and record.agency:find('%S')
        and record.agency == actorJob)
        or (actorJob == 'sadle' and record.job_type == 'police')
end

local function ownsIAComplaint(src, complaintId)
    if not CheckAuth(src) then return false end
    local id = tonumber(complaintId)
    if not id or id ~= id or id == math.huge or id <= 0 or id % 1 ~= 0 then return false end
    local record = MySQL.single.await(
        'SELECT job_type, agency FROM mdt_ia_complaints WHERE id = ? LIMIT 1',
        {id}
    )
    return CheckAuth(src) and canAccessIARecord(src, record)
end

-- The alleged employee's configured current employer is a provisional routing
-- source, not proof of where they worked on the incident date. Unknown or
-- unsupported employers remain unassigned for authorized IA triage.
local function allegedEmployeeAgency(citizenid)
    if type(citizenid) ~= 'string' or not citizenid:find('%S') or #citizenid > 64 then
        return nil, 'police'
    end
    local encoded = MySQL.scalar.await('SELECT job FROM players WHERE citizenid = ? LIMIT 1', {citizenid})
    if type(encoded) ~= 'string' then return nil, 'police' end
    local ok, job = pcall(json.decode, encoded)
    if not ok or type(job) ~= 'table' or type(job.name) ~= 'string'
        or not job.name:find('%S') then return nil, 'police' end
    local name = job.name
    for _, configured in ipairs(Config.PoliceJobs or {}) do
        if configured == name then return name, 'police' end
    end
    for _, configured in ipairs(((Config.MdtAccess or {}).FireJobs) or Config.FireJobs or {}) do
        if configured == name then return name, 'ems' end
    end
    for _, configured in ipairs(Config.MedicalJobs or {}) do
        if configured == name then return name, 'ems' end
    end
    return nil, 'police'
end

local function buildComplaintNumber(id)
    local year = os.date('%Y')
    return ('IA-%s-%05d'):format(year, id)
end

-- Submit a complaint (NO CheckAuth -- civilians can submit)
local function iaCfg()
    return (Config and Config.IA) or {}
end

-- What each status means to somebody who doesn't work at IA.
local STATUS_TEXT = {
    open          = 'has been received and is awaiting review',
    under_review  = 'is now under investigation',
    investigated  = 'has been investigated and is awaiting a decision',
    sustained     = 'has been upheld — the complaint was found to be justified',
    exonerated    = 'has been closed — the officer was found to have acted correctly',
    unfounded     = 'has been closed — no evidence was found to support it',
    closed        = 'has been closed',
}

--- Let the complainant know their complaint moved on. The success screen tells them
--- they'll be contacted, so this is the part that keeps that promise.
local function mailComplainantStatus(complaintId, status)
    if not iaCfg().NotifyComplainant then return end
    if not SendCitizenMail then return end

    local row = MySQL.single.await([[
        SELECT complaint_number, complainant_citizenid, officer_name
        FROM mdt_ia_complaints WHERE id = ?
    ]], { complaintId })
    if not row or not row.complainant_citizenid then return end

    local what = STATUS_TEXT[status] or ('is now marked "' .. tostring(status) .. '"')
    local body = ('Your complaint %s %s.'):format(row.complaint_number or '', what)
    if row.officer_name and row.officer_name ~= '' then
        body = body .. ('\n\nOfficer named in the complaint: %s'):format(row.officer_name)
    end
    body = body .. '\n\nYou do not need to reply to this message. If we need anything further from you, we will be in touch.'

    SendCitizenMail(
        row.complainant_citizenid,
        iaCfg().MailSender or 'Internal Affairs',
        ('Complaint %s — update'):format(row.complaint_number or ''),
        body
    )
end

-- Anti-spam. Complaints are a serious accusation; nobody needs to file two a second.
-- ComplaintCooldown[citizenid] = os.clock-ish timestamp in ms
local ComplaintCooldown = {}

AddEventHandler('playerDropped', function()
    local cid = ps.getIdentifier and ps.getIdentifier(source) or nil
    if cid then ComplaintCooldown[cid] = nil end
end)

--- Work out which officer a complaint is actually about.
---
--- The complaint used to keep only the name the civilian typed, and an officer's
--- IA history was found by string-matching it. "Officer Walker" instead of
--- "James Walker" meant the complaint never reached his profile at all. We resolve
--- it to a citizenid here instead — and when we can't, we say so by leaving it NULL
--- rather than guessing and attaching it to the wrong person.
---
--- @return string|nil citizenid
local function resolveOfficer(name, badge)
    name  = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    badge = tostring(badge or ''):gsub('^%s+', ''):gsub('%s+$', '')

    -- A badge is unique and unambiguous, so trust it first.
    if badge ~= '' and #badge <= 64 then
        local matches = MySQL.query.await([[
            SELECT citizenid FROM mdt_profiles
            WHERE badge_number = ? OR callsign = ?
            LIMIT 2
        ]], { badge, badge })
        if type(matches) ~= 'table' then matches = {} end
        if #matches == 1 then return matches[1].citizenid end
        if #matches > 1 then return nil end
    end

    if name == '' or #name > 255 then return nil end

    -- Fall back to the name, but only when it points at exactly one officer.
    local rows = MySQL.query.await([[
        SELECT citizenid FROM mdt_profiles
        WHERE LOWER(TRIM(fullname)) = LOWER(TRIM(?))
        LIMIT 2
    ]], { name }) or {}

    if type(rows) ~= 'table' then return nil end
    if #rows == 1 then return rows[1].citizenid end
    return nil -- no match, or ambiguous: better unassigned than wrong
end

ps.registerCallback(resourceName .. ':server:submitComplaint', function(source, data)
    local src = source
    if type(data) ~= 'table' then return { success = false, error = 'Invalid complaint' } end

    local citizenid = ps.getIdentifier(src)
    if type(citizenid) ~= 'string' or not citizenid:find('%S') or #citizenid > 64 then
        return { success = false, error = 'Missing citizen id' }
    end

    -- Anti-spam.
    local cooldownMs = iaCfg().CooldownMs or 0
    if cooldownMs > 0 then
        local last = ComplaintCooldown[citizenid]
        local now = GetGameTimer()
        if last and (now - last) < cooldownMs then
            local wait = math.ceil((cooldownMs - (now - last)) / 60000)
            return {
                success = false,
                error = ('You have already filed a complaint recently. Try again in about %d minute(s).'):format(math.max(1, wait)),
            }
        end
    end

    local player = MySQL.single.await([[
        SELECT JSON_UNQUOTE(JSON_EXTRACT(charinfo, "$.firstname")) AS firstname,
               JSON_UNQUOTE(JSON_EXTRACT(charinfo, "$.lastname")) AS lastname
        FROM players WHERE citizenid = ?
    ]], { citizenid })

    local complainantName = 'Unknown'
    if player then
        complainantName = (player.firstname or 'Unknown') .. ' ' .. (player.lastname or '')
    end

    local witnesses = data.witnesses
    if type(witnesses) == 'table' then
        witnesses = json.encode(witnesses)
    end

    local evidence = data.evidence
    if type(evidence) == 'table' then
        evidence = json.encode(evidence)
    end

    local officerName = data.officerName or data.officer_name or ''
    local officerBadge = data.officerBadge or data.officer_badge or ''

    -- Attach the complaint to a real officer where we can. NULL means "we couldn't
    -- tell who this is about" — IA assigns it by hand rather than it going nowhere.
    local officerCid = resolveOfficer(officerName, officerBadge)
    local responsibleAgency, responsibleDomain = allegedEmployeeAgency(officerCid)

    -- The success screen promises the complainant will be contacted, so record a
    -- number they can actually be reached on.
    local complainantPhone = data.complainantPhone or data.complainant_phone
    if not complainantPhone or complainantPhone == '' then
        complainantPhone = GetCitizenPhoneNumber and GetCitizenPhoneNumber(citizenid) or nil
    end
    local incidentDate = data.incidentDate or data.incident_date or nil
    local incidentLocation = data.incidentLocation or data.incident_location or ''

    local complaintId = MySQL.insert.await([[
        INSERT INTO mdt_ia_complaints
        (complaint_number, complainant_citizenid, complainant_name, complainant_phone,
         officer_citizenid, officer_name, officer_badge,
         category, description, incident_date, incident_location, witnesses, evidence, status, job_type, agency)
        VALUES ('', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', ?, ?)
    ]], {
        citizenid,
        complainantName,
        complainantPhone,
        officerCid,
        officerName,
        officerBadge,
        data.category or 'other',
        data.description or '',
        incidentDate,
        incidentLocation,
        witnesses or '[]',
        evidence or '[]',
        responsibleDomain,
        responsibleAgency
    })

    if not complaintId or complaintId <= 0 then
        return { success = false, error = 'Failed to submit complaint' }
    end

    local complaintNumber = buildComplaintNumber(complaintId)
    MySQL.update.await('UPDATE mdt_ia_complaints SET complaint_number = ? WHERE id = ?', { complaintNumber, complaintId })

    ComplaintCooldown[citizenid] = GetGameTimer()

    return {
        success = true,
        complaintNumber = complaintNumber
    }
end)

-- Get paginated list of IA complaints
ps.registerCallback(resourceName .. ':server:getIAComplaints', function(source, pageNum, filters)
    local src = source
    if filters ~= nil and type(filters) ~= 'table' then
        return { complaints = {}, hasMore = false, error = 'Invalid filters' }
    end
    filters = filters or {}

    if not canViewIA(src) then
        ps.debug('getIAComplaints: CheckAuth failed for source ' .. tostring(src))
        return { complaints = {}, hasMore = false }
    end

    local page = tonumber(pageNum) or 1
    if page ~= page or page == math.huge or page < 1 then page = 1 end
    page = math.min(10000, math.floor(page))
    local limit = Config.Pagination and Config.Pagination.Cases or 20
    limit = tonumber(limit) or 20
    if limit ~= limit or limit == math.huge or limit < 1 then limit = 20 end
    limit = math.min(100, math.floor(limit))
    local offset = (page - 1) * limit

    local clauses = {}
    local values = {}

    -- Restrict list results to the actual responsible employer. The
    -- authorized SADLE IA team may triage police records statewide.
    clauses[#clauses + 1] = "job_type = ? AND (agency = ? OR (? = 'sadle' AND job_type = 'police'))"
    values[#values + 1] = GetMdtDomain(src)
    values[#values + 1] = ps.getJobName(src)
    values[#values + 1] = ps.getJobName(src)

    if filters.status ~= nil and (type(filters.status) ~= 'string' or #filters.status > 40) then
        return { complaints = {}, hasMore = false, error = 'Invalid status filter' }
    end
    if filters.status and filters.status ~= '' then
        clauses[#clauses + 1] = 'status = ?'
        values[#values + 1] = filters.status
    end

    if filters.search ~= nil and (type(filters.search) ~= 'string' or #filters.search > 100) then
        return { complaints = {}, hasMore = false, error = 'Invalid search filter' }
    end
    if filters.search and filters.search ~= '' then
        clauses[#clauses + 1] = '(officer_name LIKE ? OR complainant_name LIKE ? OR complaint_number LIKE ?)'
        local searchTerm = '%' .. filters.search .. '%'
        values[#values + 1] = searchTerm
        values[#values + 1] = searchTerm
        values[#values + 1] = searchTerm
    end

    local whereClause = ''
    if #clauses > 0 then
        whereClause = 'WHERE ' .. table.concat(clauses, ' AND ')
    end

    values[#values + 1] = limit
    values[#values + 1] = offset

    local query = ([[
        SELECT id, complaint_number, complainant_name, officer_name, officer_badge,
               category, status, assigned_to_name, created_at
        FROM mdt_ia_complaints
        %s
        ORDER BY created_at DESC, id DESC
        LIMIT ? OFFSET ?
    ]]):format(whereClause)

    local originalCid = ps.getIdentifier(src)
    local originalJob = ps.getJobName(src)
    local ok, rows = pcall(MySQL.query.await, query, values)
    -- Returning an IA list after an employment/character switch leaks
    -- confidential investigations even if the initial query was scoped.
    if not canViewIA(src) or ps.getIdentifier(src) ~= originalCid
        or ps.getJobName(src) ~= originalJob then
        return { complaints = {}, hasMore = false }
    end

    if not ok or type(rows) ~= 'table' then
        ps.warn('[getIAComplaints] query failed: ' .. tostring(rows))
        return { complaints = {}, hasMore = false }
    end

    return {
        complaints = rows or {},
        hasMore = rows and #rows >= limit or false
    }
end)

-- Get single IA complaint with notes
ps.registerCallback(resourceName .. ':server:getIAComplaint', function(source, data)
    local src = source
    if not canViewIA(src) then return { success = false, error = 'Unauthorized' } end

    local complaintId = tonumber(data)
    if not complaintId or complaintId ~= complaintId or complaintId == math.huge
        or complaintId <= 0 or complaintId % 1 ~= 0 then
        return { success = false, error = 'Invalid complaint id' }
    end

    local actorCitizenid, actorJob = ps.getIdentifier(src), ps.getJobName(src)
    local complaint = MySQL.single.await('SELECT * FROM mdt_ia_complaints WHERE id = ?', { complaintId })
    if not canViewIA(src) or ps.getIdentifier(src) ~= actorCitizenid
        or ps.getJobName(src) ~= actorJob or not canAccessIARecord(src, complaint) then
        return { success = false, error = 'Complaint not found or access denied' }
    end

    local nOk, notes = pcall(MySQL.query.await, [[
        SELECT id, complaint_id, content, author_citizenid, author_name, created_at
        FROM mdt_ia_notes
        WHERE complaint_id = ?
        ORDER BY created_at DESC, id DESC
    ]], { complaintId })

    if not canViewIA(src) or ps.getIdentifier(src) ~= actorCitizenid
        or ps.getJobName(src) ~= actorJob or not canAccessIARecord(src, complaint) then
        return { success = false, error = 'Authorization changed' }
    end
    if not nOk or type(notes) ~= 'table' then
        return { success = false, error = 'Unable to load investigation notes' }
    end
    return {
        success = true,
        data = {
            complaint = complaint,
            notes = notes
        }
    }
end)

-- Get IA complaints against a specific officer.
--
-- Matches on the officer's citizenid where the complaint carries one, and still
-- falls back to the name so complaints filed before the link existed (or ones IA
-- never managed to assign) don't vanish from the profile.
ps.registerCallback(resourceName .. ':server:getIAHistoryForOfficer', function(source, officerName, officerCid)
    local src = source
    if not canViewIA(src) then return {} end

    if officerName ~= nil and (type(officerName) ~= 'string' or #officerName > 255) then return {} end
    if officerCid ~= nil and (type(officerCid) ~= 'string' or #officerCid > 64) then return {} end
    if (not officerName or officerName == '') and (not officerCid or officerCid == '') then
        return {}
    end

    local ok, rows = pcall(MySQL.query.await, [[
        SELECT id, complaint_number, category, status, created_at
        FROM mdt_ia_complaints
        WHERE job_type = ?
          AND (agency = ? OR (? = 'sadle' AND job_type = 'police'))
          AND (
                (officer_citizenid IS NOT NULL AND officer_citizenid = ?)
             OR (officer_citizenid IS NULL AND ? <> '' AND officer_name LIKE ?)
          )
        ORDER BY created_at DESC, id DESC
        LIMIT 50
    ]], {
        GetMdtDomain(src),
        ps.getJobName(src),
        ps.getJobName(src),
        officerCid or '',
        officerName or '',
        '%' .. (officerName or '') .. '%',
    })

    if not ok or type(rows) ~= 'table' or not canViewIA(src) then return {} end
    return rows
end)

-- Update IA complaint details (officer, badge, date, location)
ps.registerCallback(resourceName .. ':server:updateIAComplaintInfo', function(source, complaintId, updates)
    local src = source
    if not canManageIA(src) then return { success = false, error = 'Unauthorized' } end

    complaintId = tonumber(complaintId)
    if updates ~= nil and type(updates) ~= 'table' then
        return { success = false, error = 'Invalid complaint updates' }
    end
    updates = updates or {}
    if not complaintId or complaintId ~= complaintId or complaintId == math.huge or complaintId <= 0 or complaintId % 1 ~= 0 then
        return { success = false, error = 'Invalid complaint id' }
    end
    if not ownsIAComplaint(src, complaintId) then return { success = false, error = 'Complaint access denied' } end

    local sets = {}
    local vals = {}

    if updates.officer_name ~= nil and (type(updates.officer_name) ~= 'string' or #updates.officer_name > 255) then
        return { success = false, error = 'Invalid officer name' }
    end
    if updates.officer_name ~= nil then
        sets[#sets + 1] = 'officer_name = ?'
        vals[#vals + 1] = updates.officer_name
    end
    if updates.officer_badge ~= nil and (type(updates.officer_badge) ~= 'string' or #updates.officer_badge > 64) then
        return { success = false, error = 'Invalid officer badge' }
    end
    if updates.officer_badge ~= nil then
        sets[#sets + 1] = 'officer_badge = ?'
        vals[#vals + 1] = updates.officer_badge
    end

    -- IA correcting the name or badge is exactly when an unassigned complaint can
    -- finally be pinned to a real officer, so re-resolve it here.
    if updates.officer_name ~= nil or updates.officer_badge ~= nil then
        local existing = MySQL.single.await(
            'SELECT officer_name, officer_badge FROM mdt_ia_complaints WHERE id = ?', { complaintId })
        local name  = updates.officer_name  ~= nil and updates.officer_name  or (existing and existing.officer_name)
        local badge = updates.officer_badge ~= nil and updates.officer_badge or (existing and existing.officer_badge)
        local correctedCid = resolveOfficer(name, badge)
        local correctedAgency, correctedDomain = allegedEmployeeAgency(correctedCid)
        if correctedAgency and correctedDomain ~= GetMdtDomain(src) then
            return { success = false, error = 'Accused employee belongs to a different IA service' }
        end
        if correctedAgency and ps.getJobName(src) ~= correctedAgency and ps.getJobName(src) ~= 'sadle' then
            return { success = false, error = 'Cannot transfer complaint to another agency' }
        end
        sets[#sets + 1] = 'officer_citizenid = ?'
        vals[#vals + 1] = correctedCid
        sets[#sets + 1] = 'agency = ?'
        vals[#vals + 1] = correctedAgency
    end
    if updates.incident_date ~= nil and (type(updates.incident_date) ~= 'string' or #updates.incident_date > 32) then
        return { success = false, error = 'Invalid incident date' }
    end
    if updates.incident_date ~= nil then
        sets[#sets + 1] = 'incident_date = ?'
        vals[#vals + 1] = updates.incident_date
    end
    if updates.incident_location ~= nil and (type(updates.incident_location) ~= 'string' or #updates.incident_location > 255) then
        return { success = false, error = 'Invalid incident location' }
    end
    if updates.incident_location ~= nil then
        sets[#sets + 1] = 'incident_location = ?'
        vals[#vals + 1] = updates.incident_location
    end

    if #sets == 0 then
        return { success = false, error = 'No fields to update' }
    end

    if not canManageIA(src) or not ownsIAComplaint(src, complaintId) then
        return { success = false, error = 'Authorization changed' }
    end
    vals[#vals + 1] = complaintId
    local affected = MySQL.update.await('UPDATE mdt_ia_complaints SET ' .. table.concat(sets, ', ') .. ' WHERE id = ?', vals)
    if affected == nil then return { success = false, error = 'Complaint update failed' } end
    return { success = true }
end)

-- Update IA complaint status
ps.registerCallback(resourceName .. ':server:updateIAStatus', function(source, complaintId, status)
    local src = source
    if not canManageIA(src) then return { success = false, error = 'Unauthorized' } end

    complaintId = tonumber(complaintId)
    if not complaintId or complaintId ~= complaintId or complaintId == math.huge
        or complaintId <= 0 or complaintId % 1 ~= 0 or type(status) ~= 'string'
        or not STATUS_TEXT[status] then
        return { success = false, error = 'Invalid complaint id or status' }
    end
    if not ownsIAComplaint(src, complaintId) then return { success = false, error = 'Complaint access denied' } end

    if not canManageIA(src) or not ownsIAComplaint(src, complaintId) then
        return { success = false, error = 'Authorization changed' }
    end
    local ok, err = pcall(MySQL.update.await, 'UPDATE mdt_ia_complaints SET status = ? WHERE id = ?', { status, complaintId })
    if not ok or err == nil then
        ps.warn('[updateIAStatus] Failed: ' .. tostring(err))
        return { success = false, error = 'Failed to update status: ' .. tostring(err) }
    end

    mailComplainantStatus(complaintId, status)

    return { success = true }
end)

-- Assign an investigator to an IA complaint (or unassign with '__unassign__')
ps.registerCallback(resourceName .. ':server:assignIAComplaint', function(source, complaintId, assigneeCitizenId)
    local src = source
    if not canManageIA(src) then return { success = false, error = 'Unauthorized' } end

    complaintId = tonumber(complaintId)
    if not complaintId or complaintId ~= complaintId or complaintId == math.huge
        or complaintId <= 0 or complaintId % 1 ~= 0
        or type(assigneeCitizenId) ~= 'string' or not assigneeCitizenId:find('%S')
        or #assigneeCitizenId > 64 then
        return { success = false, error = 'Invalid complaint or assignee' }
    end
    if not ownsIAComplaint(src, complaintId) then return { success = false, error = 'Complaint access denied' } end

    -- Handle unassign
    if assigneeCitizenId == '__unassign__' then
        if not canManageIA(src) or not ownsIAComplaint(src, complaintId) then
            return { success = false, error = 'Authorization changed' }
        end
        local affected = MySQL.update.await('UPDATE mdt_ia_complaints SET assigned_to = NULL, assigned_to_name = NULL WHERE id = ?', { complaintId })
        return { success = affected ~= nil }
    end

    -- A department investigator cannot be assigned to another employer's
    -- confidential IA case merely by submitting their citizen ID.
    if not CanManageMdtPersonnel(src, assigneeCitizenId)
        or not canManageIA(src) or not ownsIAComplaint(src, complaintId) then
        return { success = false, error = 'Investigator must belong to your authorized department' }
    end
    local profile = MySQL.single.await('SELECT fullname FROM mdt_profiles WHERE citizenid = ?', { assigneeCitizenId })
    local assigneeName = profile and profile.fullname or 'Unknown'
    if type(assigneeName) ~= 'string' or not assigneeName:find('%S') then
        return { success = false, error = 'Investigator profile unavailable' }
    end
    if not CanManageMdtPersonnel(src, assigneeCitizenId)
        or not canManageIA(src) or not ownsIAComplaint(src, complaintId) then
        return { success = false, error = 'Authorization changed' }
    end

    local affected = MySQL.update.await('UPDATE mdt_ia_complaints SET assigned_to = ?, assigned_to_name = ? WHERE id = ?', {
        assigneeCitizenId,
        assigneeName,
        complaintId
    })

    return { success = affected ~= nil }
end)

-- Add a note to an IA complaint
ps.registerCallback(resourceName .. ':server:addIANote', function(source, complaintId, content)
    local src = source
    if not canManageIA(src) then return { success = false, error = 'Unauthorized' } end

    complaintId = tonumber(complaintId)
    if not complaintId or complaintId ~= complaintId or complaintId == math.huge
        or complaintId <= 0 or complaintId % 1 ~= 0 or type(content) ~= 'string'
        or not content:find('%S') or #content > 10000 then
        return { success = false, error = 'Invalid complaint or empty note' }
    end
    if not ownsIAComplaint(src, complaintId) then return { success = false, error = 'Complaint access denied' } end

    local citizenId = ps.getIdentifier(src)
    if type(citizenId) ~= 'string' or not citizenId:find('%S') or #citizenId > 64 then
        return { success = false, error = 'Invalid investigator identity' }
    end
    local profile = MySQL.single.await('SELECT fullname FROM mdt_profiles WHERE citizenid = ?', { citizenId })
    local authorName = profile and profile.fullname or 'Unknown'

    if not canManageIA(src) or ps.getIdentifier(src) ~= citizenId
        or not ownsIAComplaint(src, complaintId) then
        return { success = false, error = 'Authorization changed' }
    end
    local inserted = MySQL.insert.await([[
        INSERT INTO mdt_ia_notes (complaint_id, content, author_citizenid, author_name)
        VALUES (?, ?, ?, ?)
    ]], { complaintId, content, citizenId, authorName })

    return { success = inserted ~= nil and inserted ~= false }
end)

-- Delete a note from an IA complaint
ps.registerCallback(resourceName .. ':server:deleteIANote', function(source, noteId, complaintId)
    local src = source
    if not canManageIA(src) then return { success = false, error = 'Unauthorized' } end

    noteId = tonumber(noteId)
    complaintId = tonumber(complaintId)
    if not noteId or noteId ~= noteId or noteId == math.huge or noteId <= 0 or noteId % 1 ~= 0
        or not complaintId or complaintId ~= complaintId or complaintId == math.huge
        or complaintId <= 0 or complaintId % 1 ~= 0 then
        return { success = false, error = 'Invalid note or complaint' }
    end
    if not ownsIAComplaint(src, complaintId) then return { success = false, error = 'Complaint access denied' } end

    if not canManageIA(src) or not ownsIAComplaint(src, complaintId) then
        return { success = false, error = 'Authorization changed' }
    end
    local affected = MySQL.update.await('DELETE FROM mdt_ia_notes WHERE id = ? AND complaint_id = ?', { noteId, complaintId })
    return { success = type(affected) == 'number' and affected > 0 }
end)

-- Stage 4: local IA referrals to SADLE. This additive queue does not transfer
-- ownership or expose all local IA files to unrelated agencies.
local function iaReferralSchemaReady()
    local ok = pcall(MySQL.query.await, [[
        CREATE TABLE IF NOT EXISTS mdt_ia_referrals (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            complaint_id INT UNSIGNED NOT NULL,
            referring_agency VARCHAR(40) NOT NULL,
            referred_by_citizenid VARCHAR(64) NOT NULL,
            reason VARCHAR(1000) NOT NULL,
            status VARCHAR(24) NOT NULL DEFAULT 'pending',
            received_by_citizenid VARCHAR(64) DEFAULT NULL,
            received_at DATETIME DEFAULT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY idx_ia_referral_complaint (complaint_id),
            KEY idx_ia_referral_status (status, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    return ok
end

ps.registerCallback(resourceName .. ':server:referIAComplaintToSADLE', function(source, complaintId, reason)
    local src = source
    local id = tonumber(complaintId)
    if not id or id ~= id or id == math.huge or id <= 0 or id % 1 ~= 0
        or type(reason) ~= 'string' or #reason < 10 or #reason > 1000
        or not reason:find('%S') then
        return {success = false, error = 'Valid complaint and referral reason required'}
    end
    if not canManageIA(src) then return {success = false, error = 'Unauthorized'} end
    local job, cid = ps.getJobName(src), ps.getIdentifier(src)
    if type(job) ~= 'string' or not job:find('%S') or #job > 64
        or type(cid) ~= 'string' or not cid:find('%S') or #cid > 64 or job == 'sadle' then
        return {success = false, error = 'Local referring agency required'}
    end
    local record = MySQL.single.await(
        'SELECT agency, job_type FROM mdt_ia_complaints WHERE id = ? LIMIT 1', {id})
    if not record or record.agency ~= job or record.job_type ~= 'police'
        or not canManageIA(src) or ps.getIdentifier(src) ~= cid then
        return {success = false, error = 'Complaint not owned by referring agency'}
    end
    if not iaReferralSchemaReady() then return {success = false, error = 'Referral storage unavailable'} end
    -- Another SQL yield may change the player's role or character.
    if not canManageIA(src) or ps.getJobName(src) ~= job
        or ps.getIdentifier(src) ~= cid then
        return {success = false, error = 'Authorization changed'}
    end
    local ok, idOrError = pcall(MySQL.insert.await, [[
        INSERT INTO mdt_ia_referrals
            (complaint_id, referring_agency, referred_by_citizenid, reason, status)
        VALUES (?, ?, ?, ?, 'pending')
    ]], {id, job, cid, reason})
    if not ok or type(idOrError) ~= 'number' or idOrError <= 0 then
        return {success = false, error = 'Referral already exists or could not be saved'}
    end
    if ps.auditLog then
        ps.auditLog(src, 'ia_referred_to_sadle', 'ia_complaint', tostring(id),
            {referral_id = idOrError, agency = job})
    end
    return {success = true, referralId = idOrError}
end)

ps.registerCallback(resourceName .. ':server:getSADLEIAReferrals', function(source, page)
    local src = source
    if ps.getJobName(src) ~= 'sadle' or not canViewIA(src) then return {} end
    local cid = ps.getIdentifier(src)
    if not cid or not iaReferralSchemaReady() then return {} end
    local n = math.max(1, math.min(100, math.floor(tonumber(page) or 1)))
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT r.id, r.complaint_id, r.referring_agency, r.status, r.reason,
               r.created_at, c.complaint_number, c.category
        FROM mdt_ia_referrals r
        INNER JOIN mdt_ia_complaints c ON c.id = r.complaint_id
        WHERE c.job_type = 'police'
        ORDER BY r.created_at DESC, r.id DESC LIMIT 25 OFFSET ?
    ]], {(n - 1) * 25})
    if ps.getJobName(src) ~= 'sadle' or ps.getIdentifier(src) ~= cid or not canViewIA(src) then
        return {}
    end
    return ok and rows or {}
end)


-- SADLE may accept a pending referral for investigation. The complaint remains
-- owned by the original agency; this merely records the formal state handoff.
ps.registerCallback(resourceName .. ':server:acceptSADLEIAReferral', function(source, referralId)
    local src = source
    local id = tonumber(referralId)
    if not id then return {success = false, error = 'Invalid referral'} end
    if ps.getJobName(src) ~= 'sadle' or not canManageIA(src) then
        return {success = false, error = 'SADLE IA authorization required'}
    end
    local actor = ps.getIdentifier(src)
    if not actor then return {success = false, error = 'Invalid investigator'} end
    if not iaReferralSchemaReady() then
        return {success = false, error = 'Referral storage unavailable'}
    end
    if ps.getJobName(src) ~= 'sadle' or ps.getIdentifier(src) ~= actor
        or not canManageIA(src) then
        return {success = false, error = 'Authorization changed'}
    end
    -- The status predicate prevents overwriting an already accepted referral.
    local ok, changed = pcall(MySQL.update.await, [[
        UPDATE mdt_ia_referrals r
        INNER JOIN mdt_ia_complaints c ON c.id = r.complaint_id
        SET r.status = 'accepted', r.received_by_citizenid = ?,
            r.received_at = NOW()
        WHERE r.id = ? AND r.status = 'pending' AND c.job_type = 'police'
    ]], {actor, id})
    if not ok or tonumber(changed) ~= 1 then
        return {success = false, error = 'Pending police referral not found'}
    end
    if ps.auditLog then
        ps.auditLog(src, 'ia_referral_accepted', 'ia_referral', tostring(id),
            {accepted_by = actor})
    end
    return {success = true}
end)


-- Referring agency command may check its own referral status, but cannot
-- enumerate other agencies' submissions or see SADLE investigator notes.
ps.registerCallback(resourceName .. ':server:getIAReferralStatus', function(source, complaintId)
    local src = source
    local id = tonumber(complaintId)
    if not id or not canViewIA(src) then return {} end
    local job, cid = ps.getJobName(src), ps.getIdentifier(src)
    if not job or not cid or not ownsIAComplaint(src, id) then return {} end
    if not iaReferralSchemaReady() then return {} end
    local ok, row = pcall(MySQL.single.await, [[
        SELECT r.id, r.status, r.created_at, r.received_at
        FROM mdt_ia_referrals r
        INNER JOIN mdt_ia_complaints c ON c.id = r.complaint_id
        WHERE r.complaint_id = ? AND c.agency = ? AND c.job_type = 'police'
        LIMIT 1
    ]], {id, job})
    if not canViewIA(src) or ps.getJobName(src) ~= job
        or ps.getIdentifier(src) ~= cid or not ownsIAComplaint(src, id) then return {} end
    return ok and row or {}
end)
