local function safeRosterDecode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' then return {} end
    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'table' then return decoded end
    return {}
end

local function getRadioChannel(playerSource)
    if not playerSource then return 0 end
    local channel = 0
    pcall(function()
        channel = Player(playerSource).state.radioChannel or 0
    end)
    channel = tonumber(channel)
    if not channel or channel ~= channel or channel == math.huge or channel < 0 then return 0 end
    return channel
end

local function getCertifications(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return {} end
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
    if jobObj and type(jobObj.label) == 'string' and jobObj.label ~= '' then return jobObj.label end
    if jobName and ps.getSharedJobData then
        local shared = ps.getSharedJobData(jobName)
        if shared and type(shared.label) == 'string' and shared.label ~= '' then return shared.label end
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
        if type(groupMembers) ~= 'table' then groupMembers = {} end
        for _, member in ipairs(groupMembers) do
            if type(member.citizenid) == 'string' and member.citizenid ~= '' then
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
        local job = safeRosterDecode(row.job)
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
            -- A multijob/Qbox group membership is not proof that the employee
            -- is currently assigned to that department. Do not return another
            -- employer's employee just because they retain secondary membership.
            if matchFn(job.name, job.type) then
            local callsign = data.metadata and data.metadata.callsign or 'N/A'
            local fullname = data.charinfo and (data.charinfo.firstname .. ' ' .. data.charinfo.lastname) or 'Unknown'
            local rank = job.grade and job.grade.name or (job.name and job.grade and ps.getSharedJobGradeData(job.name, job.grade.level or job.grade.grade or job.grade, 'name')) or 'Unknown Rank'
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
            end -- current employing job matches this roster
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
    -- Interface-specific roster selection: DOJ is not a police agency.
    -- Fire and hospitals still use the shared legacy responder domain.
    local access = GetMdtAccess(source)
    if not access or not access.authorized then return { roster = {}, activeUnits = {} } end
    local jobList, matchFn, defaultDept, scopeJobType
    if access.jobType == 'doj' and access.agency ~= (Config.MdtAccess and Config.MdtAccess.AttorneyGeneral and Config.MdtAccess.AttorneyGeneral.job) then
        -- DOJ's court interface includes different employers (SADOJ and law
        -- firms). A shared service interface is not roster-wide jurisdiction.
        local employer = access.agency
        if type(employer) ~= 'string' or employer == '' then
            return { roster = {}, activeUnits = {} }
        end
        jobList = { employer }
        matchFn = function(jobName, _) return jobName == employer end
        defaultDept = employer
        scopeJobType = nil
    elseif access.interfaceId == 'safr' or access.interfaceId == 'sams' then
        -- Responder data shares a legacy domain, not a common employer.
        -- Avoid exposing other departments' staff through the roster.
        local employer = access.agency
        local choices = access.interfaceId == 'safr' and Config.FireJobs or Config.MedicalJobs
        local valid = false
        for _, candidate in ipairs(choices or {}) do
            if candidate == employer then valid = true break end
        end
        if not valid then return { roster = {}, activeUnits = {} } end
        local statewide = type(CanViewStatewideServiceRoster) == 'function'
            and CanViewStatewideServiceRoster(source, access.interfaceId) == true
        if statewide then
            local policy = (((Config.MdtAccess or {}).ServiceOversight or {})[access.interfaceId]) or {}
            jobList = { employer }
            for _, department in ipairs(policy.DepartmentJobs or {}) do
                local eligible = false
                for _, candidate in ipairs(choices or {}) do
                    if candidate == department then eligible = true break end
                end
                if eligible and department ~= employer then
                    jobList[#jobList + 1] = department
                end
            end
            local permitted = {}
            for _, jobName in ipairs(jobList) do permitted[jobName] = true end
            matchFn = function(name, _) return permitted[name] == true end
        else
            jobList = { employer }
            matchFn = function(name, _) return name == employer end
        end
        defaultDept = employer
        scopeJobType = nil
    else
        -- Default to the actual employing law-enforcement agency.
        -- Statewide authorized investigators can view the family roster;
        -- ordinary departmental bosses cannot inherit that oversight.
        local employer = access.agency
        local eligible = false
        for _, configured in ipairs((Config and Config.PoliceJobs) or {}) do
            if configured == employer then eligible = true break end
        end
        if not eligible then return { roster = {}, activeUnits = {} } end
        local statewide = type(CanViewStatewideLeoRoster) == 'function'
            and CanViewStatewideLeoRoster(source) == true
        if statewide then
            jobList = (Config and Config.PoliceJobs) or {}
            -- Statewide visibility is limited to explicitly configured MDT
            -- employers; unrelated jobs sharing the leo type are excluded.
            local permitted = {}
            for _, jobName in ipairs(jobList) do permitted[jobName] = true end
            matchFn = function(name, _) return permitted[name] == true end
            scopeJobType = nil
        else
            jobList = { employer }
            matchFn = function(name, _) return name == employer end
            scopeJobType = nil
        end
        defaultDept = employer
    end

    -- PowerMoves uses QBCore. Do not switch the entire roster to QBX
    -- merely because an unrelated QBX resource happens to be started.

    local rosterList = {}
    local activeUnits = {}
    local jobLookup = {}
    for _, jobName in ipairs(jobList) do
        jobLookup[tostring(jobName)] = true
    end
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
        local charinfo = safeRosterDecode(citizen.charinfo)
        local job = safeRosterDecode(citizen.job)
        local metadata = safeRosterDecode(citizen.metadata)
        -- The live QBCore job wins over a stale saved players.job value.
        local onlinePlayer = ps.getPlayerByIdentifier(citizenid)
        local liveData = onlinePlayer and onlinePlayer.PlayerData
        if type(liveData) == 'table' and type(liveData.job) == 'table' then
            job = liveData.job
            if type(liveData.metadata) == 'table' then metadata = liveData.metadata end
            if type(liveData.charinfo) == 'table' then charinfo = liveData.charinfo end
        end
        local jobName = job.name and tostring(job.name) or nil
        local inDomain = jobName ~= nil and jobLookup[jobName] == true
        if inDomain then
            local employee = employees[citizenid] or {}
            local callsign = metadata.callsign or 'N/A'
            local firstName = charinfo.firstname or 'N/A'
            local lastName = charinfo.lastname or 'N/A'
            local grade = job.grade
            local gradeLevel = type(grade) == 'table' and (grade.level or grade.grade) or grade
            local rank = (type(grade) == 'table' and grade.name)
                or (gradeLevel ~= nil and ps.getSharedJobGradeData(jobName, gradeLevel, 'name'))
                or (employee.grade and ps.getSharedJobGradeData(jobName, employee.grade, 'name'))
                or 'Unknown Rank'
            local status = checkDuty(citizenid, matchFn)
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
    local grades, names, bossGrades = {}, {}, {}
    for key, definition in pairs(job.grades) do
        if type(definition) == 'table' then
            local grade = tonumber(definition.level or definition.grade or definition.rank or definition.value or definition.id or key)
            local name = definition.name or definition.label or definition.title
            if grade and grade >= 0 and grade % 1 == 0 and type(name) == 'string' and name ~= '' and not names[grade] then
                names[grade] = name
                bossGrades[grade] = definition.isboss == true
                grades[#grades + 1] = { grade = grade, name = name }
            end
        end
    end
    if #grades == 0 then return nil end
    table.sort(grades, function(a, b) return a.grade < b.grade end)
    return { label = type(job.label) == 'string' and job.label ~= '' and job.label or jobName, grades = grades, names = names, bossGrades = bossGrades }
end

local function governmentGrade(value)
    if type(value) == 'table' then
        value = value.level or value.grade or value.rank or value.value or value.id
    end
    if type(value) ~= 'number' and type(value) ~= 'string' then return nil end
    local grade = tonumber(value)
    if not grade or grade < 0 or grade >= math.huge or grade % 1 ~= 0 then return nil end
    return grade
end

-- This only advertises controls. Employment callbacks independently verify
-- current QBCore players and shared boss flags immediately before SetJob.
local function governmentRosterCanManage(source, access, selectedDepartment, jobDefinition)
    if selectedDepartment ~= access.agency or not jobDefinition then return false end
    local ok, allowed = pcall(function()
        local job = ps.getJobData(source)
        return type(job) == 'table' and job.name == access.agency
            and governmentGrade(job.grade) == access.grade
            and job.isboss == true and jobDefinition.bossGrades[access.grade] == true
            and ps.getIdentifier(source) == access.citizenid
            and (Config.OnlyShowOnDuty ~= true or job.onduty == true)
    end)
    return ok and allowed == true
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
        canManagePersonnel = governmentRosterCanManage(source, access, selectedDepartment, selectedJob),
    }
end)

