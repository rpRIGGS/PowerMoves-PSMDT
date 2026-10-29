-- Stage 6: government assessment register. PS Housing retains property
-- ownership/sale control. This module does not alter the housing DB or levy tax.
local resourceName=tostring(GetCurrentResourceName())
local categories={residential=true,commercial=true,agricultural=true,industrial=true}
local function validId(value)
    local id=tonumber(value)
    return id and id>=1 and id<=2147483647 and id%1==0 and id or nil
end
local function taxYear(value)
    local year=tonumber(value)
    return year and year>=2020 and year<=2100 and year%1==0 and year or nil
end
local function text(value,max)
    if type(value)~='string' then return nil end
    local s=value:match('^%s*(.-)%s*$')
    return #s>0 and #s<=max and s or nil
end
local function localArea(key)
    return type(key)=='string' and key~='state'
        and type(GovernmentJurisdictionContains)=='function'
        and GovernmentJurisdictionContains('state',key)==true
end
local function staff(source)
    if type(GetGovernmentPropertyAssessorAccess)~='function' then return nil end
    local ok,data=pcall(GetGovernmentPropertyAssessorAccess,source)
    if not ok or type(data)~='table'
        or type(data.citizenid)~='string' or data.citizenid=='' then return nil end
    if data.canAssess~=true and data.canView~=true then return nil end
    return data
end
local function sameStaff(source,access)
    local current=staff(source)
    return current and current.citizenid==access.citizenid
        and current.agency==access.agency
        and current.canAssess==access.canAssess
        and current.canView==access.canView
end
local function transactionReady()
    return type(MySQL)=='table'
        and type(rawget(MySQL,'startTransaction'))=='function'
end
local function changed(result)
    return type(result)=='table' and tonumber(result.affectedRows)==1
end
local function snapshot(row)
    if not row then return nil end
    return json.encode({
        status=row.status,jurisdiction=row.jurisdiction,tax_year=row.tax_year,
        property_owner_snapshot=row.property_owner_snapshot,
        property_type=row.property_type,assessed_value=row.assessed_value,
        government_owned=row.government_owned,tax_exempt=row.tax_exempt,
        exemption_reason=row.exemption_reason,
        version=row.version,
    })
end
local function validMoney(value)
    local v=tonumber(value)
    return v and v>=0 and v<=100000000000 and v%1==0 and v or nil
end

