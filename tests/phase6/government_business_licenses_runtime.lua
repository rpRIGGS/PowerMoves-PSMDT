-- Source-level Stage 6 business-license callback regression.
-- Real server callbacks, mocked SQL, identity and physical counter policy.
local callbacks={}
local actor={cid='CIV-A',job='unemployed',duty=false,atDesk=true,review=false,issue=false,oversight=false}
local records,history,nextId={}, {},1
local now=100000
local auditFailure=false
local jobSwitchOnAudit=false
local function cloneRows()
    local output={}
    for id,r in pairs(records) do
        output[id]={}
        for key,value in pairs(r) do output[id][key]=value end
    end
    return output
end
local function query(sql,args)
    if sql:find('INSERT INTO mdt_government_business_licenses',1,true) then
        for _,row in pairs(records) do
            if row.owner_citizenid==args[1] and row.agency==args[2] and row.business_name==args[4] then
                return {affectedRows=0}
            end
        end
        local id=nextId;nextId=id+1
        records[id]={id=id,owner_citizenid=args[1],agency=args[2],
            jurisdiction=args[3],business_name=args[4],business_type=args[5],
            description=args[6],property_reference=args[7],
            status='submitted',version=1}
        return {affectedRows=1,insertId=id}
    end
    if sql:find('INSERT INTO mdt_government_business_license_audit',1,true) then
        if auditFailure then return {affectedRows=0} end
        history[#history+1]={id=args[1],action=args[4]}
        if jobSwitchOnAudit then
            actor.job='lscgov';actor.duty=true;jobSwitchOnAudit=false
        end
        return {affectedRows=1}
    end
    if sql:find('SELECT status,version,jurisdiction FROM mdt_government_business_licenses',1,true) then
        local row=records[args[1]]
        return row and row.agency==args[2] and {row} or {}
    end
    if sql:find('UPDATE mdt_government_business_licenses',1,true) then
        local approved=sql:find("SET status='approved'",1,true)~=nil
        local revoked=sql:find("SET status='revoked'",1,true)~=nil
        local action,idx,agency,jurisdiction,previous,version
        if approved or revoked then
            action=approved and 'approved' or 'revoked'
            idx,agency,jurisdiction,version=args[3],args[4],args[5],args[6]
            previous=approved and 'under_review' or 'suspended'
        else
            action=args[1];idx,agency,jurisdiction,previous,version=
                args[4],args[5],args[6],args[7],args[8]
        end
        local row=records[idx]
        if not row or row.agency~=agency or row.jurisdiction~=jurisdiction
            or row.status~=previous or row.version~=version then return {affectedRows=0} end
        row.status=action
        row.version=row.version+1
        if approved then row.license_number=('SA-BIZ-%09d'):format(idx) end
        return {affectedRows=1}
    end
    error('Unexpected transaction SQL '..sql)
end
local env=setmetatable({
    GetCurrentResourceName=function() return 'ps-mdt' end,
    GetGameTimer=function() return now end,
    Config={MdtAccess={
        GovernmentJobs={sagov='state',bcgov='blaine_county',
            lscgov='los_santos_county',lsgov='los_santos_city'},
        GovernmentJurisdictions={
            state={label='State'},blaine_county={parent='state'},
            los_santos_county={parent='state'},
            los_santos_city={parent='los_santos_county'}
        }
    }},
    GetGovernmentBusinessLicenseAccess=function()
        if not actor.duty or actor.job=='unemployed' then return nil end
        return {citizenid=actor.cid,agency=actor.job,
            jurisdiction=env.Config.MdtAccess.GovernmentJobs[actor.job],
            canReview=actor.review,canIssue=actor.issue,
            hasStateOversight=actor.oversight}
    end,
    PublicServiceDeskAllows=function(_,agency,service)
        return actor.atDesk and
            ((service=='business_license_apply' and agency=='bcgov')
             or service=='business_license_status')
    end,
    ps={
        getIdentifier=function()return actor.cid end,
        registerCallback=function(name,fn)callbacks[name]=fn end,
    },
    MySQL={
        startTransaction=function(fn)
            local before, count, previous=cloneRows(),#history,nextId
            local ok,value=pcall(fn,query)
            if not ok or value~=true then
                records=before
                while #history>count do table.remove(history) end
                nextId=previous
                return false
            end
            return true
        end,
        query={await=function(sql,args)
            local result={}
            if sql:find('WHERE owner_citizenid = ?',1,true) then
                for _,r in pairs(records) do
                    if r.owner_citizenid==args[1] then result[#result+1]=r end
                end
            else
                assert(sql:find('WHERE agency = ?',1,true))
                assert(args[2]==51 and args[3]%50==0)
                for _,r in pairs(records) do
                    if r.agency==args[1] then result[#result+1]=r end
                end
            end
            return result
        end}
    }
},{__index=_G})
assert(loadfile('server/backend/government_jurisdiction_policy.lua','t',env))()
assert(loadfile('server/backend/government_business_licenses.lua','t',env))()
local function call(name,data)
    return assert(callbacks['ps-mdt:server:'..name],name)(1,data)
end
local payload={agency='bcgov',name='Test Small Business',
    businessType='Retail',description='General sales',propertyReference=''}
assert(not call('applyForBusinessLicense',{
    agency='sagov',name='Unauthorized',businessType='Retail',description='Bad'
}).success)
local intake=call('applyForBusinessLicense',payload)
assert(intake.success and intake.applicationId==1)
assert(records[1].status=='submitted' and records[1].owner_citizenid=='CIV-A'
    and records[1].jurisdiction=='blaine_county' and #history==1)
now=now+61000
assert(not call('applyForBusinessLicense',payload).success,'Duplicate business app rejected')
assert(#call('getMyBusinessLicenseApplications').applications==1)
actor.cid='CIV-B'
assert(#call('getMyBusinessLicenseApplications').applications==0,'Owner isolation')
actor.atDesk=false
assert(not call('getMyBusinessLicenseApplications').success)
actor.cid='CLERK-A';actor.job='bcgov';actor.duty=true
actor.review=true;actor.issue=false;actor.atDesk=true
local queue=call('getGovernmentBusinessLicenses',{page=0})
assert(queue.success and #queue.applications==1 and queue.canReview and not queue.canIssue)
assert(not call('getGovernmentBusinessLicenses',{agency='lscgov'}).success)
assert(not call('getGovernmentBusinessLicenses',{page=201}).success)
assert(#call('getGovernmentBusinessLicenseAuthorities').authorities==1)
assert(not call('decideGovernmentBusinessLicense',{id=1,version=1,
    action='approved',reason='Not authorized'}).success)
local reviewing={id=1,version=1,action='under_review',reason='Review started'}
assert(call('decideGovernmentBusinessLicense',reviewing).success)
assert(records[1].status=='under_review' and records[1].version==2 and #history==2)
assert(not call('decideGovernmentBusinessLicense',reviewing).success,'Optimistic version required')
actor.issue=true
jobSwitchOnAudit=true
assert(not call('decideGovernmentBusinessLicense',{id=1,version=2,
    action='approved',reason='Must roll back'}).success)
assert(records[1].status=='under_review' and records[1].license_number==nil,
    'Job transfer before commit must roll back license issuance')
actor.job='bcgov'
local approval={id=1,version=2,action='approved',reason='Local approval'}
assert(call('decideGovernmentBusinessLicense',approval).success)
assert(records[1].status=='approved' and records[1].license_number=='SA-BIZ-000000001')
assert(not call('decideGovernmentBusinessLicense',approval).success)
actor.job='lscgov';actor.issue=true;actor.review=true
assert(not call('decideGovernmentBusinessLicense',{id=1,version=3,
    action='suspended',reason='Cross agency'}).success)
actor.job='sagov';actor.oversight=true;actor.review=false;actor.issue=false
local state=call('getGovernmentBusinessLicenseAuthorities')
assert(state.success and #state.authorities==3,'State has read-only local authority list')
assert(call('getGovernmentBusinessLicenses',{agency='bcgov'}).success)
assert(not call('decideGovernmentBusinessLicense',{id=1,version=3,
    action='suspended',reason='Oversight is not issuance'}).success)
actor.job='bcgov';actor.oversight=false;actor.issue=true;actor.review=true
auditFailure=true
assert(not call('decideGovernmentBusinessLicense',{id=1,version=3,
    action='suspended',reason='Audit failure'}).success)
assert(records[1].status=='approved')
auditFailure=false
assert(call('decideGovernmentBusinessLicense',{id=1,version=3,
    action='suspended',reason='License check'}).success)
assert(records[1].status=='suspended')
assert(call('decideGovernmentBusinessLicense',{id=1,version=4,
    action='revoked',reason='Material violation'}).success)
assert(records[1].status=='revoked')
print('PASS Stage 6 business licensing: citizen owner, local authority, audit and rollback')
