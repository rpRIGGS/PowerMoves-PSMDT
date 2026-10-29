-- Stage 6 SAGOV public notices. These are administrative notices, NOT law,
-- enacted ordinances, official vote results, business permits or case records.
local resourceName = tostring(GetCurrentResourceName())
local function noticeAccess(src)
    if type(GetGovernmentNoticeAccess) ~= 'function' then return nil end
    local ok, data = pcall(GetGovernmentNoticeAccess, src)
    if not ok or type(data) ~= 'table' or type(data.citizenid) ~= 'string'
        or type(data.agency) ~= 'string' or type(data.jurisdiction) ~= 'string' then
        return nil
    end
    local jobs = ((Config or {}).MdtAccess or {}).GovernmentJobs or {}
    if jobs[data.agency] ~= data.jurisdiction then return nil end
    return data
end

local function sameAccess(src, original)
    local current = noticeAccess(src)
    return current and current.citizenid == original.citizenid
        and current.agency == original.agency
        and current.jurisdiction == original.jurisdiction
        and current.canManage == original.canManage
        and current.canPublish == original.canPublish
        and current.hasStateOversight == original.hasStateOversight
end

local function checkedTransaction()
    return type(MySQL) == 'table' and
        type(rawget(MySQL, 'startTransaction')) == 'function'
end

local function clean(value, limit)
    if type(value) ~= 'string' then return nil end
    local result = value:match('^%s*(.-)%s*$')
    if #result == 0 or #result > limit then return nil end
    return result
end
local function integer(value, minimum, maximum)
    local num = tonumber(value)
    return num and num >= minimum and num <= maximum and num % 1 == 0 and num or nil
end
local function affected(result)
    return type(result) == 'table' and tonumber(result.affectedRows) == 1
end

