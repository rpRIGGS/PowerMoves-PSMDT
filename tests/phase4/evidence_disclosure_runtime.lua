-- Production evidence-disclosure callbacks on mocked framework and SQL.
-- No FiveM world, inventory, stash or database mutation.
local callbacks, grants, writes = {}, {}, 0
local actor={job='lspd',cid='LEO-1',duty=true,view=true,transfer=true}
local env=setmetatable({
 GetCurrentResourceName=function()return 'ps-mdt'end,
 RegisterNetEvent=function()end,
 ps={
  registerCallback=function(name,fn)callbacks[name]=fn end,
  getIdentifier=function()return actor.cid end,
  getJobName=function()return actor.job end,
  auditLog=function()end,
 },
 CheckAuth=function()return actor.duty end,
 CheckPermission=function(_,name)
  if name=='evidence_view' then return actor.view end
  if name=='evidence_transfer' then return actor.transfer end
  return false
 end,
 GetMdtAccess=function()return {authorized=actor.duty,agency=actor.job,interfaceId='sadle'} end,
 CanAccessMdtCase=function()return actor.job=='lspd' end,
 MySQL={
  scalar={await=function(sql)
   if sql:find('FROM players',1,true)then return 'sadoj' end
   return nil
  end},
  single={await=function(sql,args)
   if sql:find('FROM mdt_evidence_disclosures',1,true)then
    return grants[tostring(args[1])..':'..args[2]..':'..args[3]] and {id=10} or nil
   end
   if sql:find('SELECT case_id, created_by FROM mdt_evidence_items',1,true)then
    return {case_id=55,created_by='LEO-1'}
   end
   if sql:find('FROM mdt_evidence_items WHERE id',1,true)then
    return {id=3,title='Evidence Item',type='document',serial='SER-1'}
   end
   return nil
  end},
  query={await=function(sql,args)
   if sql:find('FROM mdt_evidence_disclosures g',1,true)then
    return actor.cid=='COUNSEL-1' and actor.job=='sadoj'
       and grants['3:COUNSEL-1:sadoj'] and {{id=3,title='Evidence Item'}} or {}
   end
   if sql:find('FROM mdt_evidence_custody',1,true)then
    return {{id=1,evidence_id=3,action='collected',created_at='2026-10-29'}}
   end
   return {}
  end},
  insert={await=function(sql,args)
   assert(sql:find('INSERT INTO mdt_evidence_disclosures',1,true))
   assert(args[2]=='sadoj' and args[5]=='lspd' and args[6]==3)
   grants['3:'..args[1]..':'..args[2]]=true;writes=writes+1;return 10
  end},
  update={await=function(sql,args)
   assert(sql:find('UPDATE mdt_evidence_disclosures',1,true))
   if actor.job~='lspd' then return 0 end
   grants['3:COUNSEL-1:sadoj']=nil;writes=writes+1;return 1
  end}
 }
},{__index=_G})
assert(loadfile('server/backend/evidence.lua','t',env))()
local function call(name,...)return assert(callbacks['ps-mdt:server:'..name],name)(1,...)end
assert(call('grantEvidenceDisclosure',3,'COUNSEL-1','Legal evidence discovery').success)
assert(writes==1)
actor.job='sadoj';actor.cid='COUNSEL-1';actor.transfer=false
assert(#call('getDisclosedEvidence')==1)
local response=call('getDisclosedEvidenceDetail',3)
assert(response.success and response.data.item.id==3 and #response.data.custody==1)
assert(response.data.item.stash_id==nil,'Discovery must never expose inventory stash identifiers')
actor.job='bcso'
assert(#call('getDisclosedEvidence')==0,'Recipient employer change must deny evidence')
actor.job='lspd';actor.cid='LEO-1';actor.transfer=true
assert(call('revokeEvidenceDisclosure',10).success)
actor.job='sadoj';actor.cid='COUNSEL-1';actor.transfer=false
assert(not call('getDisclosedEvidenceDetail',3).success,'Revoked grant must deny metadata and custody')
print('PASS read-only evidence disclosure, custody and employer-bound revocation')