-- Government employment uses the same primary QBCore job as existing MDT
-- employment actions. It never enters operational authorization or cleanup.
local governmentEmploymentLocks = {}

local function governmentEmploymentDenied(message)
    return { success = false, error = message }
end

local function governmentCore()
    local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if not ok or type(core) ~= 'table' or type(core.Functions) ~= 'table'
        or type(core.Functions.GetPlayer) ~= 'function' or type(core.Shared) ~= 'table'
        or type(core.Shared.Jobs) ~= 'table' then return nil end
    return core
end

local function governmentCorePlayer(core, source)
    local ok, player = pcall(core.Functions.GetPlayer, source)
    local data = ok and type(player) == 'table' and player.PlayerData or nil
    if type(data) ~= 'table' or type(data.job) ~= 'table'
        or type(data.citizenid) ~= 'string' or data.citizenid == ''
        or tonumber(data.source) ~= tonumber(source) then return nil end
    return player
end

local function governmentCoreGrade(core, jobName, grade)
    local job = core.Shared.Jobs[jobName]
    local definition = type(job) == 'table' and type(job.grades) == 'table'
        and (job.grades[tostring(grade)] or job.grades[grade]) or nil
    return type(definition) == 'table' and definition or nil
end

local function governmentManager(core, source, access, payload, expected)
    if not access then return nil end
    if payload.department ~= nil and payload.department ~= access.agency then return nil end
    if payload.job ~= nil and payload.job ~= access.agency then return nil end
    local player = governmentCorePlayer(core, source)
    local data = player and player.PlayerData
    local job = data and data.job
    local grade = job and governmentGrade(job.grade)
    local sharedGrade = grade and governmentCoreGrade(core, access.agency, grade)
    if not data or data.citizenid ~= access.citizenid or job.name ~= access.agency
        or grade ~= access.grade or job.isboss ~= true
        or not sharedGrade or sharedGrade.isboss ~= true
        or (Config.OnlyShowOnDuty == true and job.onduty ~= true) then return nil end
    local manager = {
        citizenid = data.citizenid, agency = job.name, grade = grade,
        onDuty = job.onduty == true, player = player,
    }
    if expected and (manager.citizenid ~= expected.citizenid or manager.agency ~= expected.agency
        or manager.grade ~= expected.grade or manager.onDuty ~= expected.onDuty) then return nil end
    return manager
