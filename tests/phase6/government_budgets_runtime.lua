-- Stage 6 budget source regression with transactional fake SQL.
-- No player balances, bank accounts or tax schedules are touched.
local callbacks = {}
local actor = {cid='CLERK-A',job='bcgov',area='blaine_county',draft=true,approve=false,oversight=false}
local budgets = {
 [1]={id=1,agency='bcgov',jurisdiction='blaine_county',department='Fire',fiscal_year=2027,status='draft',version=1},
 [2]={id=2,agency='lscgov',jurisdiction='los_santos_county',department='Parks',fiscal_year=2027,status='draft',version=1},
}
local audit, nextId, failAudit, changeAtAudit = {},3,false,false
local function cloneRows()
 local copy={}
 for id,b in pairs(budgets) do copy[id]={};for k,v in pairs(b) do copy[id][k]=v end end
 return copy
end
local function transactionQuery(sql,args)
 if sql:find('SELECT status,version FROM mdt_government_budgets',1,true) then
  local b=budgets[args[1]]
  return b and b.agency==args[2] and b.jurisdiction==args[3] and {{status=b.status,version=b.version}} or {}
 elseif sql:find('INSERT INTO mdt_government_budgets',1,true) then
  for _,b in pairs(budgets) do
   if b.agency==args[1] and b.department==args[3] and b.fiscal_year==args[4] then return {affectedRows=0} end
  end
  local id=nextId;nextId=nextId+1
  budgets[id]={id=id,agency=args[1],jurisdiction=args[2],department=args[3],fiscal_year=args[4],
   revenue_estimate=args[5],expense_limit=args[6],notes=args[7],status='draft',version=1}
  return {affectedRows=1,insertId=id}
 elseif sql:find('UPDATE mdt_government_budgets',1,true) then
  local b=budgets[args[2]]
  if not b or b.agency~=args[3] or b.jurisdiction~=args[4] or b.status~='draft'
   or b.version~=args[5] then return {affectedRows=0} end
  b.status='approved';b.version=b.version+1;return {affectedRows=1}
 elseif sql:find('INSERT INTO mdt_government_budget_audit',1,true) then
  if failAudit then return {affectedRows=0} end
  audit[#audit+1]={id=args[1],agency=args[2],actor=args[3]}
  if changeAtAudit then actor.job='lscgov';actor.area='los_santos_county';changeAtAudit=false end
  return {affectedRows=1}
 end
 error('Unexpected SQL '..sql)
end
local env=setmetatable({
 GetCurrentResourceName=function()return 'ps-mdt'end,
 Config={MdtAccess={GovernmentJobs={sagov='state',bcgov='blaine_county',lscgov='los_santos_county',lsgov='los_santos_city'}}},
 GetGovernmentBudgetAccess=function()
  return {citizenid=actor.cid,agency=actor.job,jurisdiction=actor.area,
   canDraft=actor.draft,canApprove=actor.approve,hasStateOversight=actor.oversight}
 end,
 ps={registerCallback=function(name,fn)callbacks[name]=fn end},
 MySQL={
  query={await=function(sql,args)
   assert(sql:find('WHERE agency = ? AND jurisdiction = ?',1,true),'Budget query scoped to employer')
   assert(args[3]==51 and args[4]%50==0,'Budget query bounded')
   local out={}
   for _,b in pairs(budgets) do if b.agency==args[1] and b.jurisdiction==args[2] then out[#out+1]=b end end
   return out
  end},
  startTransaction=function(fn)
   local rows=cloneRows();local previous=#audit;local originalId=nextId
   local ok,value=pcall(fn,transactionQuery)
   if not ok or value~=true then
    budgets=rows;nextId=originalId
    while #audit>previous do table.remove(audit) end
    return false
   end
   return true
  end
 }
},{__index=_G})
assert(loadfile('server/backend/government_budgets.lua','t',env))()
local function call(name,payload)
 return assert(callbacks['ps-mdt:server:'..name],name)(1,payload)
end
local own=call('getGovernmentBudgets',{page=0})
assert(own.success and #own.budgets==1 and own.budgets[1].id==1)
assert(not own.canApprove and own.canDraft)
assert(not call('getGovernmentBudgets',{agency='lscgov'}).success,'County drafts are private')
assert(not call('getGovernmentBudgets',{page=201}).success)
assert(not call('approveGovernmentBudget',{id=1,version=1,reason='No authority'}).success)
local draft={department='Public Works',fiscalYear=2027,revenueEstimate=100000,expenseLimit=90000,notes='Proposed budget'}
local created=call('createGovernmentBudget',draft)
assert(created.success and budgets[created.id].agency=='bcgov' and #audit==1)
assert(not call('createGovernmentBudget',draft).success,'Unique employer/department/year budget')
assert(not call('createGovernmentBudget',{department='Oops',fiscalYear=2027,revenueEstimate=-1,expenseLimit=50,notes='Invalid'}).success)
actor.approve=true
assert(not call('approveGovernmentBudget',{id=2,version=1,reason='Other county'}).success)
assert(call('approveGovernmentBudget',{id=1,version=1,reason='Local authorization'}).success)
assert(budgets[1].status=='approved' and budgets[1].version==2 and #audit==2)
assert(not call('approveGovernmentBudget',{id=1,version=1,reason='Repeat'}).success)
actor.job='sagov';actor.area='state';actor.oversight=true;actor.draft=false;actor.approve=false
local oversight=call('getGovernmentBudgets',{agency='lscgov'})
assert(oversight.success and #oversight.budgets==1 and not oversight.canApprove and not oversight.canDraft)
assert(not call('approveGovernmentBudget',{id=2,version=1,reason='State takeover'}).success)
actor.job='bcgov';actor.area='blaine_county';actor.draft=true;actor.approve=true;actor.oversight=false
failAudit=true
assert(not call('createGovernmentBudget',{department='Library',fiscalYear=2028,revenueEstimate=10,expenseLimit=20,notes='Rollback'}).success)
assert(budgets[nextId]==nil,'No draft without audit')
assert(not call('approveGovernmentBudget',{id=created.id,version=1,reason='Audit failure'}).success)
assert(budgets[created.id].status=='draft','No adoption without audit')
failAudit=false
changeAtAudit=true
assert(not call('approveGovernmentBudget',{id=created.id,version=1,reason='Changed employer'}).success)
assert(budgets[created.id].status=='draft','Commit-time job change must roll back')
actor.job='bcgov';actor.area='blaine_county'
env.MySQL.startTransaction=nil
assert(not call('approveGovernmentBudget',{id=created.id,version=1,reason='No API'}).success)
print('PASS Stage 6 government budget agency isolation, role scope, versions and rollback')
