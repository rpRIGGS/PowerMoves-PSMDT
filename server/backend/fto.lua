local resourceName = tostring(GetCurrentResourceName())

-- Preserve the proven FTO engine, but separate its operational training
-- families by the actual QBCore type. Legacy police and hospital rows keep
-- their existing values. New DOJ and fire assignments have their own domains.
local function getFTODomain(src)
    local jobType = ps.getJobType(src)
    local jobName = ps.getJobName(src)
    if jobType == 'fire' then return 'fire' end
    if jobType == 'doj' then return 'doj' end
    for _, name in ipairs(Config.DojJobs or {}) do
        if jobName == name then return 'doj' end
    end
    return GetMdtDomain(src)
end

-- Phase 2: FTO assignments are domain-scoped so EMS sees its own trainees and
-- police see theirs. Phases/competencies are already scoped by exact job name.
-- Existing assignment rows default to 'police'; new ones take the creator's domain.
CreateThread(function()
    Wait(2500)
    if EnsureColumn then
        EnsureColumn('mdt_fto_assignments', 'job_type', "`job_type` varchar(10) NOT NULL DEFAULT 'police'")
        -- Existing records remain NULL until explicitly reconciled to their
        -- historical employer. New assignments are always agency-keyed.
        EnsureColumn('mdt_fto_assignments', 'agency_job', "`agency_job` varchar(64) NULL DEFAULT NULL")
    end
end)

local function buildFTONumber(id)
    local year = os.date('%Y')
    return ('FTO-%s-%05d'):format(year, id)
end

-- Get phases for job
ps.registerCallback(resourceName .. ':server:getFTOPhases', function(source)
    local src = source
    if not CheckAuth(src) then return {} end
    local job = ps.getJobName(src)
    if type(job) ~= 'string' or not job:find('%S') then return {} end
    local ok, rows = pcall(MySQL.query.await, 'SELECT * FROM mdt_fto_phases WHERE job = ? ORDER BY sort_order ASC', { job })
    if not CheckAuth(src) or ps.getJobName(src) ~= job then return {} end
    return (ok and rows) or {}
end)

