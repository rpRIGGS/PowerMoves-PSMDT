-- Stage 6: server-side 511 tow eligibility. This grants no SADOT.net
-- interface by itself. Disabled until validated jobs, permissions and real
-- operator/driver/vehicle permit records are provisioned.
local function currentTransportIdentity(src)
    if type(src) ~= 'number' or src < 1 then return nil end
    local cfg = ((Config or {}).MdtAccess or {}).Transportation or {}
    if cfg.Enabled ~= true or cfg.JobType ~= 'mechanic' then return nil end
    local job = ps.getJobName(src)
    local cid = ps.getIdentifier(src)
    if type(job) ~= 'string' or job == '' or type(cid) ~= 'string' or cid == ''
        or ps.getJobType(src) ~= 'mechanic' then return nil end
    local authorizedJob = false
    for _, allowed in ipairs(cfg.AllowedOperatorJobs or {}) do
        if allowed == job then authorizedJob = true break end
    end
    if not authorizedJob then return nil end
    local onDuty = ps.getJobDuty and ps.getJobDuty(src)
    if onDuty ~= true then return nil end

    -- The plate comes from the *server's observed vehicle*, never a caller
    -- payload, call metadata or spoofable client-provided vehicle registration.
    if type(GetPlayerPed) ~= 'function' or type(GetVehiclePedIsIn) ~= 'function'
        or type(GetVehicleNumberPlateText) ~= 'function' then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return nil end
    local plate = GetVehicleNumberPlateText(vehicle)
    if type(plate) ~= 'string' then return nil end
    plate = plate:match('^%s*(.-)%s*$')
    if plate == '' or #plate > 24 then return nil end
    return {job=job,cid=cid,plate=plate}
end

local function stillSameTransportIdentity(src, original)
    local now = currentTransportIdentity(src)
    return now and now.job == original.job and now.cid == original.cid
        and now.plate == original.plate
end

local function eligibility(src)
    local identity = currentTransportIdentity(src)
    if not identity then return false end
    local ok, row = pcall(MySQL.single.await, [[
        SELECT p.id AS permit_id
        FROM mdt_sadot_tow_permits p
        INNER JOIN mdt_government_business_licenses b
            ON b.id = p.business_license_id
            AND b.agency = p.licensing_agency
            AND b.jurisdiction = p.jurisdiction
            AND b.status = 'approved'
            AND b.revoked_at IS NULL
        INNER JOIN mdt_sadot_qualified_drivers d
            ON d.permit_id = p.id
            AND d.citizenid = ?
            AND d.employer_job = p.employer_job
            AND d.revoked_at IS NULL
            AND d.expires_at > UTC_TIMESTAMP()
        INNER JOIN mdt_sadot_permitted_vehicles v
            ON v.permit_id = p.id
            AND v.plate = ?
            AND v.revoked_at IS NULL
            AND v.expires_at > UTC_TIMESTAMP()
        WHERE p.employer_job = ?
            AND p.revoked_at IS NULL
            AND p.expires_at > UTC_TIMESTAMP()
        LIMIT 1
    ]], {identity.cid, identity.plate, identity.job})
    return ok and type(row) == 'table' and row.permit_id ~= nil
        and stillSameTransportIdentity(src, identity) == true
end

-- Strict read-only export for ps-dispatch's exclusive /511 claim path.
-- Missing table, missing license, off-duty job, changed identity or no
-- current permitted vehicle always denies, never permits by mechanic type.
exports('IsSadotTowEligible', function(source)
    return eligibility(tonumber(source)) == true
end)
