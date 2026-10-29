-- Stage 5 public-records intake: strictly citizen-owned, no disclosure or agency review.
local resourceName = tostring(GetCurrentResourceName())
local lastSubmitted = {}

local function isConfiguredReceivingAgency(agency)
    if type(agency) ~= 'string' or #agency > 64 then return false end
    local cfg = Config and Config.PublicServices or {}
    for _, location in ipairs(cfg.Locations or {}) do
        if location.agency == agency and type(location.services) == 'table' then
            for _, service in ipairs(location.services) do
                if service == 'public_records_request' then return true end
            end
        end
    end
    return false
end

local function cleanText(value, limit)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if #value == 0 or #value > limit then return nil end
    return value
end

ps.registerCallback(resourceName .. ':server:submitPublicRecordRequest', function(source, payload)
    local cid = ps.getIdentifier(source)
    if type(cid) ~= 'string' or cid == '' then return {success = false, error = 'Character unavailable'} end
    if type(payload) ~= 'table' then return {success = false, error = 'Invalid request'} end
    local agency = payload.agency
    if not isConfiguredReceivingAgency(agency)
        or not PublicServiceDeskAllows(source, agency, 'public_records_request') then
        return {success = false, error = 'Receiving records office is unavailable'}
    end
    local subject = cleanText(payload.subject, 160)
    local description = cleanText(payload.description, 4000)
    if not subject or not description then
        return {success = false, error = 'Subject or description is missing or too long'}
    end
    local now = GetGameTimer()
    if lastSubmitted[cid] and now - lastSubmitted[cid] >= 0 and now - lastSubmitted[cid] < 60000 then
        return {success = false, error = 'Please wait before submitting another request'}
    end
    -- Reserve the cooldown before the database yield to reduce duplicate submissions.
    lastSubmitted[cid] = now
    local ok, id = pcall(MySQL.insert.await, [[
        INSERT INTO mdt_public_record_requests (applicant_citizenid, agency, subject, description)
        VALUES (?, ?, ?, ?)
    ]], {cid, agency, subject, description})
    if not ok or type(id) ~= 'number' or id < 1 then
        lastSubmitted[cid] = nil
        return {success = false, error = 'Submission could not be saved'}
    end
    local number = ('PR-%s-%06d'):format(os.date('%Y'), id)
    local updated, count = pcall(MySQL.update.await,
        'UPDATE mdt_public_record_requests SET request_number = ? WHERE id = ? AND applicant_citizenid = ?',
        {number, id, cid})
    if not updated or type(count) ~= 'number' or count < 1 then
        return {success = false, error = 'Request saved but tracking number unavailable; contact the records office'}
    end
    -- Database inserts yield. Do not disclose the original applicant's
    -- tracking number if the client switched characters or left the counter.
    if ps.getIdentifier(source) ~= cid
        or not PublicServiceDeskAllows(source, agency, 'public_records_request') then
        return {success = false, error = 'Request saved; session changed before confirmation'}
    end
    return {success = true, requestNumber = number}
end)

ps.registerCallback(resourceName .. ':server:getMyPublicRecordRequests', function(source)
    local cid = ps.getIdentifier(source)
    if type(cid) ~= 'string' or cid == '' or not PublicServiceDeskAllows(source, nil, 'public_records_status') then return {} end
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT request_number, agency, subject, status, created_at
        FROM mdt_public_record_requests
        WHERE applicant_citizenid = ?
        ORDER BY created_at DESC, id DESC LIMIT 50
    ]], {cid})
    if not ok or ps.getIdentifier(source) ~= cid
        or not PublicServiceDeskAllows(source, nil, 'public_records_status') then return {} end
    return rows or {}
end)

-- Citizen may read only the response specifically addressed to their character.
ps.registerCallback(resourceName .. ':server:getMyPublicRecordsResponse', function(source, requestNumber)
    local cid = ps.getIdentifier(source)
    if type(cid) ~= 'string' or type(requestNumber) ~= 'string'
       or #requestNumber > 36 or not PublicServiceDeskAllows(source, nil, 'public_records_status') then return {success = false} end
    local ok, row = pcall(MySQL.single.await, [[
        SELECT r.request_number, r.agency, r.status, p.response_text, p.issued_at
        FROM mdt_public_record_requests r
        INNER JOIN mdt_public_record_responses p ON p.request_id = r.id
          AND p.recipient_citizenid = r.applicant_citizenid AND p.agency = r.agency
        WHERE r.request_number = ? AND r.applicant_citizenid = ?
          AND r.status IN ('approved', 'denied') LIMIT 1
    ]], {requestNumber, cid})
    if not ok or ps.getIdentifier(source) ~= cid
        or not PublicServiceDeskAllows(source, nil, 'public_records_status') or not row then
        return {success = false, error = 'Response unavailable'}
    end
    return {success = true, response = row}
end)
