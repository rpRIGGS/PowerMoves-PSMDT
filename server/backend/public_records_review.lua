-- Stage 5 records-office review, agency audit, and applicant-scoped publication.
-- All staff actions require current job, MDT authorization and service-counter proximity.
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

ps.registerCallback(resourceName .. ':server:getPublicRecordsOfficeQueue', function(source, payload)
    local cid, agency = authorized(source)
    if not cid then return {success = false, error = 'Access denied'} end
    local page = type(payload) == 'table' and tonumber(payload.page) or 0
    if not page or page < 0 or page % 1 ~= 0 or page > 200 then
        return {success = false, error = 'Invalid queue page'}
    end
    local pageSize = 50
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT id, request_number, applicant_citizenid, assigned_to_citizenid,
               agency, subject, description, status, created_at
        FROM mdt_public_record_requests WHERE agency = ?
        ORDER BY CASE WHEN status IN ('submitted', 'under_review') THEN 0 ELSE 1 END,
                 created_at ASC, id ASC
        LIMIT ? OFFSET ?
    ]], {agency, pageSize + 1, page * pageSize})
    if not ok or authorized(source) ~= cid or ps.getJobName(source) ~= agency then
        return {success = false, error = 'Access changed'}
    end
    rows = type(rows) == 'table' and rows or {}
    local more = #rows > pageSize
    if more then rows[#rows] = nil end
    return {success = true, requests = rows, page = page, hasMore = more}
end)

-- Staff-only administrative decision history. The join rechecks request
-- ownership by the officer's actual employing agency on every retrieval.
ps.registerCallback(resourceName .. ':server:getPublicRecordRequestAudit', function(source, requestId)
    local cid, job = authorized(source)
    local id = tonumber(requestId)
    if not cid or not id or id < 1 or id % 1 ~= 0 then
        return {success = false, error = 'Records office access denied'}
    end
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT a.action, a.reason, a.actor_citizenid, a.created_at
        FROM mdt_public_record_request_audit a
        INNER JOIN mdt_public_record_requests r
            ON r.id = a.request_id AND r.agency = a.agency
        WHERE a.request_id = ? AND r.agency = ?
        ORDER BY a.created_at ASC, a.id ASC LIMIT 100
    ]], {id, job})
    if not ok or authorized(source) ~= cid or ps.getJobName(source) ~= job then
        return {success = false, error = 'Records office access changed'}
    end
    return {success = true, entries = rows or {}}
end)

-- Approved public replies are deliberately authored text, not raw case,
-- evidence, IA, report, or medical records.
-- The checked, row-locked transaction API is supported by oxmysql v2.12.0+.
-- Do not replace it with the older blind batch API: a zero-row UPDATE can
-- otherwise commit a partial decision. Fail closed and surface the dependency.
local warnedTransactionUnavailable = false
local function hasCheckedTransactions()
    -- Older oxmysql Lua libraries synthesize functions for unknown keys in
    -- the MySQL metatable. Only a raw method proves this API is installed.
    if type(MySQL) == 'table' and type(rawget(MySQL, 'startTransaction')) == 'function' then return true end
    if not warnedTransactionUnavailable then
        warnedTransactionUnavailable = true
        print('[ps-mdt] Stage 5 records office: requires oxmysql v2.12.0+ MySQL.startTransaction; review and publication are disabled')
    end
    return false
end

-- Warn during resource startup instead of discovering an incompatible
-- oxmysql installation only after a records officer attempts publication.
if type(CreateThread) == 'function' then
    CreateThread(function()
        Wait(1000)
        hasCheckedTransactions()
    end)
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
        if action == 'under_review' then
            local assigned = query([[
                UPDATE mdt_public_record_requests
                SET assigned_to_citizenid = ?, assigned_at = UTC_TIMESTAMP()
                WHERE id = ? AND agency = ? AND status = 'under_review'
            ]], {cid, id, job})
            if not updatedExactlyOne(assigned) then return false end
        end

        local audit = query([[
            INSERT INTO mdt_public_record_request_audit
                (request_id, agency, actor_citizenid, action, reason)
            VALUES (?, ?, ?, ?, ?)
        ]], {id, job, cid, action, reason})
        if not insertedExactlyOne(audit) then return false end
        -- The player may have moved or changed jobs while SQL was yielding.
        if authorized(source) ~= cid or ps.getJobName(source) ~= job then return false end
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
        -- The player may have moved or changed jobs while SQL was yielding.
        if authorized(source) ~= cid or ps.getJobName(source) ~= job then return false end
        return true
    end)
    if not ok or committed ~= true then
        return {success = false, error = 'Response was not issued; refresh the records queue'}
    end
    return {success = true, status = 'approved'}
end)

