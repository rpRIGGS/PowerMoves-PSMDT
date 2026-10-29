-- Stage 6 real assessor callbacks against in-memory transactions.
-- No housing property is mutated: PS Housing retains for_sale control.
local callbacks={}
local actor={cid='ASSESSOR-A',job='sagov',grade=4,assess=true,view=true}
local homes={[77]={property_id=77,street='Paleto',region='Blaine',for_sale=0}}
local records,audits={},{}
local failAudit=false
local switchActorDuringAudit=false
local function snapshot()
    local copy={}
    for id,r in pairs(records) do
        copy[id]={}
        for k,v in pairs(r) do copy[id][k]=v end
    end
    return copy,#audits
end
local function sql(query,args)
    if query:find('SELECT property_id FROM properties',1,true) then
        return homes[args[1]] and {{property_id=args[1]}} or {}
    end
    if query:find('INSERT INTO mdt_government_property_assessments',1,true) then
        local id=args[1]
        if records[id] then return {affectedRows=0} end
        records[id]={property_id=id,jurisdiction=args[2],property_type=args[3],
            assessed_value=nil,government_owned=0,tax_exempt=0,
            status='pending',version=1}
        return {affectedRows=1}
    end
    if query:find('SELECT property_id,jurisdiction,property_type,assessed_value',1,true) then
        local row=records[args[1]]
        return row and {row} or {}
    end
    if query:find('UPDATE mdt_government_property_assessments',1,true) then
        local approved=query:find("SET status='approved'",1,true)~=nil
        local id=approved and args[8] or args[4]
        local row=records[id]
        local version=approved and args[9] or args[6]
        if not row or row.version~=version or row.status~='pending' and approved then return {affectedRows=0} end
        if approved then
            row.status='approved';row.assessed_value=args[1];row.jurisdiction=args[2]
            row.property_type=args[3];row.government_owned=args[4];row.tax_exempt=args[5]
        else
            if row.status~=args[5] then return {affectedRows=0} end
            row.status=args[1]
        end
        row.version=row.version+1
        return {affectedRows=1}
    end
    if query:find('INSERT INTO mdt_government_property_assessment_audit',1,true) then
        if failAudit then return {affectedRows=0} end
        audits[#audits+1]={property_id=args[1],after=args[#args],before=args[#args-1]}
        if switchActorDuringAudit then actor.cid='ASSESSOR-B';switchActorDuringAudit=false end
        return {affectedRows=1}
    end
    error('Unexpected assessor SQL: '..query)
end
local env=setmetatable({
    Config={MdtAccess={GovernmentJurisdictions={
        state={label='San Andreas'},blaine_county={label='Blaine',parent='state'},
        los_santos_county={label='LS County',parent='state'},
        los_santos_city={label='Los Santos',parent='los_santos_county'}
    }}},
    GetCurrentResourceName=function()return 'ps-mdt'end,
    GetGovernmentPropertyAssessorAccess=function()
        if actor.job~='sagov' then return nil end
        return {citizenid=actor.cid,agency=actor.job,
            canAssess=actor.assess,canView=actor.view}
    end,
    ps={registerCallback=function(name,fn)callbacks[name]=fn end},
    json={encode=function(value)
        return tostring(value.status)..':'..tostring(value.assessed_value)
            ..':'..tostring(value.tax_exempt)..':'..tostring(value.jurisdiction)
    end},
    exports=function(_,fn)env.assessExport=fn end,
    MySQL={
        query={await=function(query,args)
            local rows={}
            for id,r in pairs(records) do
                rows[#rows+1]={
                    property_id=id,street=homes[id].street,region=homes[id].region,
                    for_sale=homes[id].for_sale,status=r.status,version=r.version,
                    jurisdiction=r.jurisdiction,property_type=r.property_type,
                    assessed_value=r.assessed_value,tax_exempt=r.tax_exempt,
                    government_owned=r.government_owned}
            end
            return rows
        end},
        single={await=function(_,args)
            return records[args[1]]
        end},
        startTransaction=function(fn)
            local before,count=snapshot()
            local ok,result=pcall(fn,sql)
            if not ok or result~=true then
                records=before
                while #audits>count do table.remove(audits) end
                return false
            end
            return true
        end
    }
},{__index=_G})
assert(loadfile('server/backend/government_jurisdiction_policy.lua','t',env))()
assert(loadfile('server/backend/government_property_assessments.lua','t',env))()
local function call(name,data)
    return assert(callbacks['ps-mdt:server:'..name],name)(1,data)
end
assert(not call('queueGovernmentPropertyAssessment',{
    propertyId=999,jurisdiction='blaine_county',propertyType='commercial'
}).success)
assert(not call('queueGovernmentPropertyAssessment',{
    propertyId=77,jurisdiction='state',propertyType='commercial'
}).success)
assert(call('queueGovernmentPropertyAssessment',{
    propertyId=77,jurisdiction='blaine_county',propertyType='commercial'
}).success)
assert(records[77].status=='pending' and #audits==1)
assert(not call('queueGovernmentPropertyAssessment',{
    propertyId=77,jurisdiction='blaine_county',propertyType='commercial'
}).success)
assert(env.assessExport(77)==false,'Unassessed property cannot pass assessor approval')
local q=call('getGovernmentPropertyAssessments',{page=0})
assert(q.success and #q.assessments==1 and #q.jurisdictions==3)
local result={propertyId=77,version=1,action='approved',reason='Tax review',
    jurisdiction='blaine_county',propertyType='commercial',assessedValue=250000,
    governmentOwned=true,taxExempt=false}
assert(call('decideGovernmentPropertyAssessment',result).success)
assert(records[77].government_owned==1 and records[77].tax_exempt==0,
    'Government ownership must never imply exemption')
assert(env.assessExport(77)==true)
assert(not call('decideGovernmentPropertyAssessment',result).success,
    'Stale approval version cannot overwrite')
assert(call('decideGovernmentPropertyAssessment',{
    propertyId=77,version=2,action='reopen',reason='New appraisal'
}).success)
assert(records[77].status=='pending')
failAudit=true
assert(not call('decideGovernmentPropertyAssessment',{
    propertyId=77,version=3,action='approved',reason='Audit unavailable',
    jurisdiction='los_santos_city',propertyType='residential',
    assessedValue=100000,governmentOwned=true,taxExempt=true
}).success)
assert(records[77].status=='pending' and records[77].tax_exempt==0,
    'Failed audit must roll back new exemption')
failAudit=false
switchActorDuringAudit=true
assert(not call('decideGovernmentPropertyAssessment',{
    propertyId=77,version=3,action='approved',reason='Identity changed',
    jurisdiction='blaine_county',propertyType='commercial',assessedValue=200000,
    governmentOwned=false,taxExempt=false
}).success)
assert(records[77].status=='pending')
actor.cid='ASSESSOR-A'
actor.assess=false
assert(not call('decideGovernmentPropertyAssessment',{
    propertyId=77,version=3,action='rejected',reason='No permission'
}).success)
assert(call('getGovernmentPropertyAssessments',{page=0}).success)
print('PASS Stage 6 assessor jurisdiction, no automatic exemptions, audited rollback, identity checks')
