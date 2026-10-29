-- Stage 3 issuer policy: actual SAMS employment AND explicit certification grant.
-- Mocks SQL only; never touches persistent FiveM records.
local callbacks, writes, insertion = {}, 0, nil
local actor = {job='sams', citizenid='STATE-1', duty=true, permission=true}
local lookupHook, readHook = nil, nil
local expectedIssuer, expectedFamily = 'sams', 'ems'
local env = setmetatable({
    GetCurrentResourceName=function() return 'ps-mdt' end,
    CreateThread=function() end,
    print=function() end,
    ps={
        registerCallback=function(name,fn) callbacks[name]=fn end,
        getJobName=function() return actor.job end,
        getIdentifier=function() return actor.citizenid end,
    },
    CheckAuth=function() return actor.duty end,
    CanManageMdtPersonnel=function(_, citizenid)
        return actor.job == 'sams' and citizenid == 'SUBORDINATE-1'
    end,
    CheckPermission=function(_,permission)
        return actor.permission and permission == 'roster_manage_certifications'
    end,
    MySQL={
        scalar={await=function(query,args)
            assert(query:find('FROM players',1,true))
            if lookupHook then local hook=lookupHook; lookupHook=nil; hook() end
            return args[1]
        end},
        query={await=function(query)
            if query:find('CREATE TABLE IF NOT EXISTS mdt_personal_accreditations',1,true) then return {} end
            assert(query:find('FROM mdt_personal_accreditations',1,true))
            if readHook then local hook=readHook; readHook=nil; hook() end
            return {{id=4,credential_code='SAMS_BLS',credential_family='ems'}}
        end},
        insert={await=function(query,args)
            insertion = { sql=query, family=args[4], issuer=args[6] }
            assert(query:find('INSERT INTO mdt_personal_accreditations',1,true))
            assert(args[4]==expectedFamily, 'Credential family must match verified issuer')
            assert(args[6]==expectedIssuer, 'Issuer must match authorized state job')
            writes=writes+1
            return 9
        end},
    },
}, {__index=_G})
assert(loadfile('server/backend/accreditation.lua','t',env))()
local issue=assert(callbacks['ps-mdt:server:issueAccreditation'])
local payload={citizenid='PATIENT-1',code='SAMS_BLS',name='Basic Life Support'}
local first = issue(1,payload)
assert(first.success, (first.message or 'SAMS issuer failed') .. ' insert=' .. tostring(insertion and insertion.family) .. '/' .. tostring(insertion and insertion.issuer))
assert(writes==1)
actor.permission=false
assert(not issue(1,payload).success)
actor.permission=true
actor.job='pillboxmed'
assert(not issue(1,payload).success, 'hospital boss is not state accreditor')
actor.job='sams'
actor.duty=false
assert(not issue(1,payload).success)
assert(writes==1)

actor.duty=true
actor.permission=true
lookupHook=function() actor.job='pillboxmed' end
assert(not issue(1,payload).success, 'Issuer transfer during target lookup must fail')
actor.job='sams'
lookupHook=function() actor.citizenid='OTHER-CHARACTER' end
assert(not issue(1,payload).success, 'Issuer character transfer during lookup must fail')
actor.citizenid='STATE-1'

local selfRead=assert(callbacks['ps-mdt:server:getMyAccreditations'])
readHook=function() actor.citizenid='OTHER-CHARACTER' end
assert(#selfRead(1)==0, 'Credential read must reject changed character')
actor.citizenid='STATE-1'
assert(#selfRead(1)==1, 'Credential owner should see their records')
assert(writes==1)
local personnelRead=assert(callbacks['ps-mdt:server:getPersonnelAccreditations'])
assert(#personnelRead(1,'SUBORDINATE-1')==1, 'Supervisor with grant should see subordinate credentials')
readHook=function() actor.job='pillboxmed' end
assert(#personnelRead(1,'SUBORDINATE-1')==0, 'Cross-employer transfer must invalidate supervisor read')
actor.job='sams'
actor.permission=false
assert(#personnelRead(1,'SUBORDINATE-1')==0, 'Missing supervisor grant should deny read')
actor.permission=true

for _, sample in ipairs({
    {job='safr',family='fire'},
    {job='post',family='leo'},
    {job='sadle',family='leo'},
}) do
    actor.job, expectedIssuer, expectedFamily = sample.job, sample.job, sample.family
    local result=issue(1,{citizenid='PATIENT-1',code='CRED_' .. sample.job,name='Credential'})
    assert(result.success, sample.job .. ' issuance requires explicit authority')
end
assert(writes==4)
actor.job='bcso'
assert(not issue(1,payload).success, 'Ordinary law enforcement is not statewide issuer')
assert(writes==4)
actor.job, actor.permission, actor.duty = 'sams', true, true
local issuerAudit=assert(callbacks['ps-mdt:server:getIssuedAccreditations'])
local originalQuery=env.MySQL.query.await
env.MySQL.query.await=function(query,args)
    assert(query:find('WHERE issued_by_job = ?',1,true), 'Audit must filter issuer')
    assert(args[1]=='sams' and args[2]==0, 'Audit must be scoped to SAMS')
    return {{id=14,citizenid='EMPLOYEE-1',credential_family='ems'}}
end
assert(#issuerAudit(1,1)==1, 'Authorized issuer can audit its own credentials')
env.MySQL.query.await=function(query,args)
    actor.job='safr'
    return {{id=14,citizenid='EMPLOYEE-1',credential_family='ems'}}
end
assert(#issuerAudit(1,1)==0, 'Issuer job change must invalidate audit result')
actor.job='sams'
actor.permission=false
assert(#issuerAudit(1,1)==0, 'Audit requires explicit issuer grant')
actor.permission=true
env.MySQL.query.await=originalQuery
print('PASS statewide issuer families and anti-transfer credential authorization')
