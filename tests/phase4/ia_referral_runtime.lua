-- FiveM-free unit test. Production IA callbacks in a mocked Lua environment.
-- Never writes to a database.
local callbacks, inserted, updates, lastQuery = {}, {}, {}, nil
local current = {job='lspd', cid='LEO-1', duty=true, permissions={ia_view=true,ia_manage=true}}
local case = {id=42,agency='lspd',job_type='police'}
local env=setmetatable({
    GetCurrentResourceName=function() return 'ps-mdt' end,
    CreateThread=function() end,
    AddEventHandler=function() end,
    Config={PoliceJobs={'lspd','bcso','sadle'},FireJobs={},MedicalJobs={}},
    ps={
        registerCallback=function(name,callback) callbacks[name]=callback end,
        getJobName=function() return current.job end,
        getIdentifier=function() return current.cid end,
        debug=function() end,
        auditLog=function() end,
    },
    CheckAuth=function() return current.duty end,
    CheckPermission=function(_,name) return current.permissions[name]==true end,
    GetMdtDomain=function() return 'police' end,
    MySQL={
        single={await=function(sql,args)
            assert(sql:find('FROM mdt_ia_complaints',1,true))
            if args[1] == case.id then return {agency=case.agency,job_type=case.job_type} end
            return nil
        end},
        query={await=function(sql,args)
            if sql:find('CREATE TABLE IF NOT EXISTS mdt_ia_referrals',1,true) then return {} end
            assert(sql:find('FROM mdt_ia_referrals',1,true))
            lastQuery={sql=sql,args=args}
            return {{id=7,complaint_id=42,referring_agency='lspd',status='pending',reason='Serious misconduct'}}
        end},
        insert={await=function(sql,args)
            assert(sql:find('INSERT INTO mdt_ia_referrals',1,true))
            inserted[#inserted+1]={sql=sql,args=args}
            return 7
        end},
        update={await=function(sql,args)
            assert(sql:find("r.status = 'pending'",1,true))
            updates[#updates+1]={sql=sql,args=args}
            return #updates==1 and 1 or 0
        end},
    }
},{__index=_G})
assert(loadfile('server/backend/ia.lua','t',env))()
local function call(name,...)
    return assert(callbacks['ps-mdt:server:'..name],name)(1,...)
end
local ok=call('referIAComplaintToSADLE',42,'Documented concerns warrant state investigation')
assert(ok.success and ok.referralId==7 and #inserted==1)
assert(inserted[1].args[2]=='lspd' and inserted[1].args[3]=='LEO-1')
current.job='bcso'
assert(not call('referIAComplaintToSADLE',42,'Attempt to refer another department case').success)
current.job='lspd';current.permissions.ia_manage=false
assert(not call('referIAComplaintToSADLE',42,'Unauthorized referral attempt').success)
current.permissions.ia_manage=true; current.job='sadle';current.cid='STATE-1'
assert(#call('getSADLEIAReferrals',1)==1)
assert(lastQuery.sql:find("c.job_type = 'police'",1,true))
assert(call('acceptSADLEIAReferral',7).success and #updates==1)
assert(not call('acceptSADLEIAReferral',7).success, 'Cannot accept twice')
current.job='bcso'
assert(#call('getSADLEIAReferrals',1)==0)
assert(not call('acceptSADLEIAReferral',7).success)
current.job='sadle';current.permissions.ia_manage=false
assert(not call('acceptSADLEIAReferral',7).success)
print('PASS local IA referral, SADLE queue and idempotent acceptance authority')
