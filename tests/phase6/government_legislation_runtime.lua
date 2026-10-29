-- Stage 6: execute legislative callbacks against isolated, rollback-capable SQL mocks.
-- Tests real server module; never touches a FiveM server or player database.
local callbacks={}
local actor={cid='CLERK-BC',job='bcgov',area='blaine_county',
  draft=true,vote=false,certify=false,publish=false,oversight=false}
local records={
 [1]={id=1,agency='bcgov',jurisdiction='blaine_county',measure_type='county_ordinance',
      title='Road signage',body='Original draft',status='draft',version=1},
 [2]={id=2,agency='lscgov',jurisdiction='los_santos_county',measure_type='county_ordinance',
      title='Other county draft',body='Protected',status='draft',version=1},
 [3]={id=3,agency='lsgov',jurisdiction='los_santos_city',measure_type='municipal_code',
      title='Published code',body='Visible publicly',status='published',version=3},
 [4]={id=4,agency='bcgov',jurisdiction='blaine_county',measure_type='county_ordinance',
      title='Vote without ballots',body='Pending',status='voting',version=2},
}
local ballots,audits,nextId={}, {},5
local failAudit=false
local transferOnAudit=false
local function copyValues(tbl)
 local result={}
 for k,v in pairs(tbl) do
  if type(v)=='table' then result[k]=copyValues(v) else result[k]=v end
 end
 return result
