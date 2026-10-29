-- Stage 5 records office: initial read-only review queue.
local resourceName = tostring(GetCurrentResourceName())

local function authorized(src)
    if not CheckAuth(src) then return nil end
    local cid = ps.getIdentifier(src)
    local job = ps.getJobName(src)
    local cfg = Config and Config.PublicServices
    local officers = cfg and cfg.RecordsOfficers
    if type(cid) ~= 'string' or type(job) ~= 'string' then return nil end
    if type(officers) ~= 'table' or type(officers[job]) ~= 'table' then return nil end
    if officers[job][cid] ~= true then return nil end
    if not PublicServiceDeskAllows(src, job, 'records_office') then return nil end
    return cid, job
end

-- Lightweight entitlement check while a staff member has the counter panel open.
-- Prevents a previously loaded request list lingering after leaving the desk.
ps.registerCallback(resourceName .. ':server:canUsePublicRecordsOffice', function(source)
    return {success = authorized(source) ~= nil}
end)

ps.registerCallback(resourceName .. ':server:getPublicRecordsOfficeQueue', function(source)
    local cid, agency = authorized(source)
    if not cid then return {success = false, error = 'Access denied'} end
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT id, request_number, agency, subject, description, status, created_at
        FROM mdt_public_record_requests WHERE agency = ?
        ORDER BY created_at DESC LIMIT 100
    ]], {agency})
    if not ok or authorized(source) ~= cid or ps.getJobName(source) ~= agency then
        return {success = false, error = 'Access changed'}
    end
    return {success = true, requests = rows or {}}
end)

-- Approved public replies are deliberately authored text, not raw case,
-- evidence, IA, report, or medical records.
-- The checked, row-locked transaction API is supported by oxmysql v2.12.0+.
-- Do not replace it with the older blind batch API: a zero-row UPDATE can
-- otherwise commit a partial decision. Fail closed and surface the dependency.
local warnedTransactionUnavailable = false
local function hasCheckedTransactions()
    if MySQL and type(MySQL.startTransaction) == 'function' then return true end
    if not warnedTransactionUnavailable then
        warnedTransactionUnavailable = true
        print('[ps-mdt] Stage 5 records office: requires oxmysql v2.12.0+ MySQL.startTransaction; review and publication are disabled')
    end
    return false
end

local function validId(value)
    local id = tonumber(value)
    return id and id >= 1 and id % 1 == 0 and id or nil
end

local function validText(value, maxLength)
    if type(value) ~= 'string' then return nil end
    local trimmed = value:match('^%s*(.-)%s*$')
    if #trimmed < 1 or #trimmed > maxLength then return nil end
    return trimmed
end

local function updatedExactlyOne(result)
    return type(result) == 'table' and tonumber(result.affectedRows) == 1
end

local function insertedExactlyOne(result)
    return type(result) == 'table' and tonumber(result.affectedRows) == 1
end

-- MySQL.startTransaction gives every statement the SAME connection and lets us
-- inspect affectedRows. The conventional batch API only returns a boolean
-- and can commit a transaction after a no-op UPDATE or INSERT ... SELECT.
ps.registerCallback(resourceName .. ':server:reviewPublicRecordsRequest', function(source, data)
    local cid, job = authorized(source)
    if not cid or type(data) ~= 'table' then return {success = false, error = 'Access denied'} end

    local id = validId(data.id)
    local action = data.action
    local reason = validText(data.reason, 1000)
    if not id or not reason or (action ~= 'under_review' and action ~= 'denied') then
        return {success = false, error = 'Invalid review decision'}
    end

    if not hasCheckedTransactions() then
        return {success = false, error = 'Records office transaction support unavailable'}
    end
    local previous = action == 'under_review' and 'submitted' or 'under_review'
    local ok, committed = pcall(MySQL.startTransaction, function(query)
        local rows = query([[
            SELECT status, applicant_citizenid FROM mdt_public_record_requests
            WHERE id = ? AND agency = ? FOR UPDATE
        ]], {id, job})
        if type(rows) ~= 'table' or not rows[1] or rows[1].status ~= previous then
            return false
        end
        if authorized(source) ~= cid or ps.getJobName(source) ~= job then return false end

        -- A denial includes a public-facing explanation addressed only to
        -- the original applicant. Never expose internal audit rows directly.
        if action == 'denied' then
            if type(rows[1].applicant_citizenid) ~= 'string'
                or rows[1].applicant_citizenid == '' then return false end
            local notice = query([[
                INSERT INTO mdt_public_record_responses
                    (request_id, agency, recipient_citizenid, response_text, issued_by_citizenid)
                VALUES (?, ?, ?, ?, ?)
            ]], {id, job, rows[1].applicant_citizenid, reason, cid})
            if not insertedExactlyOne(notice) then return false end
        end

        local changed = query([[
            UPDATE mdt_public_record_requests SET status = ?
            WHERE id = ? AND agency = ? AND status = ?
        ]], {action, id, job, previous})
        if not updatedExactlyOne(changed) then return false end

        local audit = query([[
            INSERT INTO mdt_public_record_request_audit
                (request_id, agency, actor_citizenid, action, reason)
            VALUES (?, ?, ?, ?, ?)
        ]], {id, job, cid, action, reason})
        if not insertedExactlyOne(audit) then return false end
        return true
    end)
    if not ok or committed ~= true then
        return {success = false, error = 'Request was not changed; refresh the records queue'}
    end
    return {success = true, status = action}
end)

ps.registerCallback(resourceName .. ':server:publishPublicRecordsResponse', function(source, data)
    local cid, job = authorized(source)
    if not cid or type(data) ~= 'table' then return {success = false, error = 'Access denied'} end
    local id = validId(data.id)
    local responseText = validText(data.response, 12000)
    if not id or not responseText then
        return {success = false, error = 'A valid public response is required'}
    end

    if not hasCheckedTransactions() then
        return {success = false, error = 'Records office transaction support unavailable'}
    end
    local ok, committed = pcall(MySQL.startTransaction, function(query)
        local rows = query([[
            SELECT applicant_citizenid, status FROM mdt_public_record_requests
            WHERE id = ? AND agency = ? FOR UPDATE
        ]], {id, job})
        local record = type(rows) == 'table' and rows[1] or nil
        if not record or record.status ~= 'under_review'
            or type(record.applicant_citizenid) ~= 'string' or record.applicant_citizenid == '' then
            return false
        end
        if authorized(source) ~= cid or ps.getJobName(source) ~= job then return false end

        local inserted = query([[
            INSERT INTO mdt_public_record_responses
                (request_id, agency, recipient_citizenid, response_text, issued_by_citizenid)
            VALUES (?, ?, ?, ?, ?)
        ]], {id, job, record.applicant_citizenid, responseText, cid})
        if not insertedExactlyOne(inserted) then return false end

        local changed = query([[
            UPDATE mdt_public_record_requests SET status = 'approved'
            WHERE id = ? AND agency = ? AND status = 'under_review'
        ]], {id, job})
        if not updatedExactlyOne(changed) then return false end

        local audit = query([[
            INSERT INTO mdt_public_record_request_audit
                (request_id, agency, actor_citizenid, action, reason)
            VALUES (?, ?, ?, 'approved', 'Public response issued')
        ]], {id, job, cid})
        if not insertedExactlyOne(audit) then return false end
        return true
    end)
    if not ok or committed ~= true then
        return {success = false, error = 'Response was not issued; refresh the records queue'}
    end
    return {success = true, status = 'approved'}
end)
