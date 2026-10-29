-- Stage 4 named report disclosures, production callback + mocked SQL.
local callbacks, grants, writes = {}, {}, 0
local actor={job='lspd',cid='LEO-1',duty=true,canEdit=true,canView=true}
local env=setmetatable({
 GetCurrentResourceName=function() return 'ps-mdt' end,
 Config={},
 ps={
  registerCallback=function(name,fn) callbacks[name]=fn end,
  getIdentifier=function() return actor.cid end,
  getJobName=function() return actor.job end,
  getJobType=function() return actor.job=='lspd' and 'leo' or 'doj' end,
  auditLog=function() end,
 },
 CheckAuth=function() return actor.duty end,
 CheckPermission=function(_,perm)
  if perm=='reports_edit' then return actor.canEdit end
  if perm=='reports_view' then return actor.canView end
  return false
 end,
 MySQL={
  scalar={await=function(sql,args)
   if sql:find('FROM players',1,true) then return args[1] end
   if sql:find('mdt_reports_restrictions',1,true) then return 'lspd' end
   return nil
  end},
  single={await=function(sql,args)
   if sql:find('mdt_report_disclosures',1,true) then
    return grants[tostring(args[1])..':'..args[2]] and {id=10} or nil
   end
   return nil
  end},
  query={await=function(sql,args)
   if sql:find('FROM mdt_report_disclosures g',1,true) then
    return actor.cid=='COUNSEL-1' and grants['90:COUNSEL-1'] and
      {{id=90,title='Confidential report'}} or {}
   end
   return {}
  end},
  insert={await=function(sql,args)
   assert(sql:find('INSERT INTO mdt_report_disclosures',1,true))
   assert(args[4]=='lspd' and args[5]==90 and args[6]=='lspd')
   grants['90:'..args[1]]=true;writes=writes+1;return 10
  end},
  update={await=function(sql,args)
   assert(sql:find('UPDATE mdt_report_disclosures',1,true))
   if actor.job~='lspd' then return 0 end
   grants['90:COUNSEL-1']=nil
   writes=writes+1
   return 1
  end},
 }
},{__index=_G})
assert(loadfile('server/backend/reports.lua','t',env))()
local function call(name,...) return assert(callbacks['ps-mdt:server:'..name],name)(1,...) end
assert(call('grantReportDisclosure',90,'COUNSEL-1','Court case specific discovery').success)
assert(writes==1)
actor.job='bcso'
assert(not call('grantReportDisclosure',90,'OTHER-1','Unauthorized agency share').success)
actor.job='sadoj';actor.cid='COUNSEL-1';actor.canEdit=false
assert(#call('getDisclosedReports')==1,'Granted report is in recipient inbox')
assert(not call('revokeReportDisclosure',10).success,'Recipient must not revoke owner grant')
actor.job='lspd';actor.cid='LEO-1';actor.canEdit=true
assert(call('revokeReportDisclosure',10).success)
actor.job='sadoj';actor.cid='COUNSEL-1'
assert(#call('getDisclosedReports')==0,'Revoked report should vanish')
print('PASS report disclosure grant, owner-only revoke and inbox invalidation')
