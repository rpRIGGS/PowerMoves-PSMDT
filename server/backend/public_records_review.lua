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
    return cid, job
end

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

-- Administrative review only: this never releases source records.
ps.registerCallback(resourceName .. ':server:reviewPublicRecordsRequest', function(source, data)
    local cid, job = authorized(source)
    if not cid or type(data) ~= 'table' then return {success = false} end
    local id = tonumber(data.id)
    local action = data.action
    local note = data.reason
    if not id or id < 1 or id % 1 ~= 0 then return {success = false} end
    if action ~= 'under_review' and action ~= 'denied' then return {success = false} end
    if type(note) ~= 'string' then return {success = false} end
    note = note:match('^%s*(.-)%s*$')
    if #note < 1 or #note > 1000 then return {success = false} end
    local from = action == 'under_review' and 'submitted' or 'under_review'
    local found, current = pcall(MySQL.single.await,
        'SELECT status FROM mdt_public_record_requests WHERE id = ? AND agency = ? LIMIT 1',
        {id, job})
    if not found or not current or current.status ~= from then
        return {success = false, error = 'Request is unavailable or already processed'}
    end
    if authorized(source) ~= cid or ps.getJobName(source) ~= job then return {success = false} end
    local ok, committed = pcall(MySQL.transaction.await, {
        {query = 'UPDATE mdt_public_record_requests SET status = ? WHERE id = ? AND agency = ? AND status = ?',
         values = {action, id, job, from}},
        {query = [[INSERT INTO mdt_public_record_request_audit
         (request_id, agency, actor_citizenid, action, reason)
         SELECT id, agency, ?, ?, ? FROM mdt_public_record_requests
         WHERE id = ? AND agency = ? AND status = ? AND ROW_COUNT() = 1]],
         values = {cid, action, note, id, job, action}}
    })
    if not ok or not committed then return {success = false, error = 'Database error'} end
    return {success = true}
end)