-- Per-property queue is only for authorized State Tax Assessor officials.
ps.registerCallback(resourceName..':server:getGovernmentPropertyAssessments',function(source,payload)
    local access=staff(source)
    if not access then return {success=false,error='Assessor access denied'} end
    local page=type(payload)=='table' and tonumber(payload.page or 0) or 0
    if not page or page<0 or page>200 or page%1~=0 then
        return {success=false,error='Invalid assessor queue page'}
    end
    local ok,rows=pcall(MySQL.query.await,[[
        SELECT a.property_id,a.jurisdiction,a.tax_year,a.property_type,a.assessed_value,
               a.government_owned,a.tax_exempt,a.exemption_reason,a.status,a.version,
               a.reviewed_by_citizenid,a.decision_reason,a.created_at,
               p.street,p.region,p.for_sale
        FROM mdt_government_property_assessments a
        INNER JOIN properties p ON p.property_id=a.property_id
        ORDER BY CASE WHEN a.status='pending' THEN 0 ELSE 1 END,
                 a.tax_year DESC,a.updated_at DESC,a.property_id DESC
        LIMIT ? OFFSET ?
    ]],{51,page*50})
    if not ok or not sameStaff(source,access) then
        return {success=false,error='Assessor access changed'}
    end
    rows=type(rows)=='table' and rows or {}
    local more=#rows>50
    if more then rows[#rows]=nil end
    local jurisdictions={}
    local cfg=((Config or {}).MdtAccess or {}).GovernmentJurisdictions or {}
    for key,value in pairs(cfg) do
        if localArea(key) then
            jurisdictions[#jurisdictions+1]={id=key,label=value.label or key}
        end
    end
    table.sort(jurisdictions,function(a,b)return a.id<b.id end)
    return {success=true,assessments=rows,page=page,hasMore=more,
        jurisdictions=jurisdictions,canAssess=access.canAssess==true}
end)

-- Manual intake for a property created by the existing PS Realtor/Housing.
-- The assessor checks the real PS Housing property ID, no arbitrary property
-- creation and no client-originated entity ownership assumptions.
ps.registerCallback(resourceName..':server:queueGovernmentPropertyAssessment',function(source,data)
    local access=staff(source)
    if not access or access.canAssess~=true or type(data)~='table' then
        return {success=false,error='Assessor role required'}
    end
    local id=validId(data.propertyId)
    local year=taxYear(data.taxYear)
    local area=data.jurisdiction
    local classification=data.propertyType
    if not id or not year or not localArea(area) or not categories[classification] then
        return {success=false,error='Invalid property, jurisdiction or classification'}
    end
    if not transactionReady() then return {success=false,error='Assessor transaction unavailable'} end
    local ok,committed=pcall(MySQL.startTransaction,function(query)
        local property=query('SELECT property_id,owner_citizenid FROM properties WHERE property_id=? LIMIT 1 FOR UPDATE',{id})
        if type(property)~='table' or not property[1] or not sameStaff(source,access) then return false end
        local inserted=query([[
            INSERT INTO mdt_government_property_assessments
                (property_id,jurisdiction,tax_year,property_type,
                 property_owner_snapshot,submitted_by_citizenid)
            VALUES (?,?,?,?,?,?)
        ]],{id,area,year,classification,property[1].owner_citizenid or '',access.citizenid})
        if not changed(inserted) then return false end
        local nextState={status='pending',jurisdiction=area,tax_year=year,
            property_owner_snapshot=property[1].owner_citizenid,
            property_type=classification,version=1,government_owned=0,tax_exempt=0}
        local audit=query([[
            INSERT INTO mdt_government_property_assessment_audit
                (property_id,jurisdiction,tax_year,actor_citizenid,action,
                 previous_status,new_status,reason,before_snapshot,after_snapshot)
            VALUES (?,?,?,?,'submitted',NULL,'pending','Assessment requested',NULL,?)
        ]],{id,area,year,access.citizenid,snapshot(nextState)})
        return changed(audit) and sameStaff(source,access)==true
    end)
    if not ok or committed~=true then
        return {success=false,error='Assessment queue failed; check whether property already exists in the queue'}
    end
    return {success=true,propertyId=id,jurisdiction=area,taxYear=year}
end)

ps.registerCallback(resourceName..':server:decideGovernmentPropertyAssessment',function(source,data)
    local access=staff(source)
    if not access or access.canAssess~=true or type(data)~='table' then
        return {success=false,error='Appointed assessor required'}
    end
    local id=validId(data.propertyId)
    local areaKey=data.jurisdiction
    local year=taxYear(data.taxYear)
    local version=validId(data.version)
    local action=data.action
    local reason=text(data.reason,1000)
    if not id or not year or not localArea(areaKey) or not version or not reason
        or (action~='approved' and action~='rejected' and action~='reopen') then
        return {success=false,error='Invalid assessment decision'}
    end
    local value,area,kind,owned,exempt,exemptionReason
    if action=='approved' then
        value=validMoney(data.assessedValue)
        area=data.jurisdiction
        kind=data.propertyType
        owned=data.governmentOwned
        exempt=data.taxExempt
        exemptionReason=exempt and text(data.exemptionReason,1000) or nil
        if not value or area~=areaKey or not categories[kind]
            or type(owned)~='boolean' or type(exempt)~='boolean'
            or (exempt and not exemptionReason) then
            return {success=false,error='Assessment requires value, classification and explicit exemption determination'}
        end
    end
    if not transactionReady() then return {success=false,error='Assessor transaction unavailable'} end
    local ok,committed=pcall(MySQL.startTransaction,function(query)
        local rows=query([[
            SELECT property_id,jurisdiction,tax_year,property_type,assessed_value,
                   government_owned,tax_exempt,exemption_reason,status,version,property_owner_snapshot
            FROM mdt_government_property_assessments
            WHERE property_id = ? AND jurisdiction = ? AND tax_year = ? FOR UPDATE
        ]],{id,areaKey,year})
        local record=type(rows)=='table' and rows[1] or nil
        if not record or tonumber(record.version)~=version or not sameStaff(source,access) then return false end
        local property=query('SELECT owner_citizenid FROM properties WHERE property_id=? LIMIT 1 FOR UPDATE',{id})
        if type(property)~='table' or not property[1] or
            (property[1].owner_citizenid or '')~=(record.property_owner_snapshot or '') then return false end
        local previous=record.status
        if action=='reopen' then
            if previous~='approved' and previous~='rejected' then return false end
        elseif previous~='pending' then return false end
        local before=snapshot(record)
        local after={
            status=action=='reopen' and 'pending' or action,
            tax_year=year,property_owner_snapshot=record.property_owner_snapshot,
            jurisdiction=action=='approved' and area or record.jurisdiction,
            property_type=action=='approved' and kind or record.property_type,
            assessed_value=action=='approved' and value or record.assessed_value,
            exemption_reason=action=='approved' and exemptionReason or record.exemption_reason,
            government_owned=action=='approved' and (owned and 1 or 0)
                or record.government_owned,
            tax_exempt=action=='approved' and (exempt and 1 or 0)
                or record.tax_exempt, version=version+1,
        }
        local result
        if action=='approved' then
            result=query([[
                UPDATE mdt_government_property_assessments
                SET status='approved',version=version+1,assessed_value=?,
                    property_type=?,government_owned=?,tax_exempt=?,
                    exemption_reason=?,
                    reviewed_by_citizenid=?,decision_reason=?
                WHERE property_id=? AND jurisdiction=? AND tax_year=?
                    AND status='pending' AND version=?
            ]],{value,kind,owned and 1 or 0,exempt and 1 or 0,
                exemptionReason or '',access.citizenid,reason,id,areaKey,year,version})
        else
            result=query([[
                UPDATE mdt_government_property_assessments
                SET status=?,version=version+1,reviewed_by_citizenid=?,
                    decision_reason=?
                WHERE property_id=? AND jurisdiction=? AND tax_year=?
                    AND status=? AND version=?
            ]],{after.status,access.citizenid,reason,id,areaKey,year,previous,version})
        end
        if not changed(result) then return false end
        local audit=query([[
            INSERT INTO mdt_government_property_assessment_audit
                (property_id,jurisdiction,tax_year,actor_citizenid,action,
                 previous_status,new_status,reason,before_snapshot,after_snapshot)
            VALUES (?,?,?,?,?,?,?,?,?,?)
        ]],{id,areaKey,year,access.citizenid,action,previous,after.status,
            reason,before,snapshot(after)})
        return changed(audit) and sameStaff(source,access)==true
    end)
    if not ok or committed~=true then
        return {success=false,error='Assessment changed or permission lost; refresh'}
    end
    return {success=true}
end)

-- Trusted server resource integration point for PS Housing's sale toggle.
-- Not wired into PS Housing until its fork is reviewed and tested separately.
exports('IsPropertyAssessmentApproved',function(propertyId,jurisdiction,yearValue)
    local id=validId(propertyId)
    local year=taxYear(yearValue)
    if not id or not year or not localArea(jurisdiction) then return false end
    local ok,row=pcall(MySQL.single.await,[[
        SELECT status FROM mdt_government_property_assessments
        WHERE property_id = ? AND jurisdiction = ? AND tax_year = ? LIMIT 1
    ]],{id,jurisdiction,year})
    return ok and type(row)=='table' and row.status=='approved'
end)
