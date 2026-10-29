-- Stage 6 SAGOV vending permit applications only, scoped to issuing authority.
-- Business licenses use the existing government_business_licenses.lua registry.
-- Never uses job names, grade claims or citizen IDs supplied by NUI as authority.
local resourceName = tostring(GetCurrentResourceName())
local lastSubmission = {}
local supported = {vending = true}
local function clean(value, limit)
    if type(value) ~= 'string' then return nil end
    local result = value:match('^%s*(.-)%s*$')
    if #result < 1 or #result > limit then return nil end
    return result
end
local function validId(value)
    local id = tonumber(value)
    return id and id >= 1 and id <= 9007199254740991 and id % 1 == 0 and id or nil
end
local function affected(value)
    return type(value) == 'table' and tonumber(value.affectedRows) == 1
end
local function transactions()
    return type(MySQL) == 'table' and
        type(rawget(MySQL, 'startTransaction')) == 'function'
end
local function configuredGovernmentDesk(agency)
    local settings = Config and Config.PublicServices or {}
    local jobs = ((Config or {}).MdtAccess or {}).GovernmentJobs or {}
    if type(agency) ~= 'string' or not jobs[agency] then return false end
    for _, location in ipairs(settings.Locations or {}) do
        if location.agency == agency and type(location.services) == 'table' then
            for _, service in ipairs(location.services) do
                if service == 'government_license_apply' then return true end
            end
        end
    end
    return false
end
local function officer(source)
    if type(GetGovernmentLicenseAccess) ~= 'function' then return nil end
    local ok, access = pcall(GetGovernmentLicenseAccess, source)
    if not ok or type(access) ~= 'table' then return nil end
    local jobs = ((Config or {}).MdtAccess or {}).GovernmentJobs or {}
    if type(access.citizenid) ~= 'string' or access.citizenid == ''
        or jobs[access.agency] ~= access.jurisdiction then return nil end
    return access
end
local function sameOfficer(source, previous)
    local current = officer(source)
    return current and current.citizenid == previous.citizenid
        and current.agency == previous.agency
        and current.jurisdiction == previous.jurisdiction
        and current.canReview == previous.canReview
        and current.canApprove == previous.canApprove
        and current.canRevoke == previous.canRevoke
end

ps.registerCallback(resourceName .. ':server:applyGovernmentLicense', function(source, data)
    local cid = ps.getIdentifier(source)
    if type(cid) ~= 'string' or cid == '' or type(data) ~= 'table'
        or not configuredGovernmentDesk(data.agency)
        or not PublicServiceDeskAllows(source, data.agency, 'government_license_apply') then
        return {success=false, error='Government license counter unavailable'}
    end
    local jobs = (Config.MdtAccess or {}).GovernmentJobs or {}
    local kind = data.licenseType
    local name = clean(data.businessName, 160)
    local description = clean(data.description, 4000)
    if not supported[kind] or not name or not description or not transactions() then
        return {success=false, error='Invalid application or transaction support unavailable'}
    end
    local now = GetGameTimer()
    if lastSubmission[cid] and now - lastSubmission[cid] >= 0
        and now - lastSubmission[cid] < 60000 then
        return {success=false, error='Please wait before another application'}
    end
    lastSubmission[cid] = now
    local id
    local ok, committed = pcall(MySQL.startTransaction, function(query)
        if ps.getIdentifier(source) ~= cid
            or not PublicServiceDeskAllows(source, data.agency, 'government_license_apply') then
            return false
        end
        local inserted = query([[
            INSERT INTO mdt_government_license_applications
                (applicant_citizenid, agency, jurisdiction, license_type,
                 business_name, description)
            VALUES (?, ?, ?, ?, ?, ?)
        ]], {cid, data.agency, jobs[data.agency], kind, name, description})
        if not affected(inserted) or not validId(inserted.insertId) then return false end
        id = inserted.insertId
        local audit = query([[
            INSERT INTO mdt_government_license_audit
                (application_id, agency, actor_citizenid, action, reason)
            VALUES (?, ?, ?, 'submitted', 'Applicant submitted application')
        ]], {id, data.agency, cid})
        return affected(audit) and ps.getIdentifier(source) == cid
            and PublicServiceDeskAllows(source, data.agency, 'government_license_apply')
    end)
    if not ok or committed ~= true then
        lastSubmission[cid] = nil
        return {success=false, error='Application not saved'}
    end
    if ps.getIdentifier(source) ~= cid then
        return {success=false, error='Application saved to original character; session changed'}
    end
    return {success=true, id=id}
end)

