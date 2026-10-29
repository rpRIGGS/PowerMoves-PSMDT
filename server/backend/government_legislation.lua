-- Stage 6 SAGOV legislative register and official recorded votes.
-- Recording votes does not determine the jurisdiction's quorum. An expressly
-- authorized certifying role records outcomes under the server's RP rules.
local resourceName=tostring(GetCurrentResourceName())
local function acl(source)
    if type(GetGovernmentLegislationAccess)~='function' then return nil end
    local ok,a=pcall(GetGovernmentLegislationAccess,source)
    local jobs=((Config or {}).MdtAccess or {}).GovernmentJobs or {}
    if not ok or type(a)~='table' or type(a.citizenid)~='string'
        or type(a.agency)~='string' or jobs[a.agency]~=a.jurisdiction then return nil end
    return a
end
local function same(source,initial)
    local current=acl(source)
    return current and current.citizenid==initial.citizenid
        and current.agency==initial.agency
        and current.jurisdiction==initial.jurisdiction
        and current.canDraft==initial.canDraft
        and current.canVote==initial.canVote
        and current.canCertify==initial.canCertify
        and current.canPublish==initial.canPublish
        and current.hasStateOversight==initial.hasStateOversight
end
local function checkTx()
    return type(MySQL)=='table'
        and type(rawget(MySQL,'startTransaction'))=='function'
end
local function affected(x)
    return type(x)=='table' and tonumber(x.affectedRows)==1
end
local function number(value,min,max)
    local v=tonumber(value)
    return v and v%1==0 and v>=min and v<=max and v or nil
end
local function clean(x,max)
    if type(x)~='string' then return nil end
    x=x:match('^%s*(.-)%s*$')
    return #x>0 and #x<=max and x or nil
end
local function validMeasureType(area,measureType)
    if area=='state' then return measureType=='state_law' end
    local jurisdictions=((Config or {}).MdtAccess or {}).GovernmentJurisdictions or {}
    if not jurisdictions[area] then return false end
    if area:find('county',1,true) then return measureType=='county_ordinance' end
    return measureType=='municipal_code'
end
local function canInspect(viewer,row)
    if type(CanViewGovernmentJurisdictionRecord)~='function' then return false end
    if row.agency~=viewer.agency and row.status~='published'
        and (viewer.agency~='sagov' or viewer.hasStateOversight~=true) then
        return false
    end
    return CanViewGovernmentJurisdictionRecord(
        viewer.agency,row.jurisdiction,row.status=='published',viewer.hasStateOversight==true)
end
local function transacted(source,access,fn,errorMessage)
    if not checkTx() then return {success=false,error='Legislative transaction support unavailable'} end
    local ok,committed=pcall(MySQL.startTransaction,function(query)
        if not same(source,access) then return false end
        return fn(query)==true and same(source,access)==true
    end)
    if not ok or committed~=true then
        return {success=false,error=errorMessage or 'Legislative record changed; refresh'}
    end
    return {success=true}
end
local function audit(query,id,access,action,reason)
    return affected(query([[
        INSERT INTO mdt_government_legislation_audit
            (measure_id,agency,actor_citizenid,action,reason)
        VALUES (?,?,?,?,?)
    ]],{id,access.agency,access.citizenid,action,reason}))
end

