-- Authorisation. Interface entry, role capabilities and record authorization
-- are separate: selecting a screen never changes the player's real job.
local selectedInterfaces = {}

local function contains(list, value)
    for _, entry in ipairs(list or {}) do
        if entry == value then return true end
    end
    return false
end

local function runtimeIdentity(source)
    local src = tonumber(source)
    if not src or src <= 0 then return nil end
    local ok, identity = pcall(function()
        local job = ps.getJobData and ps.getJobData(src) or {}
        local grade = job.grade
        local gradeValue = type(grade) == 'table'
            and (grade.level or grade.grade or grade.rank or grade.value or grade.id)
            or grade
        local gradeNumber = tonumber(gradeValue)
        -- Keep the legacy zero fallback, but distinguish an actual valid grade
        -- from missing/corrupt data before evaluating government role grants.
        local gradeValid = gradeNumber ~= nil and gradeNumber >= 0
            and gradeNumber < math.huge and gradeNumber % 1 == 0
        local boss = job.isboss == true or job.isBoss == true
            or (type(grade) == 'table' and (grade.isboss == true or grade.isBoss == true or grade.boss == true))
            or (ps.isBoss and ps.isBoss(src) == true)
        local duty = job.onduty
        if ps.getJobDuty then duty = ps.getJobDuty(src) end
        return {
            source = src,
            citizenid = ps.getIdentifier(src),
            job = ps.getJobName(src),
            coreJobType = ps.getJobType(src),
            grade = gradeNumber or 0,
            gradeValid = gradeValid,
            isBoss = boss == true,
            onDuty = duty == true,
        }
    end)
    if not ok or not identity.job or not identity.citizenid then return nil end
    local policy = Config.MdtAccess or {}
    identity.jurisdiction = (policy.GovernmentJobs or {})[identity.job]
    if identity.jurisdiction then
        identity.jobType, identity.primaryInterfaceId = 'gov', 'sagov'
    elseif identity.coreJobType == 'gov' then
        -- An unmapped government job must never fall through to police access.
        return identity
    elseif contains(Config.DojJobs, identity.job) or identity.coreJobType == Config.DojJobType then
        identity.jobType, identity.primaryInterfaceId = 'doj', 'sadoj'
    elseif contains(Config.PoliceJobs, identity.job) or identity.coreJobType == Config.PoliceJobType then
        identity.jobType, identity.primaryInterfaceId = 'leo', 'sadle'
    elseif contains(policy.FireJobs, identity.job) or identity.coreJobType == Config.FireJobType then
        -- Fire is a distinct QBCore job type. Preserve the legacy EMS MDT
        -- permission/domain compatibility until its backend is fully split.
        identity.jobType, identity.primaryInterfaceId = 'ems', 'safr'
    elseif contains(Config.MedicalJobs, identity.job) or identity.coreJobType == Config.MedicalJobType then
        identity.jobType, identity.primaryInterfaceId = 'ems', 'sams'
    end
    return identity
end

local function isAttorneyGeneral(identity)
    local rule = (Config.MdtAccess or {}).AttorneyGeneral or {}
    return identity and identity.job == rule.job and identity.grade == tonumber(rule.grade)
end

local function hasJudicialAuthority(identity)
    local rules = (Config.MdtAccess or {}).JudicialGrades or {}
    return identity ~= nil and identity.jobType == 'doj' and contains(rules[identity.job], identity.grade)
end

function IsMdtAttorneyGeneral(source)
    return isAttorneyGeneral(runtimeIdentity(source)) == true
end

function HasMdtJudicialAuthority(source)
    return hasJudicialAuthority(runtimeIdentity(source)) == true
end

