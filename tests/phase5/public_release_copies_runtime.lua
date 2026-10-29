-- Stage 5 callback regressions using production source and mocked SQL transactions.
-- Exercises explicitly granted release copies; no FiveM or database mutation.
local callbacks = {}
local actor = {cid='OFFICER-A', job='lspd', duty=true, atDesk=true}
local requests = {
    [1]={id=1,agency='lspd',status='approved',applicant_citizenid='CIV-A',request_number='PR-1'},
    [2]={id=2,agency='bcso',status='approved',applicant_citizenid='CIV-B',request_number='PR-2'},
    [3]={id=3,agency='lspd',status='under_review',applicant_citizenid='CIV-A',request_number='PR-3'},
}
local copies, audits, nextId = {}, {}, 1
local failAudit = false
local function copySnapshot()
    local result={}
    for id,v in pairs(copies) do
        result[id]={id=v.id,request_id=v.request_id,agency=v.agency,recipient=v.recipient,
            title=v.title,public_text=v.public_text,days=v.days,revoked=v.revoked}
    end
    return result
end
local function txQuery(sql, args)
    if sql:find('SELECT applicant_citizenid, status FROM mdt_public_record_requests',1,true) then
        local r=requests[args[1]]
        return r and r.agency==args[2] and {r} or {}
    end
    if sql:find('SELECT COUNT(*) AS total FROM mdt_public_record_release_copies',1,true) then
        local total=0
        for _,c in pairs(copies) do if c.request_id==args[1] and c.agency==args[2] then total=total+1 end end
        return {{total=total}}
    end
    if sql:find('INSERT INTO mdt_public_record_release_copies',1,true) then
        local id=nextId
        nextId=nextId+1
        copies[id]={id=id,request_id=args[1],agency=args[2],recipient=args[3],
            title=args[4],public_text=args[5],days=args[7],revoked=false}
        return {affectedRows=1,insertId=id}
    end
    if sql:find('SELECT c.request_id, c.revoked_at',1,true) then
        local c=copies[args[1]]
        if not c or c.agency~=args[2] then return {} end
        return {{request_id=c.request_id,revoked_at=c.revoked and 'now' or nil}}
    end
    if sql:find('UPDATE mdt_public_record_release_copies',1,true) then
        local c=copies[args[3]]
        if not c or c.agency~=args[4] or c.revoked then return {affectedRows=0} end
        c.revoked=true
        return {affectedRows=1}
    end
    if sql:find('INSERT INTO mdt_public_record_request_audit',1,true) then
        if failAudit then return {affectedRows=0} end
        audits[#audits+1]={id=args[1],action=sql:find('release_revoked',1,true) and 'release_revoked' or 'release_issued'}
        return {affectedRows=1}
    end
    error('Unrecognized transaction query: '..sql)
end

local env=setmetatable({
    GetCurrentResourceName=function()return 'ps-mdt'end,
    Config={PublicServices={RecordsOfficers={lspd={['OFFICER-A']=true}}}},
    CheckAuth=function()return actor.duty and actor.job=='lspd'end,
    PublicServiceDeskAllows=function(_,job,service)
        return actor.atDesk and ((service=='records_office' and job==actor.job)
            or (service=='public_records_status' and job==nil))
    end,
    ps={
        registerCallback=function(name,fn)callbacks[name]=fn end,
        getIdentifier=function()return actor.cid end,
        getJobName=function()return actor.job end
    },
    MySQL={
        query={await=function(sql,args)
            local result={}
            if sql:find('FROM mdt_public_record_release_copies c',1,true) then
                local isCitizen=sql:find('r.request_number = ?',1,true)~=nil
                for _,c in pairs(copies) do
                    local request=requests[c.request_id]
                    local permitted=isCitizen
                        and request.request_number==args[1] and request.applicant_citizenid==args[2]
                        and c.recipient==args[2] and request.status=='approved'
                        and not c.revoked and c.days>0
                        or not isCitizen and c.request_id==args[1] and c.agency==args[2]
                        and request.status=='approved'
                    if permitted then
                        result[#result+1]={id=c.id,title=c.title,public_text=c.public_text,expires_at='date',
                            revoked_at=c.revoked and 'now' or nil}
                    end
                end
                return result
            end
            return {}
        end},
        startTransaction=function(callback)
            local original=copySnapshot()
            local originalAudits=#audits
            local originalId=nextId
            local ok,result=pcall(callback,txQuery)
            if not ok or result==false then
                copies=original
                nextId=originalId
                while #audits>originalAudits do table.remove(audits) end
                return false
            end
            return true
        end
    }
},{__index=_G})

assert(loadfile('server/backend/public_records_review.lua','t',env))()
assert(loadfile('server/backend/public_records.lua','t',env))()
local function call(name,data)
    return assert(callbacks['ps-mdt:server:'..name],name)(1,data)
end
local issue={id=1,title='Redacted public policy',publicText='Safe release copy',expiresInDays=30}
assert(call('issuePublicReleaseCopy',issue).success)
assert(#audits==1 and copies[1].recipient=='CIV-A' and copies[1].days==30)
assert(not call('issuePublicReleaseCopy',{id=3,title='Premature',publicText='No',expiresInDays=30}).success)
assert(not call('issuePublicReleaseCopy',{id=2,title='Other agency',publicText='No',expiresInDays=30}).success)
assert(not call('issuePublicReleaseCopy',{id=1,title='Invalid expiry',publicText='No',expiresInDays=366}).success)
assert(not call('issuePublicReleaseCopy',{id=1,title='Bad expiry',publicText='No',expiresInDays=0}).success)
assert(#call('getPublicReleaseCopiesForOfficer',1).copies==1)
assert(#call('getPublicReleaseCopiesForOfficer',2).copies==0)

actor.cid='CIV-A';actor.job='civilian';actor.duty=false
assert(#call('getMyPublicReleaseCopies','PR-1').copies==1)
actor.cid='CIV-B'
assert(#call('getMyPublicReleaseCopies','PR-1').copies==0)
actor.cid='CIV-A';actor.atDesk=false
assert(not call('getMyPublicReleaseCopies','PR-1').success)
actor.atDesk=true
actor.cid='OFFICER-A';actor.job='lspd';actor.duty=true
failAudit=true
assert(not call('issuePublicReleaseCopy',issue).success)
assert(#audits==1 and copies[2]==nil,'Failed audit must roll back a new release')
assert(not call('revokePublicReleaseCopy',{copyId=1,reason='Withdrawn'}).success)
assert(copies[1].revoked==false and #audits==1,'Failed revocation audit must roll back')
failAudit=false
assert(call('revokePublicReleaseCopy',{copyId=1,reason='Corrected'}).success)
assert(copies[1].revoked==true and #audits==2)
assert(not call('revokePublicReleaseCopy',{copyId=1,reason='Duplicate'}).success)
actor.cid='CIV-A';actor.job='civilian';actor.duty=false
assert(#call('getMyPublicReleaseCopies','PR-1').copies==0,'Revoked copies must be unreadable')
print('PASS Stage 5 release copy issue, expiration input, agency/citizen isolation and revocation')