ps.registerCallback(resourceName .. ':server:getMyGovernmentLicenses', function(source)
    local cid = ps.getIdentifier(source)
    if type(cid) ~= 'string' or cid == ''
        or not PublicServiceDeskAllows(source, nil, 'government_license_status') then
        return {success=false, error='License counter unavailable'}
    end
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT id, agency, jurisdiction, license_type, business_name, status,
               decision_reason, expires_at, revoked_at, created_at
        FROM mdt_government_license_applications
        WHERE applicant_citizenid = ?
        ORDER BY id DESC LIMIT 50
    ]], {cid})
    if not ok or ps.getIdentifier(source) ~= cid
        or not PublicServiceDeskAllows(source, nil, 'government_license_status') then
        return {success=false, error='License counter access changed'}
    end
    return {success=true, applications=rows or {}}
end)

ps.registerCallback(resourceName .. ':server:getGovernmentLicenseQueue', function(source, data)
    local access = officer(source)
    if not access or access.canReview ~= true then
        return {success=false, error='License review not authorized'}
    end
    local page = type(data) == 'table' and tonumber(data.page) or 0
    if not page or page < 0 or page > 200 or page % 1 ~= 0 then
        return {success=false, error='Invalid page'}
    end
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT id, applicant_citizenid, agency, jurisdiction, license_type,
               business_name, description, status, assigned_to_citizenid,
               decision_reason, expires_at, revoked_at, created_at
        FROM mdt_government_license_applications
        WHERE agency = ? AND jurisdiction = ?
        ORDER BY CASE WHEN status IN ('submitted','under_review') THEN 0 ELSE 1 END,
                 id DESC LIMIT ? OFFSET ?
    ]], {access.agency, access.jurisdiction, 51, page*50})
    if not ok or not sameOfficer(source, access) then
        return {success=false, error='License review access changed'}
    end
    rows = type(rows) == 'table' and rows or {}
    local more = #rows > 50
    if more then rows[#rows] = nil end
    return {success=true, applications=rows, page=page, hasMore=more,
        agency=access.agency, canApprove=access.canApprove == true,
        canRevoke=access.canRevoke == true}
end)