end

local function governmentOnlineTarget(core, payload, hiring)
    if hiring then
        local serverId = (type(payload.serverId) == 'number' or type(payload.serverId) == 'string') and tonumber(payload.serverId) or nil
        if not serverId or serverId <= 0 or serverId >= math.huge or serverId % 1 ~= 0 then return nil end
        return governmentCorePlayer(core, serverId)
    end
    if type(payload.citizenid) ~= 'string' or payload.citizenid == ''
        or type(core.Functions.GetPlayerByCitizenId) ~= 'function' then return nil end
    local ok, found = pcall(core.Functions.GetPlayerByCitizenId, payload.citizenid)
    local data = ok and type(found) == 'table' and found.PlayerData or nil
    local source = type(data) == 'table' and tonumber(data.source) or nil
    local player = source and governmentCorePlayer(core, source) or nil
    if not player or player.PlayerData.citizenid ~= payload.citizenid then return nil end
    return player
end

local function governmentEligibleTarget(player, manager, payload, hiring, candidate)
    local data = player and player.PlayerData
    if not data or data.citizenid == manager.citizenid then return false end
    if not candidate and data.citizenid ~= payload.citizenid then return false end
    return data.job.name == (hiring and 'unemployed' or manager.agency)
end

local function governmentManagerRequest(source, payload)
    if type(payload) ~= 'table' then return nil, nil, nil, 'Invalid personnel request' end
    local access = governmentRosterAccess(source)
    if not access then return nil, nil, nil, 'Government personnel access denied' end
    local core = governmentCore()
    if not core then return nil, nil, nil, 'QBCore employment services unavailable' end
    local manager = governmentManager(core, source, access, payload)
    if not manager then return nil, nil, nil, 'Only a current department boss may manage its personnel' end
    return core, manager, access
