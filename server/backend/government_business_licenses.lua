-- Stage 6: local business licenses are governed records, not a business
-- creator, property assessment, taxation, or SADOT towing certification.
local resourceName = tostring(GetCurrentResourceName())
local lastApplication = {}
local function policy()
    local config = Config and Config.MdtAccess or {}
    return config.GovernmentJobs or {}
end
local function localJurisdiction(job)
    local jurisdiction = type(job) == 'string' and policy()[job]
    if type(jurisdiction) ~= 'string' or jurisdiction == 'state'
        or type(GovernmentJurisdictionContains) ~= 'function'
        or not GovernmentJurisdictionContains('state',jurisdiction) then
        return nil
    end
    return jurisdiction
end
local function clean(value, max)
    if type(value) ~= 'string' then return nil end
    local text = value:match('^%s*(.-)%s*$')
    if #text < 1 or #text > max then return nil end
    return text
end
local function idNumber(value)
    local v=tonumber(value)
    return v and v >= 1 and v <= 9007199254740991 and v%1==0 and v or nil
end
local function txReady()
    return type(MySQL)=='table' and type(rawget(MySQL,'startTransaction'))=='function'
end
local function affected(value)
    return type(value)=='table' and tonumber(value.affectedRows)==1
end
local function staff(source)
    if type(GetGovernmentBusinessLicenseAccess)~='function' then return nil end
    local ok, data=pcall(GetGovernmentBusinessLicenseAccess, source)
    if not ok or type(data)~='table' or type(data.citizenid)~='string'
        or type(data.agency)~='string' or type(data.jurisdiction)~='string'
        or policy()[data.agency]~=data.jurisdiction then return nil end
    if not (data.canReview == true or data.canIssue == true or data.hasStateOversight == true) then return nil end
    return data
end
local function sameStaff(source, data)
    local current=staff(source)
    return current and current.citizenid==data.citizenid
        and current.agency==data.agency
        and current.jurisdiction==data.jurisdiction
        and current.canReview==data.canReview and current.canIssue==data.canIssue
        and current.hasStateOversight==data.hasStateOversight
end

-- The counter determines the receiving authority. The caller cannot choose
-- an arbitrary government job and route a confidential application there.
ps.registerCallback(resourceName..':server:applyForBusinessLicense', function(source, payload)
    local citizenid=ps.getIdentifier(source)
    if type(citizenid)~='string' or citizenid=='' or type(payload)~='table' then
        return {success=false,error='Character or application unavailable'}
    end
    local agency=payload.agency
    local jurisdiction=localJurisdiction(agency)
    if not jurisdiction or not PublicServiceDeskAllows(source,agency,'business_license_apply') then
        return {success=false,error='Use an authorized local licensing counter'}
    end
    local name=clean(payload.name,160)
    local businessType=clean(payload.businessType,80)
    local description=clean(payload.description,4000)
    local propertyReference=payload.propertyReference == '' and nil or payload.propertyReference
    if propertyReference~=nil then propertyReference=clean(propertyReference,120) end
    if not name or not businessType or not description
        or (payload.propertyReference~=nil and payload.propertyReference~=''
            and not propertyReference) then
        return {success=false,error='Complete all valid application fields'}
    end
    local now=GetGameTimer()
    if lastApplication[citizenid] and now-lastApplication[citizenid]>=0
        and now-lastApplication[citizenid]<60000 then
        return {success=false,error='Please wait before another application'}
    end
    if not txReady() then return {success=false,error='Licensing transaction unavailable'} end
    lastApplication[citizenid]=now
    local saved
    local ok, committed=pcall(MySQL.startTransaction,function(query)
        if ps.getIdentifier(source)~=citizenid
            or not PublicServiceDeskAllows(source,agency,'business_license_apply') then return false end
        local insert=query([[
            INSERT INTO mdt_government_business_licenses
                (owner_citizenid,agency,jurisdiction,business_name,business_type,
                 description,property_reference)
            VALUES (?,?,?,?,?,?,?)
        ]],{citizenid,agency,jurisdiction,name,businessType,description,propertyReference})
        if not affected(insert) or not idNumber(insert.insertId) then return false end
        saved=insert.insertId
        local audit=query([[
            INSERT INTO mdt_government_business_license_audit
                (application_id,agency,actor_citizenid,action,reason)
            VALUES (?,?,?,'submitted','Citizen application')
        ]],{saved,agency,citizenid})
        if not affected(audit) then return false end
        return ps.getIdentifier(source)==citizenid
            and PublicServiceDeskAllows(source,agency,'business_license_apply')
    end)
    if not ok or committed~=true then
        -- Unique key protects an owner from accidentally duplicating the
        -- same business under the same local authority.
        return {success=false,error='Application was not saved; check for an existing application'}
    end
    if ps.getIdentifier(source)~=citizenid
        or not PublicServiceDeskAllows(source,agency,'business_license_apply') then
        return {success=false,error='Application saved but your session changed before confirmation'}
    end
    return {success=true,applicationId=saved}
end)

ps.registerCallback(resourceName..':server:getMyBusinessLicenseApplications',function(source)
    local cid=ps.getIdentifier(source)
    if type(cid)~='string' or cid=='' or
        not PublicServiceDeskAllows(source,nil,'business_license_status') then
        return {success=false,error='Visit a business licensing counter'}
    end
    local ok,rows=pcall(MySQL.query.await,[[
        SELECT id,agency,jurisdiction,business_name,business_type,status,
               license_number,decision_reason,created_at,issued_at
        FROM mdt_government_business_licenses
        WHERE owner_citizenid = ? ORDER BY created_at DESC,id DESC LIMIT 100
    ]],{cid})
    if not ok or ps.getIdentifier(source)~=cid
        or not PublicServiceDeskAllows(source,nil,'business_license_status') then
        return {success=false,error='Licensing counter access changed'}
    end
    return {success=true,applications=rows or {}}
end)

