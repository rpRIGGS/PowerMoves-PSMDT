-- Stage 6: execute government notice callbacks with a rolled-back SQL mock.
-- No FiveM server, database, or real player data is modified.
local callbacks = {}
local actor = {cid='GOV-A',job='bcgov',jurisdiction='blaine_county',
    manage=true,publish=false,oversight=false,onDuty=true}
local notices = {
    [1]={id=1,agency='bcgov',jurisdiction='blaine_county',title='County draft',body='Draft only',
        status='draft',version=1},
    [2]={id=2,agency='lscgov',jurisdiction='los_santos_county',title='Other county draft',
        body='Protected',status='draft',version=1},
    [3]={id=3,agency='lsgov',jurisdiction='los_santos_city',title='Published municipal notice',
        body='Public',status='published',version=2},
}
local audits = {}
local nextId=4
local publicAtDesk=true
local failAudit=false
local transferAtAudit=false
local function snapshot()
    local out={}
    for id,r in pairs(notices) do out[id]={}
        for k,v in pairs(r) do out[id][k]=v end
    end
    return out,#audits,nextId
end
local function restore(rows,count,id)
    notices=rows
    while #audits>count do table.remove(audits) end
    nextId=id
end
local function transact(sql,params)
    if sql:find('FROM mdt_government_notices',1,true)
        and sql:find('FOR UPDATE',1,true) then
        local n=notices[params[1]]
        if not n or n.agency~=params[2] then return {} end
        return {{status=n.status,version=n.version,jurisdiction=n.jurisdiction}}
    end
    if sql:find('INSERT INTO mdt_government_notices',1,true) then
        notices[nextId]={id=nextId,agency=params[1],jurisdiction=params[2],
            title=params[3],body=params[4],status='draft',version=1}
        local result={affectedRows=1,insertId=nextId}
        nextId=nextId+1
        return result
    end
    if sql:find('UPDATE mdt_government_notices',1,true) then
        local publishing=sql:find("status = 'published'",1,true)~=nil
        local id=publishing and params[2] or params[3]
        local agency=publishing and params[3] or params[4]
        local version=publishing and params[5] or params[5]
        local n=notices[id]
        if not n or n.agency~=agency or n.status~='draft'
            or n.version~=version then return {affectedRows=0} end
        if publishing then
            if n.jurisdiction~=params[4] then return {affectedRows=0} end
            n.status='published'
        else
            n.title=params[1];n.body=params[2]
        end
        n.version=n.version+1
        return {affectedRows=1}
    end
    if sql:find('INSERT INTO mdt_government_notice_audit',1,true) then
        if failAudit then return {affectedRows=0} end
        audits[#audits+1]={id=params[1],agency=params[2]}
        if transferAtAudit then actor.job='lscgov';actor.jurisdiction='los_santos_county';transferAtAudit=false end
        return {affectedRows=1}
    end
    error('Unexpected transaction SQL: '..sql)
end
local env=setmetatable({
    GetCurrentResourceName=function()return 'ps-mdt'end,
    Config={MdtAccess={
        GovernmentJobs={sagov='state',bcgov='blaine_county',
            lscgov='los_santos_county',lsgov='los_santos_city'},
        GovernmentJurisdictions={
            state={label='State'},
            blaine_county={parent='state'},
            los_santos_county={parent='state'},
            los_santos_city={parent='los_santos_county'}
        }
    }},
    GetGovernmentNoticeAccess=function()
        if not actor.onDuty or actor.job=='unknown' then return nil end
        return {citizenid=actor.cid,agency=actor.job,jurisdiction=actor.jurisdiction,
            canManage=actor.manage,canPublish=actor.publish,
            hasStateOversight=actor.oversight}
    end,
    PublicServiceDeskAllows=function(_,agency,service)
        return publicAtDesk and agency==nil and service=='government_notices'
    end,
    ps={registerCallback=function(name,fn) callbacks[name]=fn end},
    MySQL={
        query={await=function(sql,args)
            if sql:find("WHERE status = 'published'",1,true) then
                assert(args[1]==21 and args[2]%20==0, 'Public notices must paginate')
                local result={}
                for _,n in pairs(notices) do
                    if n.status=='published' then
                        result[#result+1]={id=n.id,agency=n.agency,jurisdiction=n.jurisdiction,
                            title=n.title,body=n.body}
                    end
                end
                return result
            end
            assert(sql:find('status =',1,true))
            assert(sql:find('agency = ?',1,true))
            assert(args[3]==51 and args[4]%50==0)
            local output={}
            for _,row in pairs(notices) do
                if row.status=='published' or row.agency==args[1] or args[2]==1 then
                    output[#output+1]=row
                end
            end
            return output
        end},
        startTransaction=function(callback)
            local state,count,id=snapshot()
            local ok,result=pcall(callback,transact)
            if not ok or result~=true then restore(state,count,id);return false end
            return true
        end
    }
},{__index=_G})
assert(loadfile('server/backend/government_jurisdiction_policy.lua','t',env))()
assert(loadfile('server/backend/government_notices.lua','t',env))()
local function call(name,payload)
    return assert(callbacks['ps-mdt:server:'..name],name)(1,payload)
end
local public=call('getPublicGovernmentNotices',{page=0})
assert(public.success and #public.notices==1 and public.notices[1].id==3,
    'Public counter must see only published notices')
publicAtDesk=false
assert(not call('getPublicGovernmentNotices',{page=0}).success,
    'Remote access to public notices must be denied')
publicAtDesk=true
local list=call('getGovernmentNotices',{page=0})
assert(list.success and #list.notices==2)
for _,n in ipairs(list.notices) do assert(n.id~=2,'Sibling draft leakage') end
assert(not list.canPublish and list.canManage)
assert(not call('getGovernmentNotices',{page=-1}).success)
assert(not call('getGovernmentNotices',{page=201}).success)
assert(not call('publishGovernmentNotice',{id=1,version=1}).success)
assert(not call('editGovernmentNotice',{id=2,version=1,title='Attack',body='Overwrite'}).success)
local created=call('createGovernmentNotice',{title='Blaine policy',body='Public meeting announcement'})
assert(created.success and notices[created.id].agency=='bcgov')
assert(notices[created.id].jurisdiction=='blaine_county' and #audits==1)
assert(call('editGovernmentNotice',{id=1,version=1,title='Revised',body='County only'}).success)
assert(notices[1].version==2 and #audits==2)
assert(not call('editGovernmentNotice',{id=1,version=1,title='Stale',body='No'}).success)
assert(notices[1].title=='Revised')
actor.publish=true
assert(call('publishGovernmentNotice',{id=1,version=2}).success)
assert(notices[1].status=='published' and #audits==3)
assert(not call('publishGovernmentNotice',{id=1,version=2}).success)
actor.manage=false
assert(not call('createGovernmentNotice',{title='No role',body='Not authorized'}).success)
actor.manage=true
actor.job='lscgov';actor.jurisdiction='los_santos_county'
actor.publish=true
assert(not call('editGovernmentNotice',{id=created.id,version=1,title='Cross',body='No'}).success)
assert(not call('publishGovernmentNotice',{id=created.id,version=1}).success)
actor.job='sagov';actor.jurisdiction='state';actor.manage=false;actor.publish=false;actor.oversight=true
local state=call('getGovernmentNotices',{page=0})
assert(state.success and #state.notices==4,'Explicit state oversight can read jurisdiction drafts')
assert(not call('publishGovernmentNotice',{id=2,version=1}).success,'Oversight is not publication')
actor.job='bcgov';actor.jurisdiction='blaine_county';actor.manage=true;actor.publish=true;actor.oversight=false
failAudit=true
assert(not call('createGovernmentNotice',{title='Rollback',body='No audit'}).success)
assert(not call('publishGovernmentNotice',{id=created.id,version=1}).success)
assert(notices[created.id].status=='draft')
failAudit=false
transferAtAudit=true
assert(not call('publishGovernmentNotice',{id=created.id,version=1}).success,
    'Job transfer before commit must roll back publication')
assert(notices[created.id].status=='draft')
actor.job='bcgov';actor.jurisdiction='blaine_county'
env.MySQL.startTransaction=nil
assert(not call('publishGovernmentNotice',{id=created.id,version=1}).success)
assert(notices[created.id].status=='draft')
print('PASS Stage 6 local drafts, state oversight, role-gated publishing, versioning and rollback')