end
local function txQuery(sql,args)
 if sql:find('SELECT COUNT(*) AS total',1,true) then
  local total,yes=0,0
  for _,v in pairs(ballots) do
   if v.id==args[1] and v.agency==args[2] then
    total=total+1;if v.choice=='yes' then yes=yes+1 end
   end
  end
  return {{total=total,yes_votes=yes}}
 end
 if sql:find('SELECT status,version FROM mdt_government_legislation',1,true)
   or sql:find('SELECT status FROM mdt_government_legislation',1,true) then
  local r=records[args[1]]
  if not r or r.agency~=args[2] or r.jurisdiction~=args[3] then return {} end
  return {{status=r.status,version=r.version}}
 end
 if sql:find('INSERT INTO mdt_government_legislation_votes',1,true) then
  local id,agency,cid,choice=args[1],args[2],args[3],args[4]
  for _,v in pairs(ballots) do
   if v.id==id and v.cid==cid then return {affectedRows=0} end
  end
  ballots[#ballots+1]={id=id,agency=agency,cid=cid,choice=choice}
  return {affectedRows=1}
 end
 if sql:find('INSERT INTO mdt_government_legislation_audit',1,true) then
  if failAudit then return {affectedRows=0} end
  audits[#audits+1]={id=args[1],agency=args[2],action=args[4]}
  if transferOnAudit then
   actor.job='lscgov';actor.area='los_santos_county';transferOnAudit=false
  end
  return {affectedRows=1}
 end
 if sql:find('INSERT INTO mdt_government_legislation',1,true) then
  local id=nextId;nextId=id+1
  records[id]={id=id,agency=args[1],jurisdiction=args[2],measure_type=args[3],
    title=args[4],body=args[5],status='draft',version=1}
  return {affectedRows=1,insertId=id}
 end
 if sql:find('UPDATE mdt_government_legislation',1,true) then
  local isEdit=sql:find('SET title=',1,true)~=nil
  local isCertify=sql:find('certified_by_citizenid',1,true)~=nil
  local isPublish=sql:find("status='published'",1,true)~=nil
  local id,agency,area,from,version
  if isEdit then
   id,agency,area,from,version=args[3],args[4],args[5],'draft',args[6]
  elseif isCertify then
   id,agency,area,from,version=args[4],args[5],args[6],args[7],args[8]
  elseif isPublish then
   id,agency,area,from,version=args[1],args[2],args[3],'adopted',args[4]
  else
   id,agency,area,from,version=args[2],args[3],args[4],args[5],args[6]
  end
  local r=records[id]
  if not r or r.agency~=agency or r.jurisdiction~=area or r.status~=from
     or r.version~=version then return {affectedRows=0} end
  if isEdit then r.title=args[1];r.body=args[2]
  elseif isCertify then r.status=args[1];r.certification_reason=args[3]
  elseif isPublish then r.status='published'
  else r.status=args[1] end
  r.version=r.version+1
  return {affectedRows=1}
 end
 error('Unexpected legislative transaction statement: '..sql)
end
local env=setmetatable({
 GetCurrentResourceName=function()return 'ps-mdt'end,
 Config={MdtAccess={
  GovernmentJobs={sagov='state',bcgov='blaine_county',
    lscgov='los_santos_county',lsgov='los_santos_city'},
  GovernmentJurisdictions={state={},blaine_county={parent='state'},
    los_santos_county={parent='state'},los_santos_city={parent='los_santos_county'}}
 }},
 GetGovernmentLegislationAccess=function()
  return {citizenid=actor.cid,agency=actor.job,jurisdiction=actor.area,
   canDraft=actor.draft,canVote=actor.vote,canCertify=actor.certify,
   canPublish=actor.publish,hasStateOversight=actor.oversight}
 end,
 ps={registerCallback=function(name,fn)callbacks[name]=fn end},
 MySQL={
  query={await=function(sql,args)
   if sql:find('FROM mdt_government_legislation_votes v',1,true) then
    local result={}
    for _,v in ipairs(ballots) do
     local r=records[v.id]
     if v.id==args[1] then result[#result+1]={
       voter_citizenid=v.cid,vote=v.choice,agency=v.agency,
       jurisdiction=r.jurisdiction,status=r.status}
     end
    end
    return result
   end
   assert(sql:find('FROM mdt_government_legislation',1,true))
   assert(args[3]==51 and args[4]%50==0,'Legislative list must paginate')
   local result={}
   for _,r in pairs(records) do
    if r.status=='published' or r.agency==args[1] or args[2]==1 then
     result[#result+1]=r
    end
   end
   return result
  end},
  startTransaction=function(fn)
   local oldRows=copyValues(records)
   local oldVotes=copyValues(ballots)
   local oldAudits=copyValues(audits)
   local oldNext=nextId
   local ok,result=pcall(fn,txQuery)
   if not ok or result~=true then
    records=oldRows;ballots=oldVotes;audits=oldAudits;nextId=oldNext
    return false
   end
   return true
  end
 }
},{__index=_G})
assert(loadfile('server/backend/government_jurisdiction_policy.lua','t',env))()
assert(loadfile('server/backend/government_legislation.lua','t',env))()
local function call(name,data)
 return assert(callbacks['ps-mdt:server:'..name],name)(1,data)
end
local list=call('getGovernmentLegislation',{page=0})
assert(list.success and #list.measures==3)
for _,r in ipairs(list.measures) do assert(r.id~=2,'Other county draft leaked') end
assert(not call('getGovernmentLegislation',{page=-1}).success)
assert(not call('createGovernmentMeasure',{measureType='state_law',
  title='Invalid',body='Only state may draft state law'}).success)
local created=call('createGovernmentMeasure',{measureType='county_ordinance',
  title='County road ordinance',body='Proposed text'})
assert(created.success and records[5].agency=='bcgov' and #audits==1)
assert(call('editGovernmentMeasure',{id=5,version=1,title='Revised ordinance',body='New text'}).success)
assert(records[5].version==2)
assert(not call('editGovernmentMeasure',{id=5,version=1,title='Stale',body='No'}).success)
assert(call('openGovernmentMeasureVote',{id=5,version=2}).success)
assert(records[5].status=='voting')
assert(not call('certifyGovernmentMeasure',{id=5,version=3,
  outcome='adopted',reason='No certifier permission'}).success)
actor.vote=true
assert(not call('castGovernmentOfficialVote',{id=2,choice='yes'}).success,
 'Other county measure must not accept vote')
assert(call('castGovernmentOfficialVote',{id=5,choice='yes'}).success)
assert(not call('castGovernmentOfficialVote',{id=5,choice='yes'}).success,
 'Duplicate official vote must be denied')
assert(#ballots==1)
local votes=call('getGovernmentOfficialVotes',{id=5})
assert(votes.success and #votes.votes==1 and votes.votes[1].voter_citizenid=='CLERK-BC')
actor.certify=true
assert(not call('certifyGovernmentMeasure',{id=4,version=2,
  outcome='adopted',reason='No ballots yet'}).success)
assert(call('certifyGovernmentMeasure',{id=5,version=3,
  outcome='adopted',reason='Meeting chair certified recorded votes'}).success)
assert(records[5].status=='adopted')
assert(not call('publishGovernmentMeasure',{id=5,version=4}).success)
actor.publish=true
assert(call('publishGovernmentMeasure',{id=5,version=4}).success)
assert(records[5].status=='published' and records[5].version==5)
assert(not call('publishGovernmentMeasure',{id=5,version=4}).success)
actor.job='lscgov';actor.area='los_santos_county'
assert(not call('castGovernmentOfficialVote',{id=4,choice='no'}).success)
assert(not call('editGovernmentMeasure',{id=1,version=1,
  title='Cross county',body='Denied'}).success)
actor.job='sagov';actor.area='state';actor.oversight=true
actor.draft=false;actor.vote=false;actor.certify=false;actor.publish=false
local oversight=call('getGovernmentLegislation',{page=0})
assert(oversight.success and #oversight.measures==5)
assert(not call('publishGovernmentMeasure',{id=4,version=2}).success,
 'State oversight must not publish a county law')
actor.job='bcgov';actor.area='blaine_county';actor.draft=true;actor.vote=true
actor.certify=true;actor.publish=true;actor.oversight=false
failAudit=true
assert(not call('createGovernmentMeasure',{measureType='county_ordinance',
  title='Failed draft',body='Must roll back'}).success)
assert(records[6]==nil)
assert(not call('castGovernmentOfficialVote',{id=4,choice='yes'}).success)
assert(#ballots==1,'Audit failure must roll back a vote')
failAudit=false
transferOnAudit=true
assert(not call('castGovernmentOfficialVote',{id=4,choice='yes'}).success)
assert(#ballots==1,'Job transfer must roll back vote')
actor.job='bcgov';actor.area='blaine_county'
env.MySQL.startTransaction=nil
assert(not call('castGovernmentOfficialVote',{id=4,choice='yes'}).success)
print('PASS Stage 6 legislative ownership, ballot uniqueness, certification, publishing, rollback')