end

ps.registerCallback(tostring(GetCurrentResourceName()) .. ':server:getGovernmentHireCandidate', function(source, payload)
    local core, manager, _, message = governmentManagerRequest(source, payload)
    if not core then return governmentEmploymentDenied(message) end
    local target = governmentOnlineTarget(core, payload, true)
    if not governmentEligibleTarget(target, manager, payload, true, true) then
        return governmentEmploymentDenied('Select an online unemployed player')
    end
    local citizenid = target.PlayerData.citizenid
    -- The permission lookup can yield. Re-resolve both actors afterwards;
    -- a server ID may have been reassigned to a different character.
    local access = governmentRosterAccess(source)
    manager = governmentManager(core, source, access, payload, manager)
    target = governmentOnlineTarget(core, payload, true)
    if not manager or not target or target.PlayerData.citizenid ~= citizenid
        or not governmentEligibleTarget(target, manager, payload, true, true) then
        return governmentEmploymentDenied('Personnel eligibility changed; refresh and try again')
    end
    local data = target.PlayerData
    local info = type(data.charinfo) == 'table' and data.charinfo or {}
    return {
        success = true,
        candidate = {
            citizenid = data.citizenid, serverId = tonumber(data.source),
            firstName = type(info.firstname) == 'string' and info.firstname or '',
            lastName = type(info.lastname) == 'string' and info.lastname or '',
        },
    }
end)

local function governmentEmploymentAction(source, payload, action)
    local core, manager, _, message = governmentManagerRequest(source, payload)
    if not core then return governmentEmploymentDenied(message) end
    local hiring = action == 'hire'
    if type(payload.citizenid) ~= 'string' or payload.citizenid == '' then
        return governmentEmploymentDenied('Missing employee identifier')
    end
    local grade = action == 'terminate' and 0 or governmentGrade(payload.grade)
    -- Unlike framework grade data, a requested grade must be a scalar.
    if action ~= 'terminate' and type(payload.grade) ~= 'number' and type(payload.grade) ~= 'string' then grade = nil end
    local destination = action == 'terminate' and 'unemployed' or manager.agency
    if grade == nil or not governmentCoreGrade(core, destination, grade) then
        return governmentEmploymentDenied('Invalid grade for this department')
    end
    local target = governmentOnlineTarget(core, payload, hiring)
    if not governmentEligibleTarget(target, manager, payload, hiring, false) then
        return governmentEmploymentDenied(hiring and 'Player must be online and unemployed' or 'Employee must be online and employed by your department')
    end
    local targetSource = tonumber(target.PlayerData.source)
    if governmentEmploymentLocks[payload.citizenid] then
        return governmentEmploymentDenied('Another employment action is in progress for this player')
    end
    governmentEmploymentLocks[payload.citizenid] = true
    local ok, result = pcall(function()
        -- Final authorization is after the last role read. Oversight is not a
        -- write grant: the manager's primary job always determines destination.
        local access = governmentRosterAccess(source)
        local currentManager = governmentManager(core, source, access, payload, manager)
        local currentTarget = governmentOnlineTarget(core, payload, hiring)
        if not currentManager or not currentTarget or tonumber(currentTarget.PlayerData.source) ~= targetSource
            or not governmentEligibleTarget(currentTarget, currentManager, payload, hiring, false)
            or not governmentCoreGrade(core, destination, grade) then
            return governmentEmploymentDenied('Personnel authority or employment changed; refresh and try again')
        end
        if type(currentTarget.Functions) ~= 'table' or type(currentTarget.Functions.SetJob) ~= 'function' then
            return governmentEmploymentDenied('Framework employment change unavailable')
        end
        local oldJob, oldGrade = currentTarget.PlayerData.job.name, governmentGrade(currentTarget.PlayerData.job.grade)
        local changed = currentTarget.Functions.SetJob(destination, grade)
        local updated = governmentCorePlayer(core, targetSource)
        if changed == false or not updated or updated.PlayerData.citizenid ~= payload.citizenid
            or updated.PlayerData.job.name ~= destination or governmentGrade(updated.PlayerData.job.grade) ~= grade then
            return governmentEmploymentDenied('Framework did not apply the employment change')
        end
        local saveWarning = false
        if type(updated.Functions) == 'table' and type(updated.Functions.Save) == 'function' then
            local saved, saveResult = pcall(updated.Functions.Save)
            saveWarning = not saved or saveResult == false
        end
        if ps.auditLog then
            pcall(ps.auditLog, source, 'government_employee_' .. action, 'government_personnel', payload.citizenid, {
                department = manager.agency, oldJob = oldJob, oldGrade = oldGrade,
                job = destination, grade = grade,
            })
        end
        local successMessage = action == 'hire' and 'Employee hired'
            or action == 'terminate' and 'Employment terminated' or 'Employee grade updated'
        if saveWarning then successMessage = successMessage .. '; immediate framework save could not be confirmed' end
        return { success = true, message = successMessage }
    end)
    governmentEmploymentLocks[payload.citizenid] = nil
    if not ok then return governmentEmploymentDenied('Framework employment change failed') end
    return result
