-- Stage 4: exercise the real server getCase callback with isolated mock SQL.
-- No server or persistent database access.
local callbacks = {}
local actor = {job='bcso', cid='CID-DEFENSE', authorized=true}
local granted = true
local changeDuringRead = false
local dbReads = 0
local env=setmetatable({
    GetCurrentResourceName=function() return 'ps-mdt' end,
    Config={},
    ps={
        registerCallback=function(name,fn) callbacks[name]=fn end,
        getIdentifier=function() return actor.cid end,
        getJobName=function() return actor.job end,
        auditLog=function() end,
    },
    CheckAuth=function() return actor.authorized end,
    CheckPermission=function(_,name) return name=='cases_view' end,
    GetMdtAccess=function()
        return {authorized=actor.authorized, agency=actor.job, interfaceId='sadle'}
    end,
    MySQL={
        single={await=function(sql,args)
            if sql:find('SELECT * FROM mdt_cases WHERE id = ?',1,true) then
                return {id=5,title='Case summary',assigned_department='lspd'}
            end
            if sql:find('SELECT id FROM mdt_case_disclosures',1,true) then
                assert(args[1]==5 and args[2]==actor.cid and args[3]==actor.job)
                return (granted and actor.job=='bcso' and actor.cid=='CID-DEFENSE') and {id=7} or nil
            end
            return nil
        end},
        query={await=function(sql,args)
            dbReads=dbReads+1
            if changeDuringRead and dbReads==2 then actor.cid='CID-OTHER' end
            return {{id=23,content='Private investigative information',type='private'}}
        end},
    },
}, {__index=_G})
assert(loadfile('server/backend/cases.lua','t',env))()
local getCase=assert(callbacks['ps-mdt:server:getCase'])
local ok=getCase(1,5)
assert(ok.success, 'Named recipient with active grant can read case summary')
assert(ok.data.case.title=='Case summary')
assert(#ok.data.officers==0 and #ok.data.attachments==0 and #ok.data.notes==0
    and #ok.data.reports==0 and #ok.data.evidence==0,
    'Shared case must not expose internal attachments/notes/related reports')
granted=false
assert(not getCase(1,5).success, 'Revoked grant must fail direct read')
granted=true
actor.job='safr'
assert(not getCase(1,5).success, 'Grant tied to old job must fail')
actor.job='bcso'
dbReads=0
changeDuringRead=true
assert(not getCase(1,5).success, 'Source character swap during SQL must fail')
print('PASS confidential case summary, active grant, revocation and identity recheck')