-- Save phases (replace all for job)
ps.registerCallback(resourceName .. ':server:saveFTOPhases', function(source, phases)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    if not CheckPermission(src, 'fto_manage') then return { success = false, error = 'No permission' } end
    local job = ps.getJobName(src)
    if type(job) ~= 'string' or not job:find('%S') or #job > 64 then
        return { success = false, error = 'Missing agency' }
    end
    if type(phases) ~= 'table' or #phases > 100 then
        return { success = false, error = 'Invalid phase list' }
    end
    for key in pairs(phases) do
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > #phases then
            return { success = false, error = 'Invalid phase list' }
        end
    end
    for _, phase in ipairs(phases) do
        if type(phase) ~= 'table' or type(phase.name) ~= 'string'
            or not phase.name:find('%S') or #phase.name > 255
            or (phase.description ~= nil and (type(phase.description) ~= 'string' or #phase.description > 2000))
            or (phase.duration_days ~= nil and (not tonumber(phase.duration_days)
                or tonumber(phase.duration_days) ~= tonumber(phase.duration_days)
                or tonumber(phase.duration_days) < 0 or tonumber(phase.duration_days) > 3650
                or tonumber(phase.duration_days) % 1 ~= 0)) then
            return { success = false, error = 'Invalid phase' }
        end
    end

    if not CheckAuth(src) or not CheckPermission(src, 'fto_manage')
        or ps.getJobName(src) ~= job then
        return { success = false, error = 'Authorization changed' }
    end
    local statements = {
        { query = 'DELETE FROM mdt_fto_phases WHERE job = ?', values = { job } }
    }
    for i, phase in ipairs(phases) do
        statements[#statements + 1] = {
            query = 'INSERT INTO mdt_fto_phases (job, name, description, duration_days, sort_order) VALUES (?, ?, ?, ?, ?)',
            values = { job, phase.name, phase.description or '', tonumber(phase.duration_days) or 0, i }
        }
    end
    if not MySQL.transaction or not MySQL.transaction.await then
        return { success = false, error = 'Database transactions unavailable' }
    end
    local ok, committed = pcall(MySQL.transaction.await, statements)
    if not ok or not committed then
        return { success = false, error = 'Failed to save FTO phases' }
    end
    return { success = true }
end)

-- Get competencies for job
ps.registerCallback(resourceName .. ':server:getFTOCompetencies', function(source)
    local src = source
    if not CheckAuth(src) then return {} end
    local job = ps.getJobName(src)
    if type(job) ~= 'string' or not job:find('%S') then return {} end
    local ok, rows = pcall(MySQL.query.await, 'SELECT * FROM mdt_fto_competencies WHERE job = ? ORDER BY sort_order ASC', { job })
    if not CheckAuth(src) or ps.getJobName(src) ~= job then return {} end
    return (ok and rows) or {}
end)

-- Save competencies (replace all for job)
ps.registerCallback(resourceName .. ':server:saveFTOCompetencies', function(source, competencies)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    if not CheckPermission(src, 'fto_manage') then return { success = false, error = 'No permission' } end
    local job = ps.getJobName(src)
    if type(job) ~= 'string' or job == '' or #job > 64 then
        return { success = false, error = 'Missing agency' }
    end
    if type(competencies) ~= 'table' or #competencies > 200 then
        return { success = false, error = 'Invalid competency list' }
    end
    for key in pairs(competencies) do
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > #competencies then
            return { success = false, error = 'Invalid competency list' }
        end
    end
    for _, comp in ipairs(competencies) do
        if type(comp) ~= 'table' or type(comp.name) ~= 'string'
            or not comp.name:find('%S') or #comp.name > 255
            or (comp.category ~= nil and (type(comp.category) ~= 'string' or #comp.category > 100
                or not comp.category:find('%S'))) then
            return { success = false, error = 'Invalid competency' }
        end
    end

    if not CheckAuth(src) or not CheckPermission(src, 'fto_manage')
        or ps.getJobName(src) ~= job then
        return { success = false, error = 'Authorization changed' }
    end
    local statements = {
        { query = 'DELETE FROM mdt_fto_competencies WHERE job = ?', values = { job } }
    }
    for i, comp in ipairs(competencies) do
        statements[#statements + 1] = {
            query = 'INSERT INTO mdt_fto_competencies (job, name, category, sort_order) VALUES (?, ?, ?, ?)',
            values = { job, comp.name, comp.category or 'General', i }
        }
    end
    if not MySQL.transaction or not MySQL.transaction.await then
        return { success = false, error = 'Database transactions unavailable' }
    end
    local ok, committed = pcall(MySQL.transaction.await, statements)
    if not ok or not committed then
        return { success = false, error = 'Failed to save FTO competencies' }
    end
    return { success = true }
end)

-- Get paginated list of FTO assignments
ps.registerCallback(resourceName .. ':server:getFTOList', function(source, pageNum, filters)
    local src = source
    if not CheckAuth(src) then return { entries = {}, hasMore = false } end

    if type(filters) ~= 'table' then filters = {} end
    local citizenId = ps.getIdentifier(src)
    if type(citizenId) ~= 'string' or not citizenId:find('%S') then
        return { entries = {}, hasMore = false }
    end
    local hasFTOView = CheckPermission(src, 'fto_view')

    local page = tonumber(pageNum) or 1
    if page ~= page or page == math.huge or page < 1 then page = 1 end
    page = math.min(10000, math.floor(page))
    local limit = 20
    local offset = (page - 1) * limit

    local clauses = {}
    local values = {}

    -- Domain scope: each side only sees its own FTO assignments.
    if type(ps.getJobName(src)) ~= 'string' or not ps.getJobName(src):find('%S')
        or not getFTODomain(src) then
        return { entries = {}, hasMore = false }
    end
    clauses[#clauses + 1] = 'a.job_type = ? AND a.agency_job = ?'
    values[#values + 1] = getFTODomain(src)
    values[#values + 1] = ps.getJobName(src)

    if not hasFTOView then
        clauses[#clauses + 1] = '(a.trainee_citizenid = ? OR a.trainer_citizenid = ?)'
        values[#values + 1] = citizenId
        values[#values + 1] = citizenId
    end

    if type(filters.status) == 'string' and #filters.status <= 40
        and filters.status ~= '' and filters.status ~= 'all' then
        clauses[#clauses + 1] = 'a.status = ?'
        values[#values + 1] = filters.status
    end

    if type(filters.search) == 'string' and filters.search:find('%S') and #filters.search <= 100 then
        clauses[#clauses + 1] = '(a.trainee_name LIKE ? OR a.trainer_name LIKE ? OR a.fto_number LIKE ?)'
        local s = '%' .. filters.search:gsub('%%', '\\%%'):gsub('_', '\\_') .. '%'
        values[#values + 1] = s
        values[#values + 1] = s
        values[#values + 1] = s
    end

    local whereClause = #clauses > 0 and ('WHERE ' .. table.concat(clauses, ' AND ')) or ''
    values[#values + 1] = limit
    values[#values + 1] = offset

    local query = ([[
        SELECT a.*, p.name AS current_phase,
            (SELECT COUNT(*) FROM mdt_fto_dors d WHERE d.assignment_id = a.id) AS dor_count,
            (SELECT d2.overall_rating FROM mdt_fto_dors d2 WHERE d2.assignment_id = a.id ORDER BY d2.created_at DESC LIMIT 1) AS latest_rating
        FROM mdt_fto_assignments a
        LEFT JOIN mdt_fto_phases p ON a.current_phase_id = p.id
        %s
        ORDER BY a.created_at DESC
        LIMIT ? OFFSET ?
    ]]):format(whereClause)

    local ok, rows = pcall(MySQL.query.await, query, values)
    if not ok then return { entries = {}, hasMore = false, error = 'Unable to load FTO assignments' } end

    -- Reject an old employer's results if the user changes character/job
    -- while the database query is running.
    if not CheckAuth(src) or ps.getIdentifier(src) ~= citizenId
        or getFTODomain(src) ~= values[1] or ps.getJobName(src) ~= values[2] then
        return { entries = {}, hasMore = false }
    end
    return {
        entries = rows or {},
        hasMore = rows and #rows >= limit or false,
    }
end)

-- Enforce the same training-domain boundary for direct reads and mutations
-- that the FTO list already applies. Agency-specific grants will be a
-- separate step before cross-agency accreditation access is enabled.
local function canAccessFTORecord(src, assignmentId)
    local row = MySQL.single.await(
        'SELECT job_type, agency_job FROM mdt_fto_assignments WHERE id = ? LIMIT 1',
        {assignmentId}
    )
    return row ~= nil and row.job_type == getFTODomain(src)
        and row.agency_job ~= nil and row.agency_job == ps.getJobName(src)
        and CheckAuth(src)
end

-- Get single FTO assignment with DORs
ps.registerCallback(resourceName .. ':server:getFTO', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false } end

    local assignmentId = tonumber(data)
    if not assignmentId or assignmentId ~= assignmentId or assignmentId == math.huge
        or assignmentId <= 0 or assignmentId % 1 ~= 0 then
        return { success = false, error = 'Invalid ID' }
    end

    local entry = MySQL.single.await([[
        SELECT a.*, p.name AS current_phase
        FROM mdt_fto_assignments a
        LEFT JOIN mdt_fto_phases p ON a.current_phase_id = p.id
        WHERE a.id = ?
    ]], { assignmentId })
    if not entry then return { success = false, error = 'Not found' } end
    if entry.job_type ~= getFTODomain(src)
        or entry.agency_job == nil or entry.agency_job ~= ps.getJobName(src) then
        return { success = false, error = 'Unauthorized' }
    end

    local citizenId = ps.getIdentifier(src)
    local hasFTOView = CheckPermission(src, 'fto_view')
    if not hasFTOView and entry.trainee_citizenid ~= citizenId and entry.trainer_citizenid ~= citizenId then
        return { success = false, error = 'Unauthorized' }
    end

    local dOk, dors = pcall(MySQL.query.await, [[
        SELECT d.*, p.name AS phase_name
        FROM mdt_fto_dors d
        LEFT JOIN mdt_fto_phases p ON d.phase_id = p.id
        WHERE d.assignment_id = ?
        ORDER BY d.created_at DESC
    ]], { assignmentId })

    if not dOk then return { success = false, error = 'Unable to load FTO observations' } end
    local dorList = dors or {}
    for _, dor in ipairs(dorList) do
        local rOk, ratings = pcall(MySQL.query.await, [[
            SELECT r.*, c.name AS competency_name, c.category AS competency_category
            FROM mdt_fto_dor_ratings r
            LEFT JOIN mdt_fto_competencies c ON r.competency_id = c.id
            WHERE r.dor_id = ?
            ORDER BY c.sort_order ASC
        ]], { dor.id })
        if not rOk then return { success = false, error = 'Unable to load FTO ratings' } end
        dor.ratings = ratings or {}
    end

    if not CheckAuth(src) or ps.getIdentifier(src) ~= citizenId
        or not canAccessFTORecord(src, assignmentId)
        or entry.job_type ~= getFTODomain(src) or entry.agency_job ~= ps.getJobName(src)
        or (not CheckPermission(src, 'fto_view')
            and entry.trainee_citizenid ~= citizenId and entry.trainer_citizenid ~= citizenId) then
        return { success = false, error = 'Authorization changed' }
    end
    return { success = true, data = { entry = entry, dors = dorList } }
end)

-- Get officer FTO history (for roster panel)
ps.registerCallback(resourceName .. ':server:getOfficerFTOHistory', function(source, officerCitizenId)
    local src = source
    if not CheckAuth(src) then return {} end
    if type(officerCitizenId) ~= 'string' or not officerCitizenId:find('%S')
        or #officerCitizenId > 64 then return {} end
    -- A person's milestone summary follows them across employment changes.
    -- Managers may see it only for someone currently employed by their own
    -- agency; other persons' records are not discoverable by arbitrary ID.
    local actorCitizenid, actorEmployer = ps.getIdentifier(src), ps.getJobName(src)
    if type(actorCitizenid) ~= 'string' or not actorCitizenid:find('%S')
        or type(actorEmployer) ~= 'string' or not actorEmployer:find('%S') then return {} end
    local isSelf = officerCitizenId == actorCitizenid
    if not isSelf then
        if not CheckPermission(src, 'fto_view') or not CanManageMdtPersonnel(src, officerCitizenId) then
            return {}
        end
    end

    local ok, rows = pcall(MySQL.query.await, [[
        SELECT a.id, a.fto_number, a.status, a.trainer_name, a.trainee_name,
            a.start_date, a.end_date, a.created_at,
            p.name AS phase_name,
            (SELECT COUNT(*) FROM mdt_fto_dors d WHERE d.assignment_id = a.id) AS dor_count,
            (SELECT d2.overall_rating FROM mdt_fto_dors d2 WHERE d2.assignment_id = a.id ORDER BY d2.created_at DESC LIMIT 1) AS latest_rating
        FROM mdt_fto_assignments a
        LEFT JOIN mdt_fto_phases p ON a.current_phase_id = p.id
        WHERE a.trainee_citizenid = ? AND a.job_type = ? AND a.agency_job = ?
        ORDER BY a.created_at DESC
        LIMIT 150
    ]], { officerCitizenId, getFTODomain(src), ps.getJobName(src) })

    if not CheckAuth(src) or ps.getIdentifier(src) ~= actorCitizenid
        or ps.getJobName(src) ~= actorEmployer
        or not getFTODomain(src) then return {} end
    if not isSelf and (not CheckPermission(src, 'fto_view')
        or not CanManageMdtPersonnel(src, officerCitizenId)) then return {} end
    return (ok and rows) or {}
end)

-- A training record follows its citizen, not their current employer.
-- This read-only transcript deliberately excludes DOR notes and ratings:
-- former employers' private evaluations stay within their authorized agency.
-- The caller can read their own milestones even after transfer or promotion.
ps.registerCallback(resourceName .. ':server:getMyTrainingTranscript', function(source)
    local src = source
    if not CheckAuth(src) then return {} end
    local citizenid = ps.getIdentifier(src)
    if type(citizenid) ~= 'string' or not citizenid:find('%S') then return {} end

    local ok, history = pcall(MySQL.query.await, [[
        SELECT a.fto_number, a.job_type, a.agency_job, a.status,
               a.start_date, a.end_date, a.created_at,
               p.name AS current_phase
        FROM mdt_fto_assignments a
        LEFT JOIN mdt_fto_phases p ON p.id = a.current_phase_id
        WHERE a.trainee_citizenid = ?
        ORDER BY a.created_at DESC, a.id DESC
        LIMIT 150
    ]], { citizenid })
    -- Milestone transcripts follow the character, never the recycled source ID.
    if not CheckAuth(src) or ps.getIdentifier(src) ~= citizenid then return {} end
    return ok and history or {}
end)

-- Create FTO assignment
ps.registerCallback(resourceName .. ':server:createFTOAssignment', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    if not CheckPermission(src, 'fto_manage') then return { success = false, error = 'No permission' } end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid assignment' } end
    if type(data.trainee_citizenid) ~= 'string' or not data.trainee_citizenid:find('%S')
        or #data.trainee_citizenid > 64 then
        return { success = false, error = 'Trainee is required' }
    end
    if type(data.trainer_citizenid) ~= 'string' or not data.trainer_citizenid:find('%S')
        or #data.trainer_citizenid > 64 then
        return { success = false, error = 'Trainer is required' }
    end
    if (data.trainee_name ~= nil and (type(data.trainee_name) ~= 'string' or not data.trainee_name:find('%S') or #data.trainee_name > 255))
        or (data.trainer_name ~= nil and (type(data.trainer_name) ~= 'string' or not data.trainer_name:find('%S') or #data.trainer_name > 255)) then
        return { success = false, error = 'Invalid participant name' }
    end
    if data.trainee_citizenid == data.trainer_citizenid then
        return { success = false, error = 'Trainer must be different from trainee' }
    end
    -- Departmental FTO is not a statewide academy assignment. Both trainee
    -- and field trainer must be verifiably employed by this manager's agency.
    if not getFTODomain(src) or type(ps.getJobName(src)) ~= 'string'
        or not ps.getJobName(src):find('%S') then
        return { success = false, error = 'Missing agency' }
    end
    if not CanManageMdtPersonnel(src, data.trainee_citizenid)
        or not CanManageMdtPersonnel(src, data.trainer_citizenid) then
        return { success = false, error = 'Trainee and trainer must belong to your department' }
    end

    if data.notes ~= nil and (type(data.notes) ~= 'string' or #data.notes > 20000) then
        return { success = false, error = 'Invalid assignment notes' }
    end
    if data.start_date ~= nil and (type(data.start_date) ~= 'string'
        or not data.start_date:match('^%d%d%d%d%-%d%d%-%d%d$')) then
        return { success = false, error = 'Invalid assignment start date' }
    end
    local existing = MySQL.single.await(
        "SELECT id FROM mdt_fto_assignments WHERE trainee_citizenid = ? AND status IN ('active','suspended') LIMIT 1",
        { data.trainee_citizenid })
    if existing then
        return { success = false, error = 'This trainee already has an active FTO assignment' }
    end

    -- Default a new trainee to the first phase of the program if none was chosen,
    -- so they never sit "phase-less" (which breaks DOR/phase tallies).
    local phaseId = tonumber(data.current_phase_id)
    if phaseId and (phaseId ~= phaseId or phaseId == math.huge or phaseId <= 0 or phaseId % 1 ~= 0) then
        return { success = false, error = 'Invalid phase' }
    end
    if not phaseId then
        local job = ps.getJobName and ps.getJobName(src) or nil
        if job then
            local first = MySQL.single.await(
                'SELECT id FROM mdt_fto_phases WHERE job = ? ORDER BY sort_order ASC, id ASC LIMIT 1', { job })
            phaseId = first and first.id or nil
        end
    end

    if phaseId then
        local owner = MySQL.scalar.await('SELECT job FROM mdt_fto_phases WHERE id = ? LIMIT 1', { phaseId })
        if owner ~= ps.getJobName(src) then
            return { success = false, error = 'Phase belongs to another agency' }
        end
    end
    -- Both phase lookup and active-assignment checks may yield. Verify the
    -- manager and both employees again before creating an employer-owned DOR.
    if not CheckAuth(src) or not CheckPermission(src, 'fto_manage')
        or not getFTODomain(src) or not ps.getJobName(src)
        or not CanManageMdtPersonnel(src, data.trainee_citizenid)
        or not CanManageMdtPersonnel(src, data.trainer_citizenid) then
        return { success = false, error = 'Authorization changed' }
    end
    local assignmentId = MySQL.insert.await([[
        INSERT INTO mdt_fto_assignments
        (fto_number, trainee_citizenid, trainee_name, trainer_citizenid, trainer_name,
         current_phase_id, status, start_date, notes, job_type, agency_job)
        VALUES ('', ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?)
    ]], {
        data.trainee_citizenid, data.trainee_name or '',
        data.trainer_citizenid, data.trainer_name or '',
        phaseId,
        data.start_date or os.date('%Y-%m-%d'),
        data.notes or nil,
        getFTODomain(src),
        ps.getJobName(src),
    })

    if not assignmentId or assignmentId <= 0 then return { success = false, error = 'Failed to create assignment' } end

    local ftoNumber = buildFTONumber(assignmentId)
    local numbered = MySQL.update.await('UPDATE mdt_fto_assignments SET fto_number = ? WHERE id = ?', { ftoNumber, assignmentId })
    if not numbered or numbered < 1 then return { success = false, error = 'Failed to finalize assignment number' } end

    return { success = true, id = assignmentId, fto_number = ftoNumber }
end)

-- Update FTO assignment
ps.registerCallback(resourceName .. ':server:updateFTOAssignment', function(source, assignmentId, updates)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    if not CheckPermission(src, 'fto_manage') then return { success = false, error = 'No permission' } end

    assignmentId = tonumber(assignmentId)
    if type(updates) ~= 'table' then return { success = false, error = 'Invalid updates' } end
    if not assignmentId or assignmentId ~= assignmentId or assignmentId == math.huge
        or assignmentId <= 0 or assignmentId % 1 ~= 0 then
        return { success = false, error = 'Invalid ID' }
    end

    local sets = {}
    local vals = {}
    local allowed = { 'current_phase_id', 'status', 'end_date', 'notes', 'trainer_citizenid', 'trainer_name' }

    for _, field in ipairs(allowed) do
        if updates[field] ~= nil then
            sets[#sets + 1] = field .. ' = ?'
            vals[#vals + 1] = updates[field]
        end
    end

    if updates.current_phase_id ~= nil then
        local phase = tonumber(updates.current_phase_id)
        if not phase or phase ~= phase or phase == math.huge or phase <= 0 or phase % 1 ~= 0 then
            return { success = false, error = 'Invalid phase ID' }
        end
    end
    if updates.current_phase_id ~= nil then
        local phaseJob = MySQL.scalar.await('SELECT job FROM mdt_fto_phases WHERE id = ? LIMIT 1', { tonumber(updates.current_phase_id) })
        if phaseJob ~= ps.getJobName(src) then
            return { success = false, error = 'Phase belongs to another agency' }
        end
    end
    if updates.trainer_name ~= nil and (type(updates.trainer_name) ~= 'string'
        or not updates.trainer_name:find('%S') or #updates.trainer_name > 255) then
        return { success = false, error = 'Invalid trainer name' }
    end
    if updates.status ~= nil and (type(updates.status) ~= 'string'
        or not ({ active=true, completed=true, failed=true, suspended=true })[updates.status]) then
        return { success = false, error = 'Invalid assignment status' }
    end
    if updates.end_date ~= nil and (type(updates.end_date) ~= 'string'
        or not updates.end_date:match('^%d%d%d%d%-%d%d%-%d%d$')) then
        return { success = false, error = 'Invalid end date' }
    end
    if updates.notes ~= nil and (type(updates.notes) ~= 'string' or #updates.notes > 20000) then
        return { success = false, error = 'Invalid notes' }
    end
    if #sets == 0 then return { success = false, error = 'No fields to update' } end

    if not canAccessFTORecord(src, assignmentId) then return { success = false, error = 'Unauthorized' } end
    if not CheckPermission(src, 'fto_manage') then return { success = false, error = 'No permission' } end
    if updates.trainer_citizenid ~= nil and (type(updates.trainer_citizenid) ~= 'string'
        or not updates.trainer_citizenid:find('%S') or #updates.trainer_citizenid > 64
        or not CanManageMdtPersonnel(src, updates.trainer_citizenid)) then
        return { success = false, error = 'Trainer must belong to your department' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'fto_manage')
        or not canAccessFTORecord(src, assignmentId) then
        return { success = false, error = 'Authorization changed' }
    end
    vals[#vals + 1] = assignmentId
    local saved = MySQL.update.await('UPDATE mdt_fto_assignments SET ' .. table.concat(sets, ', ') .. ' WHERE id = ?', vals)
    if saved == nil or saved < 1 then return { success = false, error = 'FTO assignment not updated' } end
    return { success = true }
end)

-- ---------------------------------------------------------------------------
-- Phase progression — the core of the trainer tool. Advancing walks the job's
-- ordered phases (by sort_order); advancing past the last phase graduates the
-- trainee (status = completed). Moving back steps one phase down. This keeps the
-- "which phase is next" logic on the server so the UI can't desync.
-- ---------------------------------------------------------------------------
ps.registerCallback(resourceName .. ':server:advanceFTOPhase', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    if not CheckPermission(src, 'fto_manage') then return { success = false, error = 'No permission' } end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid phase request' } end
    local assignmentId = tonumber(data.assignment_id)
    local direction = data.direction or 'next'
    if direction ~= 'next' and direction ~= 'back' then
        return { success = false, error = 'Invalid direction' }
    end
    if not assignmentId or assignmentId ~= assignmentId or assignmentId == math.huge
        or assignmentId <= 0 or assignmentId % 1 ~= 0 then
        return { success = false, error = 'Invalid assignment' }
    end
    if data.note ~= nil and (type(data.note) ~= 'string' or #data.note > 20000) then
        return { success = false, error = 'Invalid phase note' }
    end

    local a = MySQL.single.await(
        'SELECT id, current_phase_id, status, trainee_name FROM mdt_fto_assignments WHERE id = ?', { assignmentId })
    if not a then return { success = false, error = 'Assignment not found' } end
    if not canAccessFTORecord(src, assignmentId) then return { success = false, error = 'Unauthorized' } end
    if not CheckAuth(src) or not CheckPermission(src, 'fto_manage') then
        return { success = false, error = 'Authorization changed' }
    end
    if a.status ~= 'active' then return { success = false, error = 'Only active assignments can change phase' } end

    -- Resolve which job's phase ladder applies: the current phase's job, else the caller's.
    local job = nil
    if a.current_phase_id then
        local cp = MySQL.single.await('SELECT job FROM mdt_fto_phases WHERE id = ?', { a.current_phase_id })
        job = cp and cp.job or nil
    end
    if not job then job = ps.getJobName and ps.getJobName(src) or nil end
    if not job or job ~= ps.getJobName(src) then
        return { success = false, error = 'Training program does not match agency' }
    end

    local phases = MySQL.query.await(
        'SELECT id, name FROM mdt_fto_phases WHERE job = ? ORDER BY sort_order ASC, id ASC', { job }) or {}
    if #phases == 0 then return { success = false, error = 'No phases configured for this program' } end
    if not CheckAuth(src) or not CheckPermission(src, 'fto_manage')
        or not canAccessFTORecord(src, assignmentId) then
        return { success = false, error = 'Authorization changed' }
    end

    -- Locate the current phase in the ladder (0 = not yet placed → next is phase 1).
    local idx = 0
    for i, p in ipairs(phases) do
        if a.current_phase_id and tonumber(p.id) == tonumber(a.current_phase_id) then idx = i break end
    end

    if direction == 'back' then
        if idx <= 1 then return { success = false, error = 'Already at the first phase' } end
        local target = phases[idx - 1]
        local changed = MySQL.update.await('UPDATE mdt_fto_assignments SET current_phase_id = ? WHERE id = ? AND status = ?', { target.id, assignmentId, 'active' })
        if not changed or changed < 1 then return { success = false, error = 'Phase was not updated' } end
        if ps.auditLog then ps.auditLog(src, 'fto_phase_back', 'fto', assignmentId, { to = target.name }) end
        return { success = true, completed = false, action = 'back', phase = target }
    end

    if idx < #phases then
        local target = phases[idx + 1]
        MySQL.update.await('UPDATE mdt_fto_assignments SET current_phase_id = ? WHERE id = ?', { target.id, assignmentId })
        if ps.auditLog then ps.auditLog(src, 'fto_phase_advance', 'fto', assignmentId, { to = target.name, note = data.note }) end
        return { success = true, completed = false, action = 'advance', phase = target }
    end

    -- Past the last phase → graduation.
    local endDate = os.date('%Y-%m-%d')
    local graduated = MySQL.update.await("UPDATE mdt_fto_assignments SET status = 'completed', end_date = ? WHERE id = ? AND status = 'active'", { endDate, assignmentId })
    if not graduated or graduated < 1 then return { success = false, error = 'Graduation was not saved' } end
    if ps.auditLog then ps.auditLog(src, 'fto_completed', 'fto', assignmentId, { trainee = a.trainee_name, note = data.note }) end
    return { success = true, completed = true, action = 'complete' }
end)

-- Set an assignment's status (fail / suspend / reactivate / complete) with the
-- matching end_date bookkeeping in one place.
ps.registerCallback(resourceName .. ':server:setFTOStatus', function(source, data)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    if not CheckPermission(src, 'fto_manage') then return { success = false, error = 'No permission' } end

    if type(data) ~= 'table' then return { success = false, error = 'Invalid status request' } end
    local assignmentId = tonumber(data.assignment_id)
    local status = tostring(data.status or '')
    local valid = { active = true, completed = true, failed = true, suspended = true }
    if not assignmentId or assignmentId ~= assignmentId or assignmentId == math.huge
        or assignmentId <= 0 or assignmentId % 1 ~= 0 or not valid[status] then
        return { success = false, error = 'Invalid request' }
    end

    local a = MySQL.single.await('SELECT id, trainee_name FROM mdt_fto_assignments WHERE id = ?', { assignmentId })
    if not a then return { success = false, error = 'Assignment not found' } end
    if not canAccessFTORecord(src, assignmentId) then return { success = false, error = 'Unauthorized' } end
    if not CheckAuth(src) or not CheckPermission(src, 'fto_manage') then
        return { success = false, error = 'Authorization changed' }
    end

    if status == 'active' then
        -- Reactivating clears the end date.
        local changed = MySQL.update.await("UPDATE mdt_fto_assignments SET status = 'active', end_date = NULL WHERE id = ?", { assignmentId })
        if not changed or changed < 1 then return { success = false, error = 'Status was not saved' } end
    elseif status == 'completed' or status == 'failed' then
        local changed = MySQL.update.await('UPDATE mdt_fto_assignments SET status = ?, end_date = ? WHERE id = ?',
            { status, os.date('%Y-%m-%d'), assignmentId })
        if not changed or changed < 1 then return { success = false, error = 'Status was not saved' } end
    else -- suspended
        local changed = MySQL.update.await('UPDATE mdt_fto_assignments SET status = ? WHERE id = ?', { status, assignmentId })
        if not changed or changed < 1 then return { success = false, error = 'Status was not saved' } end
    end

    if ps.auditLog then ps.auditLog(src, 'fto_status_' .. status, 'fto', assignmentId, { trainee = a.trainee_name }) end
    return { success = true }
end)

-- Delete FTO assignment
ps.registerCallback(resourceName .. ':server:deleteFTOAssignment', function(source, assignmentId)
    local src = source
    if not CheckAuth(src) then return { success = false } end
    if not CheckPermission(src, 'fto_manage') then return { success = false, error = 'No permission' } end

    assignmentId = tonumber(assignmentId)
    if not assignmentId or assignmentId ~= assignmentId or assignmentId == math.huge
        or assignmentId <= 0 or assignmentId % 1 ~= 0 then
        return { success = false, error = 'Invalid ID' }
    end

    if not canAccessFTORecord(src, assignmentId) then return { success = false, error = 'Unauthorized' } end
    if not CheckAuth(src) or not CheckPermission(src, 'fto_manage')
        or not canAccessFTORecord(src, assignmentId) then
        return { success = false, error = 'Authorization changed' }
    end
    local deleted = MySQL.update.await('DELETE FROM mdt_fto_assignments WHERE id = ?', { assignmentId })
    if not deleted or deleted < 1 then return { success = false, error = 'Assignment was not deleted' } end
    return { success = true }
end)

-- Create DOR (Daily Observation Report)
ps.registerCallback(resourceName .. ':server:createFTODor', function(source, data)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'fto_manage') then
        return { success = false, error = 'Unauthorized' }
    end
    if type(data) ~= 'table' then return { success = false, error = 'Invalid DOR payload' } end
    local assignmentId = tonumber(data.assignment_id)
    if not assignmentId or assignmentId ~= assignmentId or assignmentId == math.huge
        or assignmentId <= 0 or assignmentId % 1 ~= 0 then
        return { success = false, error = 'Invalid assignment identifier' }
    end
    if not canAccessFTORecord(src, assignmentId) then
        return { success = false, error = 'Unauthorized' }
    end
    local phaseId = tonumber(data.phase_id)
    if phaseId and (phaseId ~= phaseId or phaseId == math.huge or phaseId <= 0 or phaseId % 1 ~= 0) then
        return { success = false, error = 'Invalid DOR phase' }
    end
    if not phaseId then
        local assignment = MySQL.single.await(
            'SELECT current_phase_id FROM mdt_fto_assignments WHERE id = ?', { assignmentId })
        phaseId = assignment and tonumber(assignment.current_phase_id) or nil
    end
    if not phaseId or phaseId <= 0 or phaseId % 1 ~= 0 then return { success = false, error = 'Invalid assignment training phase' } end
    if phaseId then
        local phaseJob = MySQL.scalar.await('SELECT job FROM mdt_fto_phases WHERE id = ? LIMIT 1', { phaseId })
        if phaseJob ~= ps.getJobName(src) then
            return { success = false, error = 'DOR phase belongs to another program' }
        end
    end
    local citizenId = ps.getIdentifier(src)
    if type(citizenId) ~= 'string' or not citizenId:find('%S') or #citizenId > 64 then
        return { success = false, error = 'Missing author identity' }
    end
    if data.shift_date ~= nil and (type(data.shift_date) ~= 'string'
        or not data.shift_date:match('^%d%d%d%d%-%d%d%-%d%d$')) then
        return { success = false, error = 'Invalid shift date' }
    end
    if data.notes ~= nil and (type(data.notes) ~= 'string' or #data.notes > 20000) then
        return { success = false, error = 'Invalid notes' }
    end
    local overallRating = data.overall_rating == nil and 3 or tonumber(data.overall_rating)
    if overallRating ~= overallRating or overallRating == math.huge
        or overallRating < 1 or overallRating > 5 or overallRating % 1 ~= 0 then
        return { success = false, error = 'Invalid overall rating' }
    end
    local ratings = data.ratings or {}
    if type(ratings) ~= 'table' or #ratings > 100 then
        return { success = false, error = 'Invalid ratings' }
    end
    for key in pairs(ratings) do
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > #ratings then
            return { success = false, error = 'Invalid rating list' }
        end
    end
    for _, ratingRow in ipairs(ratings) do
        if type(ratingRow) ~= 'table' then return { success = false, error = 'Invalid rating entry' } end
        local competencyId, rating = tonumber(ratingRow.competency_id), tonumber(ratingRow.rating)
        if not competencyId or competencyId ~= competencyId or competencyId == math.huge
            or competencyId <= 0 or competencyId % 1 ~= 0
            or not rating or rating ~= rating or rating == math.huge
            or rating < 1 or rating > 5 or rating % 1 ~= 0
            or (ratingRow.notes ~= nil and (type(ratingRow.notes) ~= 'string' or #ratingRow.notes > 20000)) then
            return { success = false, error = 'Invalid rating entry' }
        end
    end
    local profile = MySQL.single.await('SELECT fullname FROM mdt_profiles WHERE citizenid = ?', { citizenId })
    local authorName = profile and type(profile.fullname) == 'string'
        and profile.fullname:find('%S') and profile.fullname or 'Unknown'
    if not CheckAuth(src) or not CheckPermission(src, 'fto_manage')
        or ps.getIdentifier(src) ~= citizenId or not canAccessFTORecord(src, assignmentId)
        or ps.getJobName(src) == nil then
        return { success = false, error = 'Authorization changed' }
    end
    local dorId = MySQL.insert.await([[
        INSERT INTO mdt_fto_dors (assignment_id, phase_id, author_citizenid, author_name, shift_date, overall_rating, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { assignmentId, phaseId, citizenId, authorName,
        data.shift_date or os.date('%Y-%m-%d'), overallRating, data.notes })
    if not dorId or dorId <= 0 then return { success = false, error = 'Failed to create DOR' } end
    for _, ratingRow in ipairs(ratings) do
        if not CheckAuth(src) or not CheckPermission(src, 'fto_manage')
            or ps.getIdentifier(src) ~= citizenId or not canAccessFTORecord(src, assignmentId) then
            return { success = false, error = 'Authorization changed while saving ratings', id = dorId }
        end
        local saved = MySQL.insert.await([[
            INSERT INTO mdt_fto_dor_ratings (dor_id, competency_id, rating, notes)
            VALUES (?, ?, ?, ?)
        ]], { dorId, tonumber(ratingRow.competency_id), tonumber(ratingRow.rating), ratingRow.notes })
        if not saved or saved <= 0 then
            return { success = false, error = 'DOR created but rating could not be saved', id = dorId }
        end
    end
    return { success = true, id = dorId }
end)

ps.registerCallback(resourceName .. ':server:deleteFTODor', function(source, dorId)
    local src = source
    if not CheckAuth(src) or not CheckPermission(src, 'fto_manage') then
        return { success = false, error = 'Unauthorized' }
    end
    dorId = tonumber(dorId)
    if not dorId or dorId ~= dorId or dorId == math.huge or dorId <= 0 or dorId % 1 ~= 0 then
        return { success = false, error = 'Invalid DOR ID' }
    end
    local owner = MySQL.single.await('SELECT assignment_id FROM mdt_fto_dors WHERE id = ?', { dorId })
    if not owner or not owner.assignment_id or not canAccessFTORecord(src, owner.assignment_id) then
        return { success = false, error = 'Unauthorized' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'fto_manage')
        or not canAccessFTORecord(src, owner.assignment_id) then
        return { success = false, error = 'Authorization changed' }
    end
    local deleted = MySQL.update.await('DELETE FROM mdt_fto_dors WHERE id = ? AND assignment_id = ?', { dorId, owner.assignment_id })
    if not deleted or deleted < 1 then return { success = false, error = 'DOR was not deleted' } end
    return { success = true }
end)