ps.registerCallback(resourceName .. ':server:decideGovernmentLicense', function(source, data)
    local access = officer(source)
    if not access or type(data) ~= 'table' or access.canReview ~= true then
        return {success=false, error='License review denied'}
    end
    local id = validId(data.id)
    local action = data.action
    local reason = clean(data.reason, 1000)
    if not id or not reason
        or (action ~= 'under_review' and action ~= 'approved'
            and action ~= 'denied' and action ~= 'revoked') then
        return {success=false, error='Invalid decision'}
    end
    if action == 'approved' and access.canApprove ~= true
        or action == 'revoked' and access.canRevoke ~= true then
        return {success=false, error='Issuance or revocation permission required'}
    end
    if not transactions() then return {success=false, error='Checked transactions unavailable'} end
    local ok, committed = pcall(MySQL.startTransaction, function(query)
        local rows = query([[
            SELECT status, jurisdiction, license_type, business_name, applicant_citizenid
            FROM mdt_government_license_applications
            WHERE id = ? AND agency = ? FOR UPDATE
        ]], {id, access.agency})
        local row = type(rows) == 'table' and rows[1] or nil
        if not row or row.jurisdiction ~= access.jurisdiction
            or not sameOfficer(source, access) then return false end
        local old = row.status
        if (action == 'under_review' and old ~= 'submitted')
            or ((action == 'approved' or action == 'denied') and old ~= 'under_review')
            or (action == 'revoked' and old ~= 'approved') then return false end
        if action == 'approved' then
            local key = row.business_name:lower():match('^%s*(.-)%s*$')
            local held = query([[
                SELECT application_id, expires_at, revoked_at
                FROM mdt_government_license_registry
                WHERE jurisdiction = ? AND license_type = ? AND business_key = ?
                FOR UPDATE
            ]], {access.jurisdiction, row.license_type, key})
            if type(held) ~= 'table' then return false end
            if held[1] then
                -- Do not silently overwrite a live license. A staff member
                -- must revoke/expire the previous slot before reissuing.
                local replaced = query([[
                    UPDATE mdt_government_license_registry
                    SET application_id = ?, expires_at = DATE_ADD(UTC_TIMESTAMP(), INTERVAL 365 DAY),
                        revoked_at = NULL
                    WHERE jurisdiction = ? AND license_type = ? AND business_key = ?
                        AND (revoked_at IS NOT NULL OR expires_at <= UTC_TIMESTAMP())
                ]], {id, access.jurisdiction, row.license_type, key})
                if not affected(replaced) then return false end
            else
                local created = query([[
                    INSERT INTO mdt_government_license_registry
                        (jurisdiction, license_type, business_key, application_id, expires_at)
                    VALUES (?, ?, ?, ?, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 365 DAY))
                ]], {access.jurisdiction, row.license_type, key, id})
                if not affected(created) then return false end
            end
        elseif action == 'revoked' then
            local removed = query([[
                UPDATE mdt_government_license_registry
                SET revoked_at = UTC_TIMESTAMP()
                WHERE application_id = ? AND jurisdiction = ? AND revoked_at IS NULL
            ]], {id, access.jurisdiction})
            if not affected(removed) then return false end
        end

        local changed = query([[
            UPDATE mdt_government_license_applications
            SET status = ?, assigned_to_citizenid = COALESCE(assigned_to_citizenid, ?),
                decided_by_citizenid = ?, decision_reason = ?, decided_at = UTC_TIMESTAMP(),
                expires_at = CASE WHEN ? = 'approved' THEN DATE_ADD(UTC_TIMESTAMP(), INTERVAL 365 DAY)
                    ELSE expires_at END,
                revoked_by_citizenid = CASE WHEN ? = 'revoked' THEN ? ELSE revoked_by_citizenid END,
                revoked_at = CASE WHEN ? = 'revoked' THEN UTC_TIMESTAMP() ELSE revoked_at END
            WHERE id = ? AND agency = ? AND jurisdiction = ? AND status = ?
        ]], {action, access.citizenid, access.citizenid, reason, action,
            action, access.citizenid, action, id, access.agency, access.jurisdiction, old})
        if not affected(changed) then return false end
        local audit = query([[
            INSERT INTO mdt_government_license_audit
                (application_id, agency, actor_citizenid, action, reason)
            VALUES (?, ?, ?, ?, ?)
        ]], {id, access.agency, access.citizenid, action, reason})
        return affected(audit) and sameOfficer(source, access) == true
    end)
    if not ok or committed ~= true then
        return {success=false, error='License decision not saved; check status and other active licenses'}
    end
    return {success=true}
end)

-- SADOT prerequisite lookup reads the canonical local business-license
-- register, not vending permits. It never grants towing authority itself.
function HasGovernmentBusinessLicense(citizenid, businessName, jurisdiction)
    local name = clean(businessName, 160)
    if type(citizenid) ~= 'string' or citizenid == '' or not name
        or type(jurisdiction) ~= 'string' then return false end
    local ok, row = pcall(MySQL.single.await, [[
        SELECT id FROM mdt_government_business_licenses
        WHERE owner_citizenid = ? AND jurisdiction = ?
          AND business_name = ? AND status = 'approved'
        LIMIT 1
    ]], {citizenid, jurisdiction, name})
    return ok and row ~= nil
end