ps.registerCallback(resourceName..':server:getGovernmentLegislation',function(source,payload)
    local access=acl(source)
    if not access then return {success=false,error='Legislative access denied'} end
    local page=number(type(payload)=='table' and payload.page or 0,0,200)
    if not page then return {success=false,error='Invalid legislative page'} end
    local oversight=access.agency=='sagov' and access.hasStateOversight==true and 1 or 0
    local ok,rows=pcall(MySQL.query.await,[[
        SELECT id,agency,jurisdiction,measure_type,title,body,status,
               version,sponsor_citizenid,certified_by_citizenid,
               certification_reason,certified_at,published_at,updated_at
        FROM mdt_government_legislation
        WHERE status='published' OR agency=? OR ?=1
        ORDER BY updated_at DESC,id DESC LIMIT ? OFFSET ?
    ]],{access.agency,oversight,51,page*50})
    if not ok or not same(source,access) then
        return {success=false,error='Legislative access changed'}
    end
    rows=type(rows)=='table' and rows or {}
    local more=#rows>50
    if more then rows[#rows]=nil end
    local output={}
    for _,row in ipairs(rows) do
        if canInspect(access,row) then
            if row.agency~=access.agency and row.status=='published' then
                output[#output+1]={id=row.id,agency=row.agency,
                    jurisdiction=row.jurisdiction,measure_type=row.measure_type,
                    title=row.title,body=row.body,status=row.status,
                    published_at=row.published_at,updated_at=row.updated_at}
            else output[#output+1]=row end
        end
    end
    return {success=true,measures=output,hasMore=more,page=page,
        agency=access.agency,canDraft=access.canDraft==true,
        canVote=access.canVote==true,canCertify=access.canCertify==true,
        canPublish=access.canPublish==true}
end)

ps.registerCallback(resourceName..':server:createGovernmentMeasure',function(source,data)
    local access=acl(source)
    if not access or access.canDraft~=true or type(data)~='table' then
        return {success=false,error='Legislative drafting denied'}
    end
    local title=clean(data.title,180)
    local body=clean(data.body,10000)
    if not title or not body or not validMeasureType(access.jurisdiction,data.measureType) then
        return {success=false,error='Invalid measure type or content'}
    end
    local result=transacted(source,access,function(query)
        local inserted=query([[
            INSERT INTO mdt_government_legislation
                (agency,jurisdiction,measure_type,title,body,sponsor_citizenid)
            VALUES (?,?,?,?,?,?)
        ]],{access.agency,access.jurisdiction,data.measureType,
            title,body,access.citizenid})
        local id=type(inserted)=='table' and number(inserted.insertId,1,9007199254740991)
        return affected(inserted) and id and audit(query,id,access,'created','Draft created')
    end,'Legislative draft not saved')
    return result
end)

ps.registerCallback(resourceName..':server:editGovernmentMeasure',function(source,data)
    local access=acl(source)
    if not access or access.canDraft~=true or type(data)~='table' then
        return {success=false,error='Legislative editing denied'}
    end
    local id=number(data.id,1,9007199254740991)
    local version=number(data.version,1,2147483647)
    local title=clean(data.title,180)
    local body=clean(data.body,10000)
    if not id or not version or not title or not body then
        return {success=false,error='Invalid draft revision'}
    end
    return transacted(source,access,function(query)
        local rows=query([[
            SELECT status,version FROM mdt_government_legislation
            WHERE id=? AND agency=? AND jurisdiction=? FOR UPDATE
        ]],{id,access.agency,access.jurisdiction})
        local row=type(rows)=='table' and rows[1]
        if not row or row.status~='draft' or tonumber(row.version)~=version then return false end
        local changed=query([[
            UPDATE mdt_government_legislation
            SET title=?,body=?,version=version+1
            WHERE id=? AND agency=? AND jurisdiction=? AND status='draft' AND version=?
        ]],{title,body,id,access.agency,access.jurisdiction,version})
        return affected(changed) and audit(query,id,access,'edited','Draft revised')
    end,'Draft version changed; refresh')
end)

local function changeStatus(source,data,role,action,from,to,reason)
    local access=acl(source)
    if not access or access[role]~=true or type(data)~='table' then
        return {success=false,error='Legislative role denied'}
    end
    local id=number(data.id,1,9007199254740991)
    local version=number(data.version,1,2147483647)
    local auditReason=clean(reason,1000)
    if not id or not version or not auditReason then
        return {success=false,error='Legislative reason or version required'}
    end
    return transacted(source,access,function(query)
        local rows=query([[
            SELECT status,version FROM mdt_government_legislation
            WHERE id=? AND agency=? AND jurisdiction=? FOR UPDATE
        ]],{id,access.agency,access.jurisdiction})
        local row=type(rows)=='table' and rows[1]
        if not row or row.status~=from or tonumber(row.version)~=version then return false end
        if action=='certified_adopted' or action=='certified_rejected' then
            -- Recorded votes are visible to the certifying official, but no
            -- hardcoded quorum or implied enactment is derived from totals.
            local totals=query([[
                SELECT COUNT(*) AS total,SUM(vote='yes') AS yes_votes
                FROM mdt_government_legislation_votes
                WHERE measure_id=? AND agency=?
            ]],{id,access.agency})
            local counts=type(totals)=='table' and totals[1]
            if not counts or (tonumber(counts.total) or 0)<1 then return false end
            if action=='certified_adopted' and (tonumber(counts.yes_votes) or 0)<1 then
                return false
            end
        end
        local changed
        if action=='certified_adopted' or action=='certified_rejected' then
            changed=query([[
                UPDATE mdt_government_legislation
                SET status=?,version=version+1,certified_by_citizenid=?,
                    certified_at=UTC_TIMESTAMP(),certification_reason=?
                WHERE id=? AND agency=? AND jurisdiction=? AND status=? AND version=?
            ]],{to,access.citizenid,auditReason,id,access.agency,
                access.jurisdiction,from,version})
        elseif action=='published' then
            changed=query([[
                UPDATE mdt_government_legislation
                SET status='published',version=version+1,published_at=UTC_TIMESTAMP()
                WHERE id=? AND agency=? AND jurisdiction=? AND status='adopted' AND version=?
            ]],{id,access.agency,access.jurisdiction,version})
        else
            changed=query([[
                UPDATE mdt_government_legislation SET status=?,version=version+1
                WHERE id=? AND agency=? AND jurisdiction=? AND status=? AND version=?
            ]],{to,id,access.agency,access.jurisdiction,from,version})
        end
        return affected(changed) and audit(query,id,access,action,auditReason)
    end,'Legislative transition denied or already changed')
end

ps.registerCallback(resourceName..':server:openGovernmentMeasureVote',function(source,data)
    return changeStatus(source,data,'canDraft','vote_opened','draft','voting',
        'Official vote opened')
end)
ps.registerCallback(resourceName..':server:certifyGovernmentMeasure',function(source,data)
    if type(data)~='table' or (data.outcome~='adopted' and data.outcome~='rejected') then
        return {success=false,error='Explicit outcome required'}
    end
    return changeStatus(source,data,'canCertify',
        'certified_'..data.outcome,'voting',data.outcome,data.reason)
end)
ps.registerCallback(resourceName..':server:publishGovernmentMeasure',function(source,data)
    return changeStatus(source,data,'canPublish','published','adopted','published',
        'Certified measure published')
end)

ps.registerCallback(resourceName..':server:castGovernmentOfficialVote',function(source,data)
    local access=acl(source)
    if not access or access.canVote~=true or type(data)~='table' then
        return {success=false,error='Official voter role required'}
    end
    local id=number(data.id,1,9007199254740991)
    local choice=data.choice
    if not id or (choice~='yes' and choice~='no' and choice~='abstain') then
        return {success=false,error='Invalid official vote'}
    end
    return transacted(source,access,function(query)
        local rows=query([[
            SELECT status FROM mdt_government_legislation
            WHERE id=? AND agency=? AND jurisdiction=? FOR UPDATE
        ]],{id,access.agency,access.jurisdiction})
        if type(rows)~='table' or not rows[1] or rows[1].status~='voting' then return false end
        -- UNIQUE(measure_id,voter_citizenid) is authoritative under races.
        local vote=query([[
            INSERT INTO mdt_government_legislation_votes
                (measure_id,agency,voter_citizenid,vote)
            VALUES (?,?,?,?)
        ]],{id,access.agency,access.citizenid,choice})
        return affected(vote) and audit(query,id,access,'vote_cast','Official vote recorded')
    end,'Vote denied or already recorded')
end)

ps.registerCallback(resourceName..':server:getGovernmentOfficialVotes',function(source,idValue)
    local access=acl(source)
    local id=number(type(idValue)=='table' and idValue.id or idValue,1,9007199254740991)
    if not access or not id then return {success=false,error='Vote access denied'} end
    local oversight=access.agency=='sagov' and access.hasStateOversight==true
    local ok,records=pcall(MySQL.query.await,[[
        SELECT v.voter_citizenid,v.vote,v.cast_at,m.agency,m.jurisdiction,m.status
        FROM mdt_government_legislation_votes v
        INNER JOIN mdt_government_legislation m
            ON m.id=v.measure_id AND m.agency=v.agency
        WHERE v.measure_id=? ORDER BY v.id ASC LIMIT 250
    ]],{id})
    if not ok or not same(source,access) then
        return {success=false,error='Vote access changed'}
    end
    local result={}
    for _,vote in ipairs(records or {}) do
        if vote.agency==access.agency or (oversight and
            type(GovernmentJurisdictionContains)=='function' and
            GovernmentJurisdictionContains('state',vote.jurisdiction)) then
            result[#result+1]={
                voter_citizenid=vote.voter_citizenid,
                vote=vote.vote,cast_at=vote.cast_at,
            }
        end
    end
    return {success=true,votes=result}
end)
