-- Stage 3 issuer policy: actual SAMS employment AND explicit certification grant.
-- Mocks SQL only; never touches persistent FiveM records.
local callbacks, writes, insertion = {}, {}, nil
local actor = {job='sams', citizenid='STATE-1', duty=true, permission=true}
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
    CheckPermission=function(_,permission)
        return actor.permission and permission == 'roster_manage_certifications'
    end,
    MySQL={
        scalar={await=function(query,args)
            assert(query:find('FROM players',1,true))
            return args[1]
        end},
        query={await=function(query)
            assert(query:find('CREATE TABLE IF NOT EXISTS mdt_personal_accreditations',1,true))
            return {}
        end},
        insert={await=function(query,args)
            insertion = { sql=query, family=args[4], issuer=args[6] }
            assert(query:find('INSERT INTO mdt_personal_accreditations',1,true))
            assert(args[4]=='ems', 'SAMS credentials must belong to medical family')
            assert(args[6]=='sams', 'issuer must be actual SAMS job')
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
print('PASS SAMS issuer explicit grant, employer and duty boundaries')