-- Default to own-government records. State oversight is read-only with
-- explicit grant. Local state/county/municipal hierarchy does not itself
-- grant an employee access to neighboring unpublished applications.
ps.registerCallback(resourceName..':server:getGovernmentBusinessLicenses',function(source,payload)
    local access=staff(source)
    if not access then return {success=false,error='Licensing staff access denied'} end
    local target=type(payload)=='table' and payload.agency or nil
    target=target or access.agency
    if type(target)~='string' or not policy()[target] then
        return {success=false,error='Invalid licensing authority'}
    end
    if target~=access.agency and (access.agency~='sagov'
        or access.hasStateOversight~=true or not localJurisdiction(target)) then
        return {success=false,error='Other agency applications are private'}
    end
    local page=type(payload)=='table' and tonumber(payload.page or 0) or 0
    if not page or page<0 or page>200 or page%1~=0 then
        return {success=false,error='Invalid page'}
    end
    local ok,rows=pcall(MySQL.query.await,[[
        SELECT id,agency,jurisdiction,owner_citizenid,business_name,
               business_type,description,property_reference,status,version,
               license_number,reviewer_citizenid,decision_reason,created_at,issued_at
        FROM mdt_government_business_licenses
        WHERE agency = ?
        ORDER BY CASE WHEN status IN ('submitted','under_review') THEN 0 ELSE 1 END,
                 created_at ASC,id ASC
        LIMIT ? OFFSET ?
    ]],{target,51,page*50})
    if not ok or not sameStaff(source,access) then
        return {success=false,error='Licensing staff access changed'}
    end
    rows=type(rows)=='table' and rows or {}
    local more=#rows>50
    if more then rows[#rows]=nil end
    return {success=true,applications=rows,hasMore=more,page=page,
        agency=target,canReview=target==access.agency and access.canReview==true,
        canIssue=target==access.agency and access.canIssue==true}
end)

-- Decisions use a locked row, version check, employing government ownership,
-- and rollback if any audit/authorization step fails.
ps.registerCallback(resourceName..':server:decideGovernmentBusinessLicense',function(source,payload)
    local access=staff(source)
    if not access or type(payload)~='table' then
        return {success=false,error='Licensing officer access denied'}
    end
    local id=idNumber(payload.id)
    local version=idNumber(payload.version)
    local action=payload.action
    local reason=clean(payload.reason,1000)
    if not id or not version or not reason
        or (action~='under_review' and action~='approved'
            and action~='denied' and action~='suspended' and action~='revoked') then
        return {success=false,error='Invalid licensing decision'}
    end
    if action=='under_review' or action=='denied' then
        if access.canReview~=true then return {success=false,error='Review permission required'} end
    elseif access.canIssue~=true then
        return {success=false,error='License issuance permission required'}
    end
    if not localJurisdiction(access.agency) or not txReady() then
        return {success=false,error='Local licensing transaction unavailable'}
    end
    local transitions={
        under_review='submitted',approved='under_review',
        denied='under_review',suspended='approved',revoked='suspended',
    }
    local previous=transitions[action]
    local ok,committed=pcall(MySQL.startTransaction,function(query)
        local rows=query([[
            SELECT status,version,jurisdiction FROM mdt_government_business_licenses
            WHERE id = ? AND agency = ? FOR UPDATE
        ]],{id,access.agency})
        local row=type(rows)=='table' and rows[1] or nil
        if not row or row.status~=previous or tonumber(row.version)~=version
            or row.jurisdiction~=access.jurisdiction
            or not sameStaff(source,access) then return false end
        local changed
        if action=='approved' then
            changed=query([[
                UPDATE mdt_government_business_licenses
                SET status='approved',version=version+1,reviewer_citizenid=?,
                    decision_reason=?,issued_at=UTC_TIMESTAMP(),
                    license_number=CONCAT('SA-BIZ-',LPAD(id,9,'0'))
                WHERE id=? AND agency=? AND jurisdiction=?
                    AND status='under_review' AND version=?
            ]],{access.citizenid,reason,id,access.agency,access.jurisdiction,version})
        elseif action=='revoked' then
            changed=query([[
                UPDATE mdt_government_business_licenses
                SET status='revoked',version=version+1,reviewer_citizenid=?,
                    decision_reason=?,revoked_at=UTC_TIMESTAMP()
                WHERE id=? AND agency=? AND jurisdiction=?
                    AND status='suspended' AND version=?
            ]],{access.citizenid,reason,id,access.agency,access.jurisdiction,version})
        else
            changed=query([[
                UPDATE mdt_government_business_licenses
                SET status=?,version=version+1,reviewer_citizenid=?,decision_reason=?
                WHERE id=? AND agency=? AND jurisdiction=?
                    AND status=? AND version=?
            ]],{action,access.citizenid,reason,id,access.agency,
                  access.jurisdiction,previous,version})
        end
        if not affected(changed) then return false end
        local audit=query([[
            INSERT INTO mdt_government_business_license_audit
                (application_id,agency,actor_citizenid,action,reason)
            VALUES (?,?,?,?,?)
        ]],{id,access.agency,access.citizenid,action,reason})
        return affected(audit) and sameStaff(source,access)==true
    end)
    if not ok or committed~=true then
        return {success=false,error='License decision denied or stale; refresh'}
    end
    return {success=true}
end)
