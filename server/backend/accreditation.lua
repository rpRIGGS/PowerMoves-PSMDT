-- Personal accreditation ledger. Supplements (does not replace) the existing
-- roster certification tags in mdt_profiles.certifications.
-- POST sets/records peace officer and corrections credentials; SAFR records
-- statewide fire-rescue credentials. Department FTO records remain separate.
local resourceName = tostring(GetCurrentResourceName())
local schemaReady = false

local function ensureSchema()
    if schemaReady then return true end
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS mdt_personal_accreditations (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                citizenid VARCHAR(64) NOT NULL,
                credential_code VARCHAR(64) NOT NULL,
                credential_name VARCHAR(160) NOT NULL,
                credential_family VARCHAR(16) NOT NULL,
                specialization VARCHAR(160) DEFAULT NULL,
                issued_by_job VARCHAR(64) NOT NULL,
                issued_by_citizenid VARCHAR(64) NOT NULL,
                issued_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                expires_at DATE DEFAULT NULL,
                source_reference VARCHAR(128) DEFAULT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                KEY idx_accreditation_citizen (citizenid, credential_family),
                KEY idx_accreditation_issuer (issued_by_job)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
    end)
    if not ok then
        print('[ps-mdt] Accreditation table unavailable: ' .. tostring(err))
        return false
    end
    schemaReady = true
    return true
end

CreateThread(function()
    Wait(2500)
    ensureSchema()
end)

local function clean(value, max)
    if type(value) ~= 'string' then return nil end
    local v = value:match('^%s*(.-)%s*$')
    if v == '' or #v > max then return nil end
    return v
end

local function issuerFamily(source)
    local job = ps.getJobName(source)
    if job == 'post' then return 'leo' end
    if job == 'safr' then return 'fire' end
    -- SAMS is the statewide medical accreditor. The existing explicit
    -- certification-management grant is required for issuance.
    if job == 'sams' then return 'ems' end
    -- SADLE is the accreditor; accreditation officers must have their own
    -- approved grant rather than inheriting permission solely from a job label.
    if job == 'sadle' then return 'leo' end
    return nil
end

local function readByCitizen(citizenid)
    if not ensureSchema() then return {} end
    return MySQL.query.await([[
        SELECT id, credential_code, credential_name, credential_family,
               specialization, issued_by_job, issued_at, expires_at, source_reference
        FROM mdt_personal_accreditations
        WHERE citizenid = ?
        ORDER BY issued_at DESC, id DESC
        LIMIT 200
    ]], {citizenid}) or {}
end

-- The owner of a credential can read it after transferring employment.
ps.registerCallback(resourceName .. ':server:getMyAccreditations', function(source)
    if not CheckAuth(source) then return {} end
    local citizenid = ps.getIdentifier(source)
    if not citizenid then return {} end
    local ok, rows = pcall(readByCitizen, citizenid)
    if not CheckAuth(source) or ps.getIdentifier(source) ~= citizenid then return {} end
    return ok and rows or {}
end)

-- Current-employer supervisors may read a subordinate's credentials.
-- This does not permit unrelated employer queries or editing former DORs.
ps.registerCallback(resourceName .. ':server:getPersonnelAccreditations', function(source, citizenid)
    if not CheckAuth(source) or type(citizenid) ~= 'string' then return {} end
    if citizenid ~= ps.getIdentifier(source) then
        if not CheckPermission(source, 'roster_manage_certifications')
            or not CanManageMdtPersonnel(source, citizenid) then return {} end
    end
    local originalActor, originalJob = ps.getIdentifier(source), ps.getJobName(source)
    local ok, rows = pcall(readByCitizen, citizenid)
    if not CheckAuth(source) or ps.getIdentifier(source) ~= originalActor
        or ps.getJobName(source) ~= originalJob then return {} end
    if citizenid ~= originalActor and (not CheckPermission(source, 'roster_manage_certifications')
        or not CanManageMdtPersonnel(source, citizenid)) then return {} end
    return ok and rows or {}
end)

-- POST/SAFR/SADLE qualified certification officials can issue permanent
-- credentials. A credential is a history entry; a later duplicate/renewal
-- is an additional issuance and never erases the earlier one.
ps.registerCallback(resourceName .. ':server:issueAccreditation', function(source, payload)
    if not CheckAuth(source) then return {success = false, message = 'Unauthorized'} end
    local family = issuerFamily(source)
    if not family or not CheckPermission(source, 'roster_manage_certifications') then
        return {success = false, message = 'Accreditation issuer authorization required'}
    end
    if type(payload) ~= 'table' then return {success = false, message = 'Invalid request'} end
    local citizenid = clean(payload.citizenid, 64)
    local code = clean(payload.code, 64)
    local name = clean(payload.name, 160)
    if not citizenid or not code or not name then
        return {success = false, message = 'Citizen, credential code and title are required'}
    end
    if not code:match('^[%w_%-%.]+$') then
        return {success = false, message = 'Credential code contains invalid characters'}
    end
    local specialization = clean(payload.specialization, 160)
    local sourceRef = clean(payload.reference, 128)
    local expiry = payload.expiresAt
    if expiry == '' then expiry = nil end
    if expiry ~= nil then
        if type(expiry) ~= 'string' or not expiry:match('^%d%d%d%d%-%d%d%-%d%d$') then
            return {success = false, message = 'Expiry must be YYYY-MM-DD'}
        end
    end
    local originalActor, originalIssuer = ps.getIdentifier(source), ps.getJobName(source)
    if not originalActor or not originalIssuer then
        return {success = false, message = 'Unauthorized'}
    end
    local found = MySQL.scalar.await('SELECT citizenid FROM players WHERE citizenid = ? LIMIT 1', {citizenid})
    if not found then return {success = false, message = 'Character not found'} end
    -- The target-citizen lookup may yield. Revalidate the exact issuer and
    -- actor before adding a permanent credential to the shared ledger.
    if not CheckAuth(source) or issuerFamily(source) ~= family
        or ps.getIdentifier(source) ~= originalActor or ps.getJobName(source) ~= originalIssuer
        or not CheckPermission(source, 'roster_manage_certifications') then
        return {success = false, message = 'Authorization changed'}
    end
    local issuer = ps.getJobName(source)
    local actor = ps.getIdentifier(source)
    if not issuer or not actor or not ensureSchema() then
        return {success = false, message = 'Accreditation unavailable'}
    end
    -- Schema setup can also yield. Do not attribute issuance to a new
    -- character or department if the employee changed during initialization.
    if not CheckAuth(source) or ps.getJobName(source) ~= issuer
        or ps.getIdentifier(source) ~= actor or issuerFamily(source) ~= family
        or not CheckPermission(source, 'roster_manage_certifications') then
        return {success = false, message = 'Authorization changed'}
    end
    local ok, id = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO mdt_personal_accreditations
            (citizenid, credential_code, credential_name, credential_family,
             specialization, issued_by_job, issued_by_citizenid, expires_at, source_reference)
            VALUES (?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), ?)
        ]], {citizenid, code, name, family, specialization or '', issuer, actor, expiry or '', sourceRef or ''})
    end)
    if not ok or not id then
        return {success = false, message = 'Accreditation could not be saved'}
    end
    if ps.auditLog then
        ps.auditLog(source, 'accreditation_issued', 'citizen', citizenid,
            {credential_id = id, credential_code = code, issuer = issuer})
    end
    return {success = true, id = id}
end)