end

ps.registerCallback(tostring(GetCurrentResourceName()) .. ':server:hireGovernmentEmployee', function(source, payload)
    return governmentEmploymentAction(source, payload, 'hire')
end)

ps.registerCallback(tostring(GetCurrentResourceName()) .. ':server:setGovernmentEmployeeGrade', function(source, payload)
    return governmentEmploymentAction(source, payload, 'grade_change')
end)

ps.registerCallback(tostring(GetCurrentResourceName()) .. ':server:terminateGovernmentEmployee', function(source, payload)
    return governmentEmploymentAction(source, payload, 'terminate')
end)

-- Get available officer tags/certifications (filtered by job type)
ps.registerCallback('ps-mdt:server:getOfficerTags', function(source)
    local src = source
    if not CheckAuth(src) then return {} end

    local jobType = ps.getJobType(src)
    local rows
    if jobType and (jobType == 'leo' or jobType == 'ems' or jobType == 'fire') then
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

    if type(payload) ~= 'table' then
        return { success = false, message = 'Invalid certification request' }
    end
    local citizenid = payload.citizenid
    local certifications = payload.certifications

    if type(citizenid) ~= 'string' or not citizenid:find('%S')
        or #citizenid > 64 or type(certifications) ~= 'table' then
        return { success = false, message = 'Invalid payload' }
    end

    local count = 0
    for _ in pairs(certifications) do
        count = count + 1
        if count > 200 then return { success = false, message = 'Too many certifications' } end
    end
    if not CanManageMdtPersonnel(src, citizenid) then
        return { success = false, message = 'Personnel administration is limited to your department' }
    end

    EnsureProfileExists(citizenid)

    if not CheckAuth(src) or not CheckPermission(src, 'roster_manage_certifications')
        or not CanManageMdtPersonnel(src, citizenid) then
        return { success = false, message = 'Personnel authorization changed' }
    end

    local encodeOk, encoded = pcall(json.encode, certifications)
    if not encodeOk or type(encoded) ~= 'string' or #encoded > 65535 then
        return { success = false, message = 'Certification data too large' }
    end
    local saved = MySQL.update.await('UPDATE mdt_profiles SET certifications = ? WHERE citizenid = ?', { encoded, citizenid })
    if saved == nil then return { success = false, message = 'Failed to save certifications' } end
    return { success = true }
end)