local function rolePermissions(identity)
    -- SAFR retains the existing legacy EMS jobType for operational callbacks,
    -- but its *authorization ceiling* is an independent fire permission family.
    -- Neither switching screens nor holding a boss flag merges the two sets.
    local permissionFamily = identity.primaryInterfaceId == 'safr' and 'fire' or identity.jobType
    local ceiling = ((Config.MdtAccess or {}).PermissionSets or {})[permissionFamily] or {}
    -- Government has no operational callbacks in phase 1. Stored roles or a
    -- QBCore boss flag cannot turn interface entry into police/medical access.
    if identity.jobType == 'gov' then return {} end
    -- Safe migration: 'legacy' retains current boss access; 'explicit' uses
    -- approved job-and-grade permission grants for bosses as well.
    -- QBCore boss employment authority remains independent of MDT grants.
    local bossMode = ((Config.MdtAccess or {}).BossPermissionMode or 'legacy')
    local granted = identity.isBoss and bossMode ~= 'explicit' and ceiling or nil
    if not granted then
        local row = MySQL.single.await(
            'SELECT permissions FROM mdt_permission_roles WHERE job = ? AND grade = ?',
            { identity.job, identity.grade }
        )
        if row and row.permissions then
            local ok, decoded = pcall(json.decode, row.permissions)
            if ok and type(decoded) == 'table' then granted = decoded end
        end
        if not granted then
            local defaults = (Config.PermissionDefaults or {})[identity.job] or {}
            granted = defaults[tostring(identity.grade)] or {}
        end
    end
    local permissions, seen = {}, {}
    for _, permission in ipairs(granted) do
        local allowed = contains(ceiling, permission)
            or (type(permission) == 'string' and permission:sub(1, 11) == 'tab_hidden_')
        if permission == 'judicial_authority' or permission == 'warrants_approve' then
            allowed = false -- Added below only from the exact live judicial role.
        end
        -- AG heads SADLE and supervises prosecution; neither boss nor stored
        -- permissions may confer court scheduling/modification or adjudication.
        if isAttorneyGeneral(identity) and type(permission) == 'string'
            and permission:sub(1, 6) == 'court_' and permission ~= 'court_view' then
            allowed = false
        end
        if isAttorneyGeneral(identity) and (permission == 'warrants_issue' or permission == 'warrants_close') then
            allowed = false
        end
        if allowed and not seen[permission] then
            permissions[#permissions + 1], seen[permission] = permission, true
        end
    end
    -- These capabilities derive only from the exact judicial role mapping.
    if hasJudicialAuthority(identity) then
        permissions[#permissions + 1] = 'judicial_authority'
        permissions[#permissions + 1] = 'warrants_approve'
    end
    return permissions
end

-- Legacy operational eligibility deliberately excludes government. Existing
-- callbacks using only CheckAuth must not become available to new GOV users.
function CheckAuth(source)
    local identity = runtimeIdentity(source)
    return identity ~= nil and identity.primaryInterfaceId ~= nil and identity.jobType ~= 'gov'
end

function GetMdtAccess(source)
    local identity = runtimeIdentity(source)
    local empty = {
        authorized = false, eligible = false, isCivilian = false, onDuty = false,
        jobType = 'civilian', allowedInterfaces = {}, permissions = {}, isBoss = false,
    }
    if not identity then return empty end
    if not identity.primaryInterfaceId then
        selectedInterfaces[identity.source] = nil
        empty.authorized = Config.CivilianAccess and Config.CivilianAccess.enabled == true or false
        empty.isCivilian, empty.onDuty = empty.authorized, empty.authorized
        empty.agency = identity.job
        return empty
    end
    local allowed = { identity.primaryInterfaceId }
    if isAttorneyGeneral(identity) then allowed[#allowed + 1] = 'sadoj' end
    local fingerprint = table.concat({ identity.citizenid, identity.job, tostring(identity.grade) }, ':')
    local selection = selectedInterfaces[identity.source]
    if not selection or selection.fingerprint ~= fingerprint or not contains(allowed, selection.interfaceId) then
        selection = { fingerprint = fingerprint, interfaceId = identity.primaryInterfaceId }
        selectedInterfaces[identity.source] = selection
    end
    local authorized = identity.jobType == 'doj' or Config.OnlyShowOnDuty ~= true or identity.onDuty
    local role = isAttorneyGeneral(identity) and 'attorney_general'
        or (hasJudicialAuthority(identity) and 'judiciary')
        or (identity.job == 'sadoj' and (identity.grade == 5 or identity.grade == 6) and 'prosecution')
        or identity.jobType
    return {
        authorized = authorized, eligible = true, isCivilian = false, onDuty = identity.onDuty,
        jobType = selection.interfaceId == 'sadoj' and 'doj' or identity.jobType,
        coreJobType = identity.coreJobType, grade = identity.grade, role = role,
        interfaceId = selection.interfaceId, primaryInterfaceId = identity.primaryInterfaceId,
        allowedInterfaces = allowed, agency = identity.job, jurisdiction = identity.jurisdiction,
        permissions = rolePermissions(identity), isBoss = identity.isBoss,
    }
end

function CheckMdtInterfaceAccess(source, interfaceId)
    local access = GetMdtAccess(source)
    return access.authorized and contains(access.allowedInterfaces, interfaceId)
end

-- Dedicated read-only statewide LEO roster authorization. Do not use the
-- legacy boss permission ceiling; an agency boss is not automatically an
-- investigator or statewide accreditor. Access is an exact live job+grade
-- stored role grant limited to approved oversight jobs, or the configured AG.
function CanViewStatewideLeoRoster(source)
    local identity = runtimeIdentity(source)
    if not identity or identity.jobType ~= 'leo' or not identity.gradeValid then return false end
    local allowedJobs = ((Config.MdtAccess or {}).LeoRosterOversightJobs) or {}
    if not contains(allowedJobs, identity.job) then return false end
    if isAttorneyGeneral(identity) then return true end
    local ok, row = pcall(MySQL.single.await,
        'SELECT permissions FROM mdt_permission_roles WHERE job = ? AND grade = ?',
        {identity.job, identity.grade})
    if not ok or not row then return false end
    local granted = row.permissions
    if type(granted) == 'string' then
        local decodedOk, decoded = pcall(json.decode, granted)
        granted = decodedOk and decoded or nil
    end
    if type(granted) ~= 'table' or not contains(granted, 'leo_roster_oversight') then return false end
    -- Database queries yield; verify employment still matches the caller.
    local now = runtimeIdentity(source)
    return now ~= nil and now.jobType == 'leo' and now.gradeValid
        and now.citizenid == identity.citizenid
        and now.job == identity.job and now.grade == identity.grade
        and now.onDuty == identity.onDuty
end

-- Separate, read-only government personnel scope. This deliberately does not
-- use CheckAuth/CheckPermission or boss-derived operational permission sets.
function GetGovernmentRosterAccess(source)
    local identity = runtimeIdentity(source)
    if not identity or identity.gradeValid ~= true or identity.jobType ~= 'gov' or not identity.jurisdiction then return nil end
    local access = GetMdtAccess(source)
    if not access.authorized or access.isCivilian or access.interfaceId ~= 'sagov' then return nil end

    local ok, row = pcall(MySQL.single.await,
        'SELECT permissions FROM mdt_permission_roles WHERE job = ? AND grade = ?',
        { identity.job, identity.grade }
    )
    if not ok then return nil end
    local permissions = {}
    if row then
        -- A stored empty or malformed value does not revive config defaults.
        if type(row.permissions) == 'table' then
            permissions = row.permissions
        elseif type(row.permissions) == 'string' then
            local decodedOk, decoded = pcall(json.decode, row.permissions)
            if decodedOk and type(decoded) == 'table' then permissions = decoded end
        end
    else
        local defaults = (Config.PermissionDefaults or {})[identity.job] or {}
        local configured = defaults[tostring(identity.grade)]
        if type(configured) == 'table' then permissions = configured end
    end

    -- The role lookup can yield. Never return a previous character's or job's
    -- scope after a disconnect, duty update, promotion or employment change.
    local current = runtimeIdentity(source)
    if not current or current.gradeValid ~= true or current.citizenid ~= identity.citizenid or current.job ~= identity.job
        or current.grade ~= identity.grade or current.onDuty ~= identity.onDuty
        or current.jobType ~= 'gov' or current.jurisdiction ~= identity.jurisdiction then return nil end
    local currentAccess = GetMdtAccess(source)
    if not currentAccess.authorized or currentAccess.isCivilian or currentAccess.interfaceId ~= 'sagov' then return nil end

    local policy = Config.MdtAccess or {}
    local permission = (policy.GovernmentPersonnel or {}).OversightPermission
    local hasOversight = current.job == 'sagov' and type(permission) == 'string'
        and permission ~= '' and contains(permissions, permission)
    local allowedJobs = { current.job }
    if hasOversight then
        local otherJobs = {}
        for jobName in pairs(policy.GovernmentJobs or {}) do
            if jobName ~= current.job then otherJobs[#otherJobs + 1] = jobName end
        end
        table.sort(otherJobs)
        for _, jobName in ipairs(otherJobs) do allowedJobs[#allowedJobs + 1] = jobName end
    end
    return {
        citizenid = current.citizenid, agency = current.job, grade = current.grade,
        jurisdiction = current.jurisdiction, allowedJobs = allowedJobs, hasOversight = hasOversight == true,
    }
end

function CheckPermission(source, permName)
    if not permName or not CheckAuth(source) then return false end
    local access = GetMdtAccess(source)
    return contains(access.permissions, permName)
end

local function upsertProfileSession(src, action)
    if not src then return end
    local citizenid = ps.getIdentifier(src)
    if not citizenid then return end

    local fullName = ps.getPlayerName(src)
    local callsign = ps.getMetadata(src, 'callsign')
    local job = ps.getJobData and ps.getJobData(src) or nil
    local jobName = job and job.name or ps.getJobName(src)
    local jobGrade = job and job.grade and job.grade.name or ps.getJobGradeName(src)

    local ok, profileId = pcall(EnsureProfileData,
        citizenid,
        fullName,
        callsign,
        callsign,
        jobGrade,
        jobName
    )

    if not ok or not profileId then
        ps.warn('Failed to upsert profile session for ' .. tostring(citizenid) .. ': ' .. tostring(profileId))
        return
    end

    if action == 'login' then
        -- Wrap all login operations in a single transaction to prevent race conditions
        local okTx, errTx = pcall(MySQL.transaction.await, {
            {
                query = [[
                    UPDATE mdt_profile_sessions
                    SET logout_at = NOW()
                    WHERE profile_id = ? AND logout_at IS NULL
                ]],
                values = { profileId }
            },
            {
                query = [[
                    INSERT INTO mdt_profile_sessions (profile_id, citizenid, source, login_at)
                    VALUES (?, ?, ?, NOW())
                ]],
                values = { profileId, citizenid, src }
            },
            {
                query = 'UPDATE mdt_profiles SET last_login_at = NOW() WHERE id = ?',
                values = { profileId }
            },
        })
        if not okTx then
            ps.warn('Failed to create login session (transaction): ' .. tostring(errTx))
        end
    elseif action == 'logout' then
        local okTx, errTx = pcall(MySQL.transaction.await, {
            {
                query = [[
                    UPDATE mdt_profile_sessions
                    SET logout_at = NOW()
                    WHERE profile_id = ? AND logout_at IS NULL
                    ORDER BY id DESC
                    LIMIT 1
                ]],
                values = { profileId }
            },
            {
                query = 'UPDATE mdt_profiles SET last_logout_at = NOW() WHERE id = ?',
                values = { profileId }
            },
        })
        if not okTx then
            ps.warn('Failed to update logout session (transaction): ' .. tostring(errTx))
        end
    end
end

-- FiveManage log helper for duty logging
local function SendDutyLog(officerName, citizenid, action, jobName)
    if not FiveManageQueueLog then return end

    FiveManageQueueLog({
        action = action == 'login' and 'mdt_clock_in' or 'mdt_clock_out',
        category = 'duty',
        message = (action == 'login' and 'Clock In' or 'Clock Out') .. ': ' .. (officerName or 'Unknown'),
        metadata = {
            officer = officerName or 'Unknown',
            citizenid = citizenid or 'N/A',
            department = jobName or 'Unknown',
            time = os.date('%Y-%m-%d %H:%M:%S')
        }
    })
end

RegisterNetEvent('ps-mdt:server:trackLogin', function()
    local src = source
    if not CheckAuth(src) then return end
    upsertProfileSession(src, 'login')
    if ps.auditLog then
        ps.auditLog(src, 'mdt_login', 'profile', ps.getIdentifier(src), {})
    end
    -- FiveManage duty log
    local officerName = ps.getPlayerName(src) or 'Unknown'
    local citizenid = ps.getIdentifier(src) or 'N/A'
    local jobName = ps.getJobName(src) or 'Unknown'
    SendDutyLog(officerName, citizenid, 'login', jobName)
end)

RegisterNetEvent('ps-mdt:server:trackLogout', function()
    local src = source
    if not CheckAuth(src) then return end
    upsertProfileSession(src, 'logout')
    if ps.auditLog then
        ps.auditLog(src, 'mdt_logout', 'profile', ps.getIdentifier(src), {})
    end
    -- FiveManage duty log
    local officerName = ps.getPlayerName(src) or 'Unknown'
    local citizenid = ps.getIdentifier(src) or 'N/A'
    local jobName = ps.getJobName(src) or 'Unknown'
    SendDutyLog(officerName, citizenid, 'logout', jobName)
end)

AddEventHandler('playerDropped', function()
    local src = source
    selectedInterfaces[tonumber(src)] = nil
    upsertProfileSession(src, 'logout')
end)

ps.registerCallback(tostring(GetCurrentResourceName())..':server:checkAuth', function(source)
    local access = GetMdtAccess(source)
    -- Preserve the tablet-opening callback's existing boolean/civilian shape.
    -- Staff may open the duty screen without being authorized for operations.
    if access.eligible then return true end
    if access.isCivilian then return { isCivilian = true } end
    return false
end)

ps.registerCallback(tostring(GetCurrentResourceName())..':server:getInterfaceAccess', function(source)
    return GetMdtAccess(source)
end)

ps.registerCallback(tostring(GetCurrentResourceName())..':server:setInterface', function(source, payload)
    local interfaceId = type(payload) == 'table' and payload.interfaceId or payload
    local access = GetMdtAccess(source)
    if type(interfaceId) ~= 'string' or not access.authorized or not contains(access.allowedInterfaces, interfaceId) then
        access.success, access.error = false, 'Interface access denied'
        return access
    end
    -- Loading role permissions can yield on MySQL. Recheck the live identity
    -- before changing selection in case the player changed jobs or disconnected.
    local identity = runtimeIdentity(source)
    local selection = selectedInterfaces[tonumber(source)]
    local fingerprint = identity and table.concat({ identity.citizenid, identity.job, tostring(identity.grade) }, ':')
    if not identity or not selection or selection.fingerprint ~= fingerprint then
        access = GetMdtAccess(source)
        access.success, access.error = false, 'Identity changed; refresh interface access'
        return access
    end
    selection.interfaceId = interfaceId
    access = GetMdtAccess(source)
    access.success = access.authorized and access.interfaceId == interfaceId
    return access
end)

-- Existing consumers keep their permission response fields, with explicit
-- effective grants rather than an unrestricted boss override.
ps.registerCallback(tostring(GetCurrentResourceName())..':server:getMyPermissions', function(source)
    local access = GetMdtAccess(source)
    return { permissions = access.permissions, isBoss = access.isBoss }
end)
