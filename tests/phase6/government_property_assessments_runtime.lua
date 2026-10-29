-- Stage 6 real assessor callbacks with keyed in-memory transaction mocks.
-- Does not modify PS Housing properties, ownership or sale status.
local callbacks={}
local actor={cid='ASSESSOR-A',job='sagov',assess=true,view=true}
local homes={[77]={property_id=77,owner_citizenid='CIV-HOME',street='Paleto',region='Blaine',for_sale=0}}
local records,audits={},{}
local failAudit=false
local transferAtAudit=false
local function key(id,area,year)
    return tostring(id)..':'..tostring(area)..':'..tostring(year)
end
local function snapshot()
    local out={}
    for k,row in pairs(records) do
        out[k]={}
        for prop,value in pairs(row) do out[k][prop]=value end
    end
    return out,#audits
end
local function tx(sql,args)
    if sql:find('SELECT property_id,owner_citizenid FROM properties',1,true)
        or sql:find('SELECT owner_citizenid FROM properties',1,true) then
        local row=homes[args[1]]
        return row and {row} or {}
    end
    if sql:find('INSERT INTO mdt_government_property_assessments',1,true) then
        local recordKey=key(args[1],args[2],args[3])
        if records[recordKey] then return {affectedRows=0} end
        records[recordKey]={property_id=args[1],jurisdiction=args[2],tax_year=args[3],
            property_type=args[4],property_owner_snapshot=args[5],
            assessed_value=nil,government_owned=0,tax_exempt=0,
            status='pending',version=1}
        return {affectedRows=1}
    end
    if sql:find('SELECT property_id,jurisdiction,tax_year',1,true) then
        local row=records[key(args[1],args[2],args[3])]
        return row and {row} or {}
    end
    if sql:find('UPDATE mdt_government_property_assessments',1,true) then
        local approved=sql:find("SET status='approved'",1,true)~=nil
        local id=approved and args[8] or args[4]
        local area=approved and args[9] or args[5]
        local year=approved and args[10] or args[6]
        local version=approved and args[11] or args[8]
        local row=records[key(id,area,year)]
        if not row or row.version~=version then return {affectedRows=0} end
        if approved then
            if row.status~='pending' then return {affectedRows=0} end
            row.status='approved';row.assessed_value=args[1];row.property_type=args[2]
            row.government_owned=args[3];row.tax_exempt=args[4]
            row.exemption_reason=args[5]
        else
            if row.status~=args[7] then return {affectedRows=0} end
            row.status=args[1]
        end
        row.version=row.version+1
        return {affectedRows=1}
    end
    if sql:find('INSERT INTO mdt_government_property_assessment_audit',1,true) then
        if failAudit then return {affectedRows=0} end
        audits[#audits+1]={id=args[1],jurisdiction=args[2],year=args[3],
            action=args[5],before=args[#args-1],after=args[#args]}
        if transferAtAudit then actor.cid='ASSESSOR-B';transferAtAudit=false end
        return {affectedRows=1}
    end
    error('Unexpected assessor SQL: '..sql)
end
local env
env=setmetatable({
    Config={MdtAccess={GovernmentJurisdictions={
        state={label='San Andreas'},blaine_county={label='Blaine',parent='state'},
        los_santos_county={label='LS County',parent='state'},
        los_santos_city={label='Los Santos',parent='los_santos_county'}
    }}},
    GetCurrentResourceName=function() return 'ps-mdt' end,
    GetGovernmentPropertyAssessorAccess=function()
        if actor.job~='sagov' then return nil end
        return {citizenid=actor.cid,agency=actor.job,
            canAssess=actor.assess,canView=actor.view}
    end,
    ps={registerCallback=function(name,fn)callbacks[name]=fn end},
    json={encode=function(row)
        return tostring(row.status)..':'..tostring(row.assessed_value)
            ..':'..tostring(row.tax_exempt)..':'..tostring(row.jurisdiction)
            ..':'..tostring(row.tax_year)
    end},
    exports=function(_,fn)env.assessExport=fn end,
    MySQL={
        query={await=function(sql,args)
            assert(sql:find('mdt_government_property_assessments',1,true))
            local rows={}
            for _,r in pairs(records) do
                rows[#rows+1]={
                    property_id=r.property_id,jurisdiction=r.jurisdiction,tax_year=r.tax_year,
                    street=homes[r.property_id].street,region=homes[r.property_id].region,
                    for_sale=homes[r.property_id].for_sale,status=r.status,version=r.version,
                    property_type=r.property_type,assessed_value=r.assessed_value,
                    tax_exempt=r.tax_exempt,government_owned=r.government_owned,
                    exemption_reason=r.exemption_reason,
                }
            end
            return rows
        end},
        single={await=function(_,args)
            return records[key(args[1],args[2],args[3])]
        end},
        startTransaction=function(fn)
            local prior,count=snapshot()
            local ok,committed=pcall(fn,tx)
            if not ok or committed~=true then
                records=prior
                while #audits>count do table.remove(audits) end
                return false
            end
            return true
        end,
    },
},{__index=_G})
assert(loadfile('server/backend/government_jurisdiction_policy.lua','t',env))()
assert(loadfile('server/backend/government_property_assessments.lua','t',env))()
local function call(name,data)
    return assert(callbacks['ps-mdt:server:'..name],name)(1,data)
end
local function queue(area,year)
    return call('queueGovernmentPropertyAssessment',{
        propertyId=77,jurisdiction=area,taxYear=year,propertyType='commercial'
    })
end
assert(not call('queueGovernmentPropertyAssessment',{
    propertyId=999,jurisdiction='blaine_county',taxYear=2026,propertyType='commercial'
}).success)
assert(queue('blaine_county',2026).success)
assert(queue('state',2026).success,'State is an independent taxing authority')
assert(queue('blaine_county',2027).success,'Assessments are annual')
assert(not queue('blaine_county',2026).success,'Duplicate authority/year rejected')
assert(records[key(77,'blaine_county',2026)].status=='pending' and #audits==3)
assert(env.assessExport(77,'blaine_county',2026)==false)
assert(env.assessExport(77,'state',2026)==false)
assert(env.assessExport(77)==false,'Jurisdiction and year must be explicit')
local q=call('getGovernmentPropertyAssessments',{page=0})
assert(q.success and #q.assessments==3 and #q.jurisdictions==4)

local approve={propertyId=77,jurisdiction='blaine_county',taxYear=2026,
    version=1,action='approved',reason='Assessed for county',
    propertyType='commercial',assessedValue=250000,
    governmentOwned=true,taxExempt=false}
assert(call('decideGovernmentPropertyAssessment',approve).success)
assert(records[key(77,'blaine_county',2026)].government_owned==1
    and records[key(77,'blaine_county',2026)].tax_exempt==0,
    'Government ownership must not automatically imply exemption')
assert(env.assessExport(77,'blaine_county',2026)==true)
assert(env.assessExport(77,'state',2026)==false,
    'One jurisdiction approval must not approve another')
assert(not call('decideGovernmentPropertyAssessment',approve).success,'Stale version rejected')
assert(call('decideGovernmentPropertyAssessment',{
    propertyId=77,jurisdiction='blaine_county',taxYear=2026,
    version=2,action='reopen',reason='Updated valuation'
}).success)
assert(records[key(77,'blaine_county',2026)].status=='pending')

local exemption={propertyId=77,jurisdiction='blaine_county',taxYear=2026,
    version=3,action='approved',reason='No legal waiver',
    propertyType='commercial',assessedValue=200000,
    governmentOwned=true,taxExempt=true}
assert(not call('decideGovernmentPropertyAssessment',exemption).success,
    'Exemption must have separate justification')
exemption.exemptionReason='Approved under recorded tax authority policy'
failAudit=true
assert(not call('decideGovernmentPropertyAssessment',exemption).success)
assert(records[key(77,'blaine_county',2026)].status=='pending',
    'Failed audit must roll back exemption and assessment state')
failAudit=false
transferAtAudit=true
assert(not call('decideGovernmentPropertyAssessment',exemption).success,
    'Character transfer before commit must roll back')
assert(records[key(77,'blaine_county',2026)].status=='pending')
actor.cid='ASSESSOR-A'
homes[77].owner_citizenid='NEW-OWNER'
assert(not call('decideGovernmentPropertyAssessment',exemption).success,
    'Ownership change in PS Housing requires reassessment')
homes[77].owner_citizenid='CIV-HOME'
assert(call('decideGovernmentPropertyAssessment',exemption).success)
assert(records[key(77,'blaine_county',2026)].tax_exempt==1)
assert(records[key(77,'state',2026)].status=='pending')
assert(homes[77].for_sale==0,'Assessor must not mutate PS Housing sale status')
actor.assess=false
assert(not call('decideGovernmentPropertyAssessment',{
    propertyId=77,jurisdiction='state',taxYear=2026,
    version=1,action='rejected',reason='Unauthorized'
}).success)
assert(call('getGovernmentPropertyAssessments',{page=0}).success)
print('PASS Stage 6 per-authority/year assessor, tax exemption, ownership and audit rollback')