-- Get job grades for a specific department
ps.registerCallback('ps-mdt:server:getJobGrades', function(source, payload)
    local src = source
    if not CheckAuth(src) then return {} end
    if not CheckPermission(src, 'roster_manage_officers') then return {} end

    if payload ~= nil and type(payload) ~= 'table' then return {} end
    payload = payload or {}
    local jobName = payload.job or ps.getJobName(src)
    if type(jobName) ~= 'string' or #jobName > 64
        or jobName ~= ps.getJobName(src) then return {} end

    local jobData = ps.getSharedJob(jobName)
    if not jobData or not jobData.grades then
        local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
        jobData = ok and core and core.Shared and core.Shared.Jobs and core.Shared.Jobs[jobName]
    end
    if not jobData or not jobData.grades then return {} end
    if not CheckAuth(src) or not CheckPermission(src, 'roster_manage_officers')
        or jobName ~= ps.getJobName(src) then return {} end

    local grades = {}
    for gradeKey, gradeValue in pairs(jobData.grades) do
        if type(gradeValue) == 'table' then
            local level = tonumber(gradeValue.level or gradeValue.grade or gradeKey)
            if level and level == level and level ~= math.huge
                and level >= 0 and level % 1 == 0 then
                grades[#grades + 1] = {
                    grade = level,
                    name = gradeValue.name or gradeValue.label or ('Grade ' .. tostring(level)),
                    isBoss = gradeValue.isboss == true or gradeValue.isBoss == true or gradeValue.boss == true,
                }
            end
        end
    end

    table.sort(grades, function(a, b) return a.grade < b.grade end)
    return grades
end)

