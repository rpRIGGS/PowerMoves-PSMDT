local function getRadioChannel(playerSource)
    if not playerSource then return 0 end
    local channel = 0
    pcall(function()
        channel = Player(playerSource).state.radioChannel or 0
    end)
    return tonumber(channel) or 0
end

local function getCertifications(citizenid)
    EnsureProfileExists(citizenid)

    local profile = MySQL.single.await('SELECT certifications FROM mdt_profiles WHERE citizenid = ?', { citizenid })
    if not profile then
        return {}
    end

    if profile.certifications and profile.certifications ~= '' then
        local ok, decoded = pcall(json.decode, profile.certifications)
        if ok and type(decoded) == 'table' then
            return decoded
        end
    end

    return {}
end

-- Resolve a human-facing department label. Prefers the live job's label (online
-- players), falls back to the shared job config's label (offline / DB rows), and
-- finally the raw job name. Avoids showing the internal id like "police" as DEPT.
local function deptLabel(jobName, jobObj)
    if jobObj and jobObj.label and jobObj.label ~= '' then return jobObj.label end
    if jobName and ps.getSharedJobData then
        local shared = ps.getSharedJobData(jobName)
        if shared and shared.label and shared.label ~= '' then return shared.label end
    end
    return jobName
end

local function buildRosterFromQbx(jobList, matchFn, defaultDept)
    local rosterList = {}
    local activeUnits = {}
    local members = {}
    local qbx = exports['qbx_core']

    for _, jobName in ipairs(jobList) do
        local groupMembers = qbx:GetGroupMembers(jobName, 'job') or {}
        for _, member in ipairs(groupMembers) do
            if member.citizenid then
                members[member.citizenid] = true
            end
        end
    end

    for _, player in ipairs(qbx:GetQBPlayers() or {}) do
        local data = player.PlayerData or nil
        if data and data.job then
            local job = data.job
            if matchFn(job.name, job.type) then
                members[data.citizenid] = true
            end
        end
    end

    for _, row in ipairs(MySQL.query.await('SELECT citizenid, job FROM players', {}) or {}) do
        local job = row.job and json.decode(row.job) or {}
        if matchFn(job.name, job.type) then
            members[row.citizenid] = true
        end
    end

    for citizenid, _ in pairs(members) do
        local onlinePlayer = qbx:GetPlayerByCitizenId(citizenid)
        local player = onlinePlayer or qbx:GetOfflinePlayer(citizenid)
        if player and player.PlayerData then
            local data = player.PlayerData
            local job = data.job or {}
            local callsign = data.metadata and data.metadata.callsign or 'N/A'
            local fullname = data.charinfo and (data.charinfo.firstname .. ' ' .. data.charinfo.lastname) or 'Unknown'
            local rank = job.grade and job.grade.name or 'Officer'
            local department = job.name or defaultDept
            local departmentLabel = deptLabel(job.name, job) or department
            local certifications = getCertifications(citizenid)

            local onlineSrc = onlinePlayer and (onlinePlayer.PlayerData and onlinePlayer.PlayerData.source or onlinePlayer.source) or nil
            rosterList[#rosterList + 1] = {
                id = #rosterList + 1,
                citizenid = citizenid,
                callsign = callsign,
                firstName = data.charinfo and data.charinfo.firstname or 'N/A',
                lastName = data.charinfo and data.charinfo.lastname or 'N/A',
                rank = rank,
                department = department,
                departmentLabel = departmentLabel,
                status = (onlinePlayer and job.onduty) and 'On Duty' or 'Off Duty',
                certifications = certifications,
                badgeNumber = callsign,
                radioChannel = getRadioChannel(onlineSrc)
            }

            if rosterList[#rosterList].status == 'On Duty' then
                activeUnits[#activeUnits + 1] = {
                    id = rosterList[#rosterList].id,
                    badgeNumber = rosterList[#rosterList].badgeNumber,
                    callsign = rosterList[#rosterList].callsign,
                    firstName = rosterList[#rosterList].firstName,
                    lastName = rosterList[#rosterList].lastName,
                }
            end
        end
    end

    return {
        roster = rosterList,
        activeUnits = activeUnits
    }
end

local function checkDuty(citizenid, matchFn)
    matchFn = matchFn or IsPoliceJob
    local player = ps.getPlayerByIdentifier(citizenid)
    if not player then return 'Off Duty' end

    local src = player.source or (player.PlayerData and player.PlayerData.source)
    if not src then return 'Off Duty' end

    if matchFn(ps.getJobName(src), ps.getJobType(src)) and ps.getJobDuty(src) then
        return 'On Duty'
    end
    return 'Off Duty'
end

ps.registerCallback('ps-mdt:server:getRosterList', function(source)
    if not CheckAuth(source) then return { roster = {}, activeUnits = {} } end
    -- Scope the roster to the caller's domain: EMS sees EMS, police sees police.
    local domain = GetMdtDomain(source)
    local jobList, matchFn, defaultDept, scopeJobType
    if domain == 'ems' then
        jobList = (Config and Config.MedicalJobs) or { 'ambulance' }
        matchFn = IsEmsJob
        defaultDept = (jobList[1]) or 'ambulance'
        scopeJobType = Config and Config.MedicalJobType and tostring(Config.MedicalJobType) or nil
    else
        jobList = (Config and Config.PoliceJobs) or { 'police' }
        matchFn = IsPoliceJob
        defaultDept = 'police'
        scopeJobType = Config and Config.PoliceJobType and tostring(Config.PoliceJobType) or nil
    end

    if GetResourceState('qbx_core') == 'started' and exports['qbx_core'] then
        return buildRosterFromQbx(jobList, matchFn, defaultDept)
    end

    local rosterList = {}
    local activeUnits = {}
    local jobLookup = {}
    for _, jobName in ipairs(jobList) do
        jobLookup[tostring(jobName)] = true
    end
    local jobType = scopeJobType

    local employees = {}
    if GetResourceState('ps-multijob') == 'started' and exports['ps-multijob'] then
        for _, jobName in ipairs(jobList) do
            local list = exports['ps-multijob']:getEmployees(jobName) or {}
            for _, employee in pairs(list) do
                if employee and employee.citizenid then
                    employees[employee.citizenid] = employee
                end
            end
        end
    end

    for _, citizen in pairs(MySQL.query.await('SELECT citizenid, charinfo, job, metadata FROM players', {}) or {}) do
        local citizenid = citizen.citizenid
        local charinfo = citizen.charinfo and json.decode(citizen.charinfo) or {}
        local job = citizen.job and json.decode(citizen.job) or {}
        local metadata = citizen.metadata and json.decode(citizen.metadata) or {}
        local jobName = job.name and tostring(job.name) or nil
        local inDomain = (jobName and jobLookup[jobName]) or (job.type and jobType and tostring(job.type) == jobType)
        if inDomain then
            local employee = employees[citizenid] or {}
            local callsign = metadata.callsign or 'N/A'
            local firstName = charinfo.firstname or 'N/A'
            local lastName = charinfo.lastname or 'N/A'
            local rank = job.grade and job.grade.name or employee.grade and ps.getSharedJobGradeData(jobName or defaultDept, employee.grade, 'name') or 'Officer'
            local status = checkDuty(citizenid, matchFn)
            local onlinePlayer = ps.getPlayerByIdentifier(citizenid)
            local onlineSrc = onlinePlayer and (onlinePlayer.source or (onlinePlayer.PlayerData and onlinePlayer.PlayerData.source)) or nil
            rosterList[#rosterList + 1] = {
                id = #rosterList + 1,
                citizenid = citizenid,
                callsign = callsign,
                firstName = firstName,
                lastName = lastName,
                rank = rank,
                department = jobName or employee.job or defaultDept,
                departmentLabel = deptLabel(jobName, job) or jobName or employee.job or defaultDept,
                status = status,
                certifications = getCertifications(citizenid),
                badgeNumber = callsign,
                radioChannel = getRadioChannel(onlineSrc)
            }
            if status == 'On Duty' then
                activeUnits[#activeUnits + 1] = {
                    id = rosterList[#rosterList].id,
                    badgeNumber = rosterList[#rosterList].badgeNumber,
                    callsign = rosterList[#rosterList].callsign,
                    firstName = rosterList[#rosterList].firstName,
                    lastName = rosterList[#rosterList].lastName,
                }
            end
        end
    end
    return {
        roster = rosterList,
        activeUnits = activeUnits
    }
end)

-- Government personnel reuse the roster's framework data without loading
-- operational profiles, certifications, radio state or employment controls.
local function governmentRosterDenied(message)
    return { success = false, error = message, roster = {}, departments = {} }
end

local function governmentRosterAccess(source)
    if type(GetGovernmentRosterAccess) ~= 'function' then return nil end
    local ok, access = pcall(GetGovernmentRosterAccess, source)
    if not ok or type(access) ~= 'table' then return nil end
    local governmentJobs = (Config.MdtAccess or {}).GovernmentJobs or {}
    if type(access.citizenid) ~= 'string' or access.citizenid == ''
        or type(access.agency) ~= 'string' or not governmentJobs[access.agency]
        or governmentJobs[access.agency] ~= access.jurisdiction
        or type(access.allowedJobs) ~= 'table' then return nil end
    local snapshot = {
        citizenid = access.citizenid, agency = access.agency,
        grade = access.grade, jurisdiction = access.jurisdiction,
        hasOversight = access.hasOversight == true, allowedJobs = {},
    }
    local seen = {}
    for _, jobName in ipairs(access.allowedJobs) do
        if type(jobName) ~= 'string' or not governmentJobs[jobName]
            or (jobName ~= access.agency and (access.agency ~= 'sagov' or not snapshot.hasOversight)) then return nil end
        if not seen[jobName] then
            seen[jobName] = true
            snapshot.allowedJobs[#snapshot.allowedJobs + 1] = jobName
        end
    end
    if not seen[access.agency] then return nil end
    table.sort(snapshot.allowedJobs)
    return snapshot
end

local function sameGovernmentRosterAccess(initial, current, department)
    if not current or initial.citizenid ~= current.citizenid or initial.agency ~= current.agency
        or initial.grade ~= current.grade or initial.jurisdiction ~= current.jurisdiction
        or initial.hasOversight ~= current.hasOversight or #initial.allowedJobs ~= #current.allowedJobs then return false end
    local selectedAllowed = false
    for index, jobName in ipairs(initial.allowedJobs) do
        if current.allowedJobs[index] ~= jobName then return false end
        if jobName == department then selectedAllowed = true end
    end
    return selectedAllowed
end

local function governmentRosterJob(jobName)
    local job
    if type(ps.getSharedJobData) == 'function' then
        local ok, value = pcall(ps.getSharedJobData, jobName)
        if ok and type(value) == 'table' then job = value end
    end
    if not job and type(ps.getSharedJob) == 'function' then
        local ok, value = pcall(ps.getSharedJob, jobName)
        if ok and type(value) == 'table' then job = value end
    end
    if not job then
        local ok, value = pcall(function()
            local core = exports['qb-core']:GetCoreObject()
            return core and core.Shared and core.Shared.Jobs and core.Shared.Jobs[jobName]
        end)
        if ok and type(value) == 'table' then job = value end
    end
    if not job or type(job.grades) ~= 'table' then return nil end
    local grades, names = {}, {}
    for key, definition in pairs(job.grades) do
        if type(definition) == 'table' then
            local grade = tonumber(definition.level or definition.grade or definition.rank or definition.value or definition.id or key)
            local name = definition.name or definition.label or definition.title
            if grade and grade >= 0 and grade % 1 == 0 and type(name) == 'string' and name ~= '' and not names[grade] then
                names[grade] = name
                grades[#grades + 1] = { grade = grade, name = name }
            end
        end
    end
    if #grades == 0 then return nil end
    table.sort(grades, function(a, b) return a.grade < b.grade end)
    return { label = type(job.label) == 'string' and job.label ~= '' and job.label or jobName, grades = grades, names = names }
end

local function governmentRosterObject(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' then return {} end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or {}
end

ps.registerCallback(tostring(GetCurrentResourceName()) .. ':server:getGovernmentRoster', function(source, payload)
    if payload ~= nil and type(payload) ~= 'table' then return governmentRosterDenied('Invalid roster request') end
    payload = payload or {}
    if payload.department ~= nil and type(payload.department) ~= 'string' then
        return governmentRosterDenied('Invalid department')
    end
    local access = governmentRosterAccess(source)
    if not access then return governmentRosterDenied('Government personnel access denied') end
    local selectedDepartment = payload.department or access.agency
    if not sameGovernmentRosterAccess(access, access, selectedDepartment) then
        return governmentRosterDenied('Department access denied')
    end

    local policy = Config.MdtAccess or {}
    local departments, selectedJob = {}, nil
    for _, jobName in ipairs(access.allowedJobs) do
        local job = governmentRosterJob(jobName)
        if not job then return governmentRosterDenied('Government department configuration unavailable') end
        if jobName == access.agency and not job.names[access.grade] then
            return governmentRosterDenied('Government position configuration unavailable')
        end
        local jurisdiction = policy.GovernmentJobs[jobName]
        local details = (policy.GovernmentJurisdictions or {})[jurisdiction] or {}
        departments[#departments + 1] = {
            job = jobName, label = job.label, jurisdiction = jurisdiction,
            jurisdictionLabel = type(details.label) == 'string' and details.label or jurisdiction,
            parentJurisdiction = type(details.parent) == 'string' and details.parent or nil,
            grades = job.grades,
        }
        if jobName == selectedDepartment then selectedJob = job end
    end
    if not sameGovernmentRosterAccess(access, governmentRosterAccess(source), selectedDepartment) then
        return governmentRosterDenied('Government personnel access changed; refresh the roster')
    end

    local ok, rows = pcall(MySQL.query.await, [[
        SELECT citizenid, charinfo, job FROM players
        WHERE CASE WHEN JSON_VALID(job)
            THEN JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) ELSE NULL END = ?
    ]], { selectedDepartment })
    if not ok or type(rows) ~= 'table' then return governmentRosterDenied('Unable to load government personnel') end

    local rosterByCitizen, onlineCitizens = {}, {}
    local function addEmployee(citizenid, charinfo, job)
        if type(citizenid) ~= 'string' or citizenid == '' or job.name ~= selectedDepartment then return end
        local value = job.grade
        local grade = tonumber(type(value) == 'table'
            and (value.level or value.grade or value.rank or value.value or value.id) or value)
        local rank = grade and selectedJob.names[grade] or nil
        rosterByCitizen[citizenid] = {
            citizenid = citizenid,
            firstName = type(charinfo.firstname) == 'string' and charinfo.firstname or '',
            lastName = type(charinfo.lastname) == 'string' and charinfo.lastname or '',
            rank = rank or '', grade = rank and grade or nil,
            department = selectedDepartment, departmentLabel = selectedJob.label,
            jurisdiction = policy.GovernmentJobs[selectedDepartment],
        }
    end
    local function addOnlineEmployee(citizenid, player)
        rosterByCitizen[citizenid] = nil
        local data = type(player) == 'table' and (player.PlayerData or player) or nil
        if type(data) ~= 'table' then return end
        if data.citizenid ~= nil and data.citizenid ~= citizenid then return end
        addEmployee(citizenid, governmentRosterObject(data.charinfo), governmentRosterObject(data.job))
    end

    -- Live employment overrides saved jobs, including transfers out of the
    -- selected department. The separate online pass also adds transfers in.
    local onlineOk, onlineSources = pcall(GetPlayers)
    if not onlineOk or type(onlineSources) ~= 'table' then return governmentRosterDenied('Unable to load government personnel') end
    for _, playerSource in pairs(onlineSources) do
        local identifierOk, citizenid = pcall(ps.getIdentifier, tonumber(playerSource) or playerSource)
        if identifierOk and type(citizenid) == 'string' and citizenid ~= '' then
            onlineCitizens[citizenid] = true
            local playerOk, player = pcall(ps.getPlayerByIdentifier, citizenid)
            if playerOk then addOnlineEmployee(citizenid, player) end
        end
    end
    for _, row in pairs(rows) do
        local citizenid = type(row) == 'table' and row.citizenid or nil
        if type(citizenid) == 'string' and citizenid ~= '' and not onlineCitizens[citizenid] then
            local playerOk, player = pcall(ps.getPlayerByIdentifier, citizenid)
            if playerOk then
                if player then
                    addOnlineEmployee(citizenid, player)
                else
                    addEmployee(citizenid, governmentRosterObject(row.charinfo), governmentRosterObject(row.job))
                end
            end
        end
    end
    if not sameGovernmentRosterAccess(access, governmentRosterAccess(source), selectedDepartment) then
        return governmentRosterDenied('Government personnel access changed; refresh the roster')
    end
    local roster = {}
    for _, employee in pairs(rosterByCitizen) do roster[#roster + 1] = employee end
    table.sort(roster, function(a, b)
        local aName, bName = (a.lastName .. '\0' .. a.firstName):lower(), (b.lastName .. '\0' .. b.firstName):lower()
        return aName == bName and a.citizenid < b.citizenid or aName < bName
    end)
    return {
        success = true, roster = roster, departments = departments,
        selectedDepartment = selectedDepartment, hasOversight = access.hasOversight,
        canManagePersonnel = false,
    }
end)

-- Get available officer tags/certifications (filtered by job type)
ps.registerCallback('ps-mdt:server:getOfficerTags', function(source)
    local src = source
    if not CheckAuth(src) then return {} end

    local jobType = ps.getJobType(src)
    local rows
    if jobType and (jobType == 'leo' or jobType == 'ems') then
        rows = MySQL.query.await([[
            SELECT id, name, color, description FROM mdt_tags
            WHERE type = 'officer'
              AND (job_type = ? OR job_type = 'all' OR job_type IS NULL)
            ORDER BY name ASC
        ]], { jobType })
    else
        rows = MySQL.query.await([[
            SELECT id, name, color, description FROM mdt_tags
            WHERE type = 'officer'
            ORDER BY name ASC
        ]])
    end
    return rows or {}
end)

-- Update officer certifications
ps.registerCallback('ps-mdt:server:updateOfficerCertifications', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'roster_manage_certifications') then
        return { success = false, message = 'No permission to manage certifications' }
    end

    payload = payload or {}
    local citizenid = payload.citizenid
    local certifications = payload.certifications

    if not citizenid or type(certifications) ~= 'table' then
        return { success = false, message = 'Invalid payload' }
    end

    if not CanManageMdtPersonnel(src, citizenid) then
        return { success = false, message = 'Personnel administration is limited to your department' }
    end

    EnsureProfileExists(citizenid)

    local encoded = json.encode(certifications)
    MySQL.update.await('UPDATE mdt_profiles SET certifications = ? WHERE citizenid = ?', { encoded, citizenid })

    return { success = true }
end)

-- Get job grades for a specific department
ps.registerCallback('ps-mdt:server:getJobGrades', function(source, payload)
    local src = source
    if not CheckAuth(src) then return {} end
    if not CheckPermission(src, 'roster_manage_officers') then return {} end

    payload = payload or {}
    local jobName = payload.job or ps.getJobName(src)
    if jobName ~= ps.getJobName(src) then return {} end

    local jobData = ps.getSharedJob(jobName)
    if not jobData or not jobData.grades then return {} end

    local grades = {}
    for gradeKey, gradeValue in pairs(jobData.grades) do
        grades[#grades + 1] = {
            grade = tonumber(gradeKey) or 0,
            name = gradeValue.name or ('Grade ' .. gradeKey),
            isBoss = gradeValue.isboss == true or gradeValue.isBoss == true or gradeValue.boss == true,
        }
    end

    table.sort(grades, function(a, b) return a.grade < b.grade end)
    return grades
end)

-- Promote/demote an officer (change their job grade)
-- Set a player's job/grade directly through the active framework.
-- The ps bridge's setJob path depends on a setPlayerData export that isn't
-- present on this server, so promote/terminate calls silently failed. We talk to
-- QBX first (the roster already uses qbx_core), then fall back to QBCore.
---@return boolean ok
local function setOfficerJob(targetSrc, jobName, grade)
    grade = tonumber(grade) or 0

    if GetResourceState('qbx_core') == 'started' and exports['qbx_core'] then
        local ok, res = pcall(function()
            return exports['qbx_core']:SetJob(targetSrc, jobName, grade)
        end)
        -- QBX returns true on success (and may return nil on older builds).
        if ok and res ~= false then return true end
    end

    local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and QBCore and QBCore.Functions then
        local Player = QBCore.Functions.GetPlayer(targetSrc)
        if Player and Player.Functions and Player.Functions.SetJob then
            local sok = pcall(function() return Player.Functions.SetJob(jobName, grade) end)
            if sok then return true end
        end
    end

    return false
end

ps.registerCallback('ps-mdt:server:promoteOfficer', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'roster_manage_officers') then
        return { success = false, message = 'No permission to manage officers' }
    end

    payload = payload or {}
    local citizenid = payload.citizenid
    local jobName = payload.job
    local newGrade = tonumber(payload.grade)

    if not citizenid or not jobName or not newGrade then
        return { success = false, message = 'Missing required fields' }
    end

    if not CanManageMdtPersonnel(src, citizenid, jobName) then
        return { success = false, message = 'Personnel administration is limited to your department' }
    end

    -- Validate the grade exists
    local gradeData = ps.getSharedJobGrade(jobName, newGrade)
    if not gradeData then
        return { success = false, message = 'Invalid grade for this job' }
    end

    -- Find the target player (must be online for QBCore SetJob)
    local targetPlayer = ps.getPlayerByIdentifier(citizenid)
    if not targetPlayer then
        return { success = false, message = 'Officer must be online to change rank' }
    end

    local targetSrc = targetPlayer.source or (targetPlayer.PlayerData and targetPlayer.PlayerData.source)
    if not targetSrc then
        return { success = false, message = 'Could not resolve officer source' }
    end

    -- Don't allow changing your own rank
    if targetSrc == src then
        return { success = false, message = 'You cannot change your own rank' }
    end

    if not setOfficerJob(targetSrc, jobName, newGrade) then
        return { success = false, message = 'Failed to update rank (framework error)' }
    end

    local gradeName = gradeData.name or ('Grade ' .. newGrade)

    if ps.auditLog then
        ps.auditLog(src, 'officer_promoted', 'officers', citizenid, {
            job = jobName,
            grade = newGrade,
            gradeName = gradeName,
        })
    end

    return { success = true, message = 'Officer rank updated to ' .. gradeName }
end)

-- Fire an officer (set their job to unemployed)
ps.registerCallback('ps-mdt:server:fireOfficer', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'roster_manage_officers') then
        return { success = false, message = 'No permission to manage officers' }
    end

    payload = payload or {}
    local citizenid = payload.citizenid

    if not citizenid then
        return { success = false, message = 'Missing citizen ID' }
    end

    if not CanManageMdtPersonnel(src, citizenid) then
        return { success = false, message = 'Personnel administration is limited to your department' }
    end

    local targetPlayer = ps.getPlayerByIdentifier(citizenid)
    if not targetPlayer then
        return { success = false, message = 'Officer must be online to be terminated' }
    end

    local targetSrc = targetPlayer.source or (targetPlayer.PlayerData and targetPlayer.PlayerData.source)
    if not targetSrc then
        return { success = false, message = 'Could not resolve officer source' }
    end

    -- Don't allow firing yourself
    if targetSrc == src then
        return { success = false, message = 'You cannot fire yourself' }
    end

    if not setOfficerJob(targetSrc, 'unemployed', 0) then
        return { success = false, message = 'Failed to terminate officer (framework error)' }
    end

    -- Optional full personal-data wipe (boss panel toggle). Runs after the job
    -- change so the person is already off the roster; only touches their own
    -- footprint, never investigative/shared data. See personnel_cleanup.lua.
    local cleanup = nil
    if payload.deleteData and CleanupPersonnelData then
        cleanup = CleanupPersonnelData(citizenid)
    end

    if ps.auditLog then
        ps.auditLog(src, 'officer_fired', 'officers', citizenid, {
            dataDeleted = payload.deleteData and true or false,
            cleanupSteps = cleanup and cleanup.steps or nil,
        })
    end

    local message = 'Officer has been terminated'
    if payload.deleteData then
        if cleanup and cleanup.ok then
            message = 'Officer terminated and MDT data removed'
        elseif cleanup then
            message = 'Officer terminated, but data cleanup failed: ' .. tostring(cleanup.error)
        end
    end

    return { success = true, message = message, cleanup = cleanup }
end)

-- Update officer callsign (wrapper around existing setCallsign for NUI)
ps.registerCallback('ps-mdt:server:updateOfficerCallsign', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'roster_manage_officers') then
        return { success = false, message = 'No permission to manage officers' }
    end

    payload = payload or {}
    local citizenid = payload.citizenid
    local newCallsign = payload.callsign

    if not citizenid or not newCallsign or newCallsign == '' then
        return { success = false, message = 'Missing citizen ID or callsign' }
    end

    if not CanManageMdtPersonnel(src, citizenid) then
        return { success = false, message = 'Personnel administration is limited to your department' }
    end

    -- Use the existing setCallsign callback logic
    local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if not ok or not QBCore then
        return { success = false, message = 'Core framework not available' }
    end

    local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if not Player then
        return { success = false, message = 'Officer must be online to update callsign' }
    end

    Player.Functions.SetMetaData('callsign', newCallsign)

    local resourceName = GetCurrentResourceName()
    TriggerClientEvent(resourceName .. ':client:updateCallsign', Player.PlayerData.source, newCallsign)

    MySQL.update.await('UPDATE mdt_profiles SET callsign = ? WHERE citizenid = ?', { newCallsign, citizenid })

    if ps.auditLog then
        ps.auditLog(src, 'callsign_changed', 'officers', citizenid, { callsign = newCallsign })
    end

    return { success = true, message = 'Callsign updated to ' .. newCallsign }
end)
