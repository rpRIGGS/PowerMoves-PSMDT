-- Stage 4 case disclosure behavior with production callbacks and mocked database.
local callbacks, writes, grants = {}, {}, {}
local actor={cid='LSPD-1',job='lspd',duty=true,allowed={cases_view=true,cases_edit=true}}
local dbCase={id=55,case_number='CASE-55',assigned_department='lspd',title='Confidential investigation'}
local env=setmetatable({
 GetCurrentResourceName=function() return 'ps-mdt' end,
 ps={
  registerCallback=function(name,fn) callbacks[name]=fn end,
  getIdentifier=function() return actor.cid end,
  getJobName=function() return actor.job end,
  auditLog=function() end,
 },
 CheckAuth=function() return actor.duty end,
 CheckPermission=function(_,name) return actor.allowed[name]==true end,
 GetMdtAccess=function() return {authorized=actor.duty,agency=actor.job,interfaceId='sadle'} end,
 MySQL={
  single={await=function(sql,args)
   if sql:find('FROM mdt_case_disclosures',1,true) then
    if grants[args[1]..':'..args[2]] then return {id=12} end
    return nil
   end
   if sql:find('FROM mdt_cases',1,true) then
    if args[1]~=55 then return nil end
    return sql:find('SELECT %*') and dbCase or {assigned_department=dbCase.assigned_department}
   end
   return nil
  end},
  scalar={await=function(sql,args)
   if sql:find('FROM players',1,true) then return args[1] end
   return nil
  end},
  query={await=function(sql,args)
   if sql:find('FROM mdt_case_disclosures g',1,true) then
    if actor.cid=='DEFENSE-1' and grants['55:DEFENSE-1'] then
     return {{id=55,title='Confidential investigation',assigned_department='lspd'}}
    end
    return {}
   end
   return {}
  end},
  insert={await=function(sql,args)
   assert(sql:find('INSERT INTO mdt_case_disclosures',1,true))
   assert(args[5]=='lspd','only owner may issue disclosure')
   grants['55:'..args[1]]=true
   writes[#writes+1]='grant'
   return 12
  end},
  update={await=function(sql,args)
   if sql:find('UPDATE mdt_case_disclosures',1,true) then
    if actor.job~='lspd' then return 0 end
    grants['55:DEFENSE-1']=nil
    writes[#writes+1]='revoke'
    return 1
   end
   return 1
  end},
 }
},{__index=_G})
assert(loadfile('server/backend/cases.lua','t',env))()
local function call(name,...)
 return assert(callbacks['ps-mdt:server:'..name],name)(1,...)
end
assert(call('grantCaseDisclosure',55,'DEFENSE-1','Assigned counsel discovery').success)
assert(grants['55:DEFENSE-1'])
actor.job='bcso'
assert(not call('grantCaseDisclosure',55,'OTHER-1','Unauthorized cross-agency disclosure').success)
actor.job='lspd'
actor.cid='DEFENSE-1'
actor.job='sadoj'
actor.allowed.cases_edit=false
assert(call('getCase',55).success,'Named grant should allow case detail')
assert(#call('getDisclosedCases')==1)
assert(not call('revokeCaseDisclosure',12).success,'Recipient cannot revoke a department grant')
actor.cid='LSPD-1';actor.job='lspd';actor.allowed.cases_edit=true
assert(call('revokeCaseDisclosure',12).success)
actor.cid='DEFENSE-1';actor.job='sadoj'
assert(not call('getCase',55).success,'Revoked grant must deny case detail')
assert(#call('getDisclosedCases')==0)
print('PASS cross-agency case disclosure grant, inbox and revocation')