-- Promote/demote an officer (change their job grade)
-- Use QBCore for personnel changes; PowerMoves does not use QBX.
---@return boolean ok
local function setOfficerJob(targetSrc, jobName, grade)
    grade = tonumber(grade)
    if not grade or grade ~= grade or grade == math.huge
        or grade < 0 or grade % 1 ~= 0 then return false end
    if GetResourceState('qb-core') ~= 'started' then return false end

    local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and QBCore and QBCore.Functions then
        local Player = QBCore.Functions.GetPlayer(targetSrc)
        if Player and Player.Functions and Player.Functions.SetJob then
            local sok, result = pcall(function() return Player.Functions.SetJob(jobName, grade) end)
            if sok and result ~= false then
                local updated = QBCore.Functions.GetPlayer(targetSrc)
                local data = updated and updated.PlayerData and updated.PlayerData.job
                local actualGrade = data and data.grade
                actualGrade = type(actualGrade) == 'table' and actualGrade.level or actualGrade
                return data ~= nil and data.name == jobName and tonumber(actualGrade) == grade
            end
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

    if type(payload) ~= 'table' then
        return { success = false, message = 'Invalid personnel request' }
    end
    local citizenid = payload.citizenid
    local jobName = payload.job
    local newGrade = tonumber(payload.grade)
    if type(citizenid) ~= 'string' or not citizenid:find('%S') or #citizenid > 64
        or type(jobName) ~= 'string' or not jobName:find('%S') or #jobName > 64 then
        return { success = false, message = 'Invalid identifiers' }
    end

    if not citizenid or not jobName or not newGrade
        or newGrade ~= newGrade or newGrade == math.huge
        or newGrade < 0 or newGrade % 1 ~= 0 then
        return { success = false, message = 'Missing or invalid required fields' }
    end

    if not CanManageMdtPersonnel(src, citizenid, jobName) then
        return { success = false, message = 'Personnel administration is limited to your department' }
    end

    -- Validate the grade exists
    local gradeData = ps.getSharedJobGrade(jobName, newGrade)
    if not gradeData then
        local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
        local job = ok and core and core.Shared and core.Shared.Jobs and core.Shared.Jobs[jobName]
        gradeData = job and job.grades and (job.grades[tostring(newGrade)] or job.grades[newGrade])
    end
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

    -- Do not rely on source identity alone: the target may have reconnected.
    if citizenid == ps.getIdentifier(src) then
        return { success = false, message = 'You cannot change your own rank' }
    end
    if targetSrc == src then
        return { success = false, message = 'You cannot change your own rank' }
    end

    local currentTarget = ps.getPlayerByIdentifier(citizenid)
    local currentSrc = currentTarget and (currentTarget.source or (currentTarget.PlayerData and currentTarget.PlayerData.source))
    if tonumber(currentSrc) ~= tonumber(targetSrc) then
        return { success = false, message = 'Officer session changed; refresh the roster' }
    end
    if not CheckAuth(src) or not CheckPermission(src, 'roster_manage_officers')
        or not CanManageMdtPersonnel(src, citizenid, jobName) then
        return { success = false, message = 'Personnel authorization changed' }
    end

    if not setOfficerJob(targetSrc, jobName, newGrade) then
        return { success = false, message = 'Failed to update rank (framework error)' }
    end

    local gradeName = gradeData.name or gradeData.label or ('Grade ' .. newGrade)

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

    if type(payload) ~= 'table' then
        return { success = false, message = 'Invalid personnel request' }
    end
    local citizenid = payload.citizenid
    if payload.deleteData ~= nil and type(payload.deleteData) ~= 'boolean' then
        return { success = false, message = 'Invalid cleanup option' }
    end

    if type(citizenid) ~= 'string' or not citizenid:find('%S') or #citizenid > 64 then
        return { success = false, message = 'Invalid citizen ID' }
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

    if citizenid == ps.getIdentifier(src) then
        return { success = false, message = 'You cannot fire yourself' }
    end
    if targetSrc == src then
        return { success = false, message = 'You cannot fire yourself' }
    end

    if not CheckAuth(src) or not CheckPermission(src, 'roster_manage_officers')
        or not CanManageMdtPersonnel(src, citizenid) then
        return { success = false, message = 'Personnel authorization changed' }
    end

    local latest = ps.getPlayerByIdentifier(citizenid)
    local latestSource = latest and (latest.source or (latest.PlayerData and latest.PlayerData.source))
    if tonumber(latestSource) ~= tonumber(targetSrc) then
        return { success = false, message = 'Officer session changed; refresh the roster' }
    end

    if payload.deleteData and type(CleanupPersonnelData) ~= 'function' then
        return { success = false, message = 'Personnel cleanup unavailable' }
    end
    if not setOfficerJob(targetSrc, 'unemployed', 0) then
        return { success = false, message = 'Failed to terminate officer (framework error)' }
    end

    -- Optional full personal-data wipe (boss panel toggle). Runs after the job
    -- change so the person is already off the roster; only touches their own
    -- footprint, never investigative/shared data. See personnel_cleanup.lua.
    local cleanup = nil
    if payload.deleteData and type(CleanupPersonnelData) ~= 'function' then
        return { success = false, message = 'Personnel cleanup unavailable' }
    end
    if payload.deleteData and CleanupPersonnelData then
        if not CheckAuth(src) or not CheckPermission(src, 'roster_manage_officers')
            or not CanManageMdtPersonnel(src, citizenid) then
            return { success = false, message = 'Personnel cleanup authorization changed' }
        end
        local cleanupOk, cleanupResult = pcall(CleanupPersonnelData, citizenid)
        cleanup = cleanupOk and cleanupResult or { ok = false, error = tostring(cleanupResult) }
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

    if type(payload) ~= 'table' then
        return { success = false, message = 'Invalid callsign request' }
    end
    local citizenid = payload.citizenid
    local newCallsign = payload.callsign

    if type(citizenid) ~= 'string' or not citizenid:find('%S') or #citizenid > 64
        or type(newCallsign) ~= 'string' or not newCallsign:find('%S')
        or #newCallsign > 32 or newCallsign:find('[%c]') then
        return { success = false, message = 'Invalid citizen ID or callsign' }
    end

    if citizenid == ps.getIdentifier(src) then
        return { success = false, message = 'Use your own callsign settings' }
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

    local existing = MySQL.scalar.await(
        'SELECT citizenid FROM mdt_profiles WHERE callsign = ? AND citizenid != ? LIMIT 1',
        { newCallsign, citizenid }
    )
    if existing then
        return { success = false, message = 'Callsign is already assigned' }
    end

    -- Verify the target still belongs to the same department after the query.
    if not CheckAuth(src) or not CheckPermission(src, 'roster_manage_officers')
        or not CanManageMdtPersonnel(src, citizenid) then
        return { success = false, message = 'Personnel authorization changed' }
    end

    Player.Functions.SetMetaData('callsign', newCallsign)

    local resourceName = GetCurrentResourceName()
    TriggerClientEvent(resourceName .. ':client:updateCallsign', Player.PlayerData.source, newCallsign)

    local saved = MySQL.update.await('UPDATE mdt_profiles SET callsign = ? WHERE citizenid = ?', { newCallsign, citizenid })
    if saved == nil then return { success = false, message = 'Failed to save callsign' } end

    if ps.auditLog then
        ps.auditLog(src, 'callsign_changed', 'officers', citizenid, { callsign = newCallsign })
    end

    return { success = true, message = 'Callsign updated to ' .. newCallsign }
end)