-- Only published notices are visible outside the employing agency unless a
-- state official has the explicit notices-oversight grant. An invalid
-- jurisdiction hierarchy fails closed in all cases.
ps.registerCallback(resourceName .. ':server:getGovernmentNotices', function(source, payload)
    local access = noticeAccess(source)
    if not access then return {success=false, error='Government notice access denied'} end
    local page = integer(type(payload)=='table' and payload.page or 0, 0, 200)
    if not page then return {success=false, error='Invalid page'} end
    local stateOversight = access.agency == 'sagov'
        and access.hasStateOversight == true and 1 or 0
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT id, agency, jurisdiction, title, body, status, version,
               created_by_citizenid, published_by_citizenid, published_at, updated_at
        FROM mdt_government_notices
        WHERE status = 'published'
           OR (status = 'draft' AND agency = ?)
           OR (status = 'draft' AND ? = 1)
        ORDER BY CASE WHEN status = 'draft' THEN 0 ELSE 1 END,
                 updated_at DESC, id DESC
        LIMIT ? OFFSET ?
    ]], {access.agency, stateOversight, 51, page*50})
    if not ok or not sameAccess(source, access) then
        return {success=false, error='Notice access changed'}
    end
    rows = type(rows) == 'table' and rows or {}
    local more = #rows > 50
    if more then rows[#rows] = nil end
    local visible = {}
    for _, row in ipairs(rows) do
        local published = row.status == 'published'
        local scopeOK = (published or row.agency == access.agency
            or (stateOversight == 1 and access.agency == 'sagov'))
        if scopeOK and type(CanViewGovernmentJurisdictionRecord) == 'function'
            and CanViewGovernmentJurisdictionRecord(
                access.agency, row.jurisdiction, published, stateOversight == 1
            ) then
            visible[#visible+1] = row
        end
    end
    return {
        success=true, notices=visible, page=page, hasMore=more,
        canManage=access.canManage == true, canPublish=access.canPublish == true,
        agency=access.agency, jurisdiction=access.jurisdiction,
    }
end)

ps.registerCallback(resourceName .. ':server:createGovernmentNotice', function(source, payload)
    local access = noticeAccess(source)
    if not access or access.canManage ~= true or type(payload) ~= 'table' then
        return {success=false, error='Notice authoring denied'}
    end
    local title = clean(payload.title, 160)
    local body = clean(payload.body, 6000)
    if not title or not body then return {success=false, error='Invalid notice text'} end
    if not checkedTransaction() then return {success=false, error='Checked transactions unavailable'} end
    local noticeId
    local ok, committed = pcall(MySQL.startTransaction, function(query)
        if not sameAccess(source, access) then return false end
        local created = query([[
            INSERT INTO mdt_government_notices
                (agency, jurisdiction, title, body, status, created_by_citizenid)
            VALUES (?, ?, ?, ?, 'draft', ?)
        ]], {access.agency, access.jurisdiction, title, body, access.citizenid})
        if not affected(created) or not integer(created.insertId, 1, 9007199254740991) then
            return false
        end
        noticeId = created.insertId
        local audited = query([[
            INSERT INTO mdt_government_notice_audit
                (notice_id, agency, actor_citizenid, action, reason)
            VALUES (?, ?, ?, 'created', 'Draft created')
        ]], {noticeId, access.agency, access.citizenid})
        return affected(audited) and sameAccess(source, access) == true
    end)
    if not ok or committed ~= true then
        return {success=false, error='Draft was not saved'}
    end
    return {success=true, id=noticeId}
end)

ps.registerCallback(resourceName .. ':server:editGovernmentNotice', function(source, payload)
    local access = noticeAccess(source)
    if not access or access.canManage ~= true or type(payload) ~= 'table' then
        return {success=false, error='Notice editing denied'}
    end
    local id = integer(payload.id, 1, 9007199254740991)
    local version = integer(payload.version, 1, 2147483647)
    local title = clean(payload.title, 160)
    local body = clean(payload.body, 6000)
    if not id or not version or not title or not body then
        return {success=false, error='Invalid draft changes'}
    end
    if not checkedTransaction() then return {success=false, error='Checked transactions unavailable'} end
    local ok, committed = pcall(MySQL.startTransaction, function(query)
        local rows = query([[
            SELECT status, version FROM mdt_government_notices
            WHERE id = ? AND agency = ? FOR UPDATE
        ]], {id, access.agency})
        if type(rows) ~= 'table' or not rows[1]
            or rows[1].status ~= 'draft' or tonumber(rows[1].version) ~= version
            or not sameAccess(source, access) then return false end
        local changed = query([[
            UPDATE mdt_government_notices
            SET title = ?, body = ?, version = version + 1
            WHERE id = ? AND agency = ? AND status = 'draft' AND version = ?
        ]], {title, body, id, access.agency, version})
        if not affected(changed) then return false end
        local audit = query([[
            INSERT INTO mdt_government_notice_audit
                (notice_id, agency, actor_citizenid, action, reason)
            VALUES (?, ?, ?, 'edited', 'Draft revised')
        ]], {id, access.agency, access.citizenid})
        return affected(audit) and sameAccess(source, access) == true
    end)
    if not ok or committed ~= true then
        return {success=false, error='Draft changed or access revoked; refresh'}
    end
    return {success=true, version=version+1}
end)

ps.registerCallback(resourceName .. ':server:publishGovernmentNotice', function(source, payload)
    local access = noticeAccess(source)
    if not access or access.canPublish ~= true or type(payload) ~= 'table' then
        return {success=false, error='Notice publishing denied'}
    end
    local id = integer(payload.id, 1, 9007199254740991)
    local version = integer(payload.version, 1, 2147483647)
    if not id or not version then return {success=false, error='Invalid notice version'} end
    if not checkedTransaction() then return {success=false, error='Checked transactions unavailable'} end
    local ok, committed = pcall(MySQL.startTransaction, function(query)
        local rows = query([[
            SELECT status, version, jurisdiction FROM mdt_government_notices
            WHERE id = ? AND agency = ? FOR UPDATE
        ]], {id, access.agency})
        if type(rows) ~= 'table' or not rows[1]
            or rows[1].status ~= 'draft' or tonumber(rows[1].version) ~= version
            or rows[1].jurisdiction ~= access.jurisdiction
            or not sameAccess(source, access) then return false end
        local changed = query([[
            UPDATE mdt_government_notices
            SET status = 'published', version = version + 1,
                published_by_citizenid = ?, published_at = UTC_TIMESTAMP()
            WHERE id = ? AND agency = ? AND jurisdiction = ?
                AND status = 'draft' AND version = ?
        ]], {access.citizenid, id, access.agency, access.jurisdiction, version})
        if not affected(changed) then return false end
        local audit = query([[
            INSERT INTO mdt_government_notice_audit
                (notice_id, agency, actor_citizenid, action, reason)
            VALUES (?, ?, ?, 'published', 'Public notice published')
        ]], {id, access.agency, access.citizenid})
        return affected(audit) and sameAccess(source, access) == true
    end)
    if not ok or committed ~= true then
        return {success=false, error='Notice already changed or publishing denied'}
    end
    return {success=true}
end)

-- Civilian public kiosk: never sends draft data or unpublished audit entries.
-- No standalone slash command or unrestricted remote public callback.
ps.registerCallback(resourceName .. ':server:getPublicGovernmentNotices', function(source, payload)
    if type(PublicServiceDeskAllows) ~= 'function'
        or not PublicServiceDeskAllows(source, nil, 'government_notices') then
        return {success=false, error='Public notices counter unavailable'}
    end
    local page = integer(type(payload)=='table' and payload.page or 0, 0, 200)
    if not page then return {success=false, error='Invalid public notice page'} end
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT id, agency, jurisdiction, title, body, published_at
        FROM mdt_government_notices
        WHERE status = 'published'
        ORDER BY published_at DESC, id DESC
        LIMIT ? OFFSET ?
    ]], {21, page*20})
    if not ok or not PublicServiceDeskAllows(source, nil, 'government_notices') then
        return {success=false, error='Public counter access changed'}
    end
    rows = type(rows) == 'table' and rows or {}
    local more = #rows > 20
    if more then rows[#rows] = nil end
    local visible = {}
    for _, row in ipairs(rows) do
        if type(CanViewGovernmentJurisdictionRecord) == 'function'
            and CanViewGovernmentJurisdictionRecord(nil, row.jurisdiction, true, false) then
            visible[#visible+1] = row
        end
    end
    return {success=true, notices=visible, hasMore=more, page=page}
end)