-- Explicit public-release copies are separate, manually reviewed documents.
-- These callbacks never load raw MDT case/report/evidence/medical material.
ps.registerCallback(resourceName .. ':server:getPublicReleaseCopiesForOfficer', function(source, requestId)
    local cid, job = authorized(source)
    local id = validId(requestId)
    if not cid or not id then return {success = false, error = 'Access denied'} end
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT c.id, c.title, c.public_text, c.issued_at, c.expires_at,
               c.revoked_at, c.revocation_reason
        FROM mdt_public_record_release_copies c
        INNER JOIN mdt_public_record_requests r
            ON r.id = c.request_id AND r.agency = c.agency
        WHERE c.request_id = ? AND r.agency = ? AND r.status = 'approved'
        ORDER BY c.id DESC LIMIT 20
    ]], {id, job})
    if not ok or authorized(source) ~= cid or ps.getJobName(source) ~= job then
        return {success = false, error = 'Access changed'}
    end
    return {success = true, copies = rows or {}}
end)

ps.registerCallback(resourceName .. ':server:issuePublicReleaseCopy', function(source, data)
    local cid, job = authorized(source)
    if not cid or type(data) ~= 'table' then return {success = false, error = 'Access denied'} end
    local id = validId(data.id)
    local title = validText(data.title, 160)
    local publicText = validText(data.publicText, 12000)
    local days = tonumber(data.expiresInDays)
    if not id or not title or not publicText
        or not days or days % 1 ~= 0 or days < 1 or days > 365 then
        return {success = false, error = 'Invalid release copy or expiry'}
    end
    if not hasCheckedTransactions() then
        return {success = false, error = 'Records office transaction support unavailable'}
    end

    local ok, committed = pcall(MySQL.startTransaction, function(query)
        local rows = query([[
            SELECT applicant_citizenid, status FROM mdt_public_record_requests
            WHERE id = ? AND agency = ? FOR UPDATE
        ]], {id, job})
        local request = type(rows) == 'table' and rows[1] or nil
        if not request or request.status ~= 'approved'
            or type(request.applicant_citizenid) ~= 'string'
            or request.applicant_citizenid == '' then return false end
        if authorized(source) ~= cid or ps.getJobName(source) ~= job then return false end

        local totalRows = query([[
            SELECT COUNT(*) AS total FROM mdt_public_record_release_copies
            WHERE request_id = ? AND agency = ?
        ]], {id, job})
        if type(totalRows) ~= 'table' or not totalRows[1]
            or not tonumber(totalRows[1].total)
            or tonumber(totalRows[1].total) >= 20 then return false end

        local copy = query([[
            INSERT INTO mdt_public_record_release_copies
                (request_id, agency, recipient_citizenid, title, public_text,
                 issued_by_citizenid, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? DAY))
        ]], {id, job, request.applicant_citizenid, title, publicText, cid, days})
        if not insertedExactlyOne(copy) then return false end

        local audit = query([[
            INSERT INTO mdt_public_record_request_audit
                (request_id, agency, actor_citizenid, action, reason)
            VALUES (?, ?, ?, 'release_issued', ?)
        ]], {id, job, cid, title})
        if not insertedExactlyOne(audit) then return false end
        if authorized(source) ~= cid or ps.getJobName(source) ~= job then return false end
        return true
    end)
    if not ok or committed ~= true then
        return {success = false, error = 'Copy not issued; refresh the request'}
    end
    return {success = true}
end)

ps.registerCallback(resourceName .. ':server:revokePublicReleaseCopy', function(source, data)
    local cid, job = authorized(source)
    if not cid or type(data) ~= 'table' then return {success = false, error = 'Access denied'} end
    local copyId = validId(data.copyId)
    local reason = validText(data.reason, 1000)
    if not copyId or not reason then return {success = false, error = 'Revocation reason required'} end
    if not hasCheckedTransactions() then
        return {success = false, error = 'Records office transaction support unavailable'}
    end
    local ok, committed = pcall(MySQL.startTransaction, function(query)
        local rows = query([[
            SELECT c.request_id, c.revoked_at
            FROM mdt_public_record_release_copies c
            INNER JOIN mdt_public_record_requests r
                ON r.id = c.request_id AND r.agency = c.agency
            WHERE c.id = ? AND r.agency = ? FOR UPDATE
        ]], {copyId, job})
        local copy = type(rows) == 'table' and rows[1] or nil
        if not copy or copy.revoked_at ~= nil then return false end
        if authorized(source) ~= cid or ps.getJobName(source) ~= job then return false end

        local updated = query([[
            UPDATE mdt_public_record_release_copies
            SET revoked_at = UTC_TIMESTAMP(), revoked_by_citizenid = ?,
                revocation_reason = ?
            WHERE id = ? AND agency = ? AND revoked_at IS NULL
        ]], {cid, reason, copyId, job})
        if not updatedExactlyOne(updated) then return false end
        local audit = query([[
            INSERT INTO mdt_public_record_request_audit
                (request_id, agency, actor_citizenid, action, reason)
            VALUES (?, ?, ?, 'release_revoked', ?)
        ]], {copy.request_id, job, cid, reason})
        if not insertedExactlyOne(audit) then return false end
        if authorized(source) ~= cid or ps.getJobName(source) ~= job then return false end
        return true
    end)
    if not ok or committed ~= true then
        return {success = false, error = 'Release copy could not be revoked'}
    end
    return {success = true}
end)
