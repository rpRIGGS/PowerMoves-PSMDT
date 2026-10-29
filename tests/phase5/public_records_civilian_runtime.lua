-- Stage 5 production citizen callbacks in a FiveM-free mock.
-- No user data is read or changed.
local callbacks, rows, responses = {}, {}, {}
local actor = {cid='CIV-A', nearDesk=true}
local now, nextId = 100000, 1
local changeCidDuringQuery, changeLocationDuringQuery = false, false
local env = setmetatable({
    GetCurrentResourceName=function() return 'ps-mdt' end,
    GetGameTimer=function() return now end,
    Config={PublicServices={Locations={{
        id='public_lspd', agency='lspd', services={'public_records_request','public_records_status'}
    }}}},
    PublicServiceDeskAllows=function(source, agency, service)
        assert(type(source)=='number' and source == 1, 'Use actual server source, not undefined src')
        return actor.nearDesk and (agency == nil or agency == 'lspd')
            and (service == 'public_records_request' or service == 'public_records_status')
    end,
    ps={
        registerCallback=function(name,fn) callbacks[name]=fn end,
        getIdentifier=function() return actor.cid end,
    },
    MySQL={
        insert={await=function(sql,args)
            assert(sql:find('INSERT INTO mdt_public_record_requests',1,true))
            local id=nextId; nextId=nextId+1
            rows[id]={id=id,cid=args[1],agency=args[2],subject=args[3],status='submitted'}
            return id
        end},
        update={await=function(sql,args)
            local row=rows[args[2]]
            if not row or row.cid~=args[3] then return 0 end
            row.number=args[1]
            return 1
        end},
        query={await=function(sql,args)
            assert(sql:find('WHERE applicant_citizenid = ?',1,true))
            local list={}
            for _, row in pairs(rows) do
                if row.cid==args[1] then
                    list[#list+1]={request_number=row.number,agency=row.agency,status=row.status,subject=row.subject}
                end
            end
            if changeCidDuringQuery then actor.cid='CIV-CHANGED'; changeCidDuringQuery=false end
            if changeLocationDuringQuery then actor.nearDesk=false; changeLocationDuringQuery=false end
            return list
        end},
        single={await=function(sql,args)
            assert(sql:find('r.applicant_citizenid = ?',1,true))
            for _, row in pairs(rows) do
                if row.number==args[1] and row.cid==args[2] and (row.status=='approved' or row.status=='denied')
                    and responses[row.id] then
                    return {request_number=row.number,response_text=responses[row.id]}
                end
            end
            return nil
        end}
    }
}, {__index=_G})
assert(loadfile('server/backend/public_records.lua','t',env))()
local function call(name, payload)
    return assert(callbacks['ps-mdt:server:'..name],name)(1,payload)
end
local a=call('submitPublicRecordRequest',{agency='lspd',subject='Public charter',description='Requested document'})
assert(a.success and a.requestNumber:find('PR-',1,true)==1)
assert(not call('submitPublicRecordRequest',{agency='lspd',subject='Duplicate',description='Second request'}).success)
now=now+61000
assert(not call('submitPublicRecordRequest',{agency='bcso',subject='Wrong agency',description='Invalid target'}).success)
actor.nearDesk=false
assert(not call('submitPublicRecordRequest',{agency='lspd',subject='Remote',description='No public counter'}).success)
actor.nearDesk=true
assert(#call('getMyPublicRecordRequests')==1)
rows[1].status='approved';responses[1]='Publicly approved text'
assert(call('getMyPublicRecordsResponse',a.requestNumber).success)
rows[1].status='denied';responses[1]='Public denial explanation'
assert(call('getMyPublicRecordsResponse',a.requestNumber).response.response_text=='Public denial explanation',
    'Only the original applicant may read denial notices')
actor.cid='CIV-B'
assert(#call('getMyPublicRecordRequests')==0, 'Different character must not see first applicant')
assert(not call('getMyPublicRecordsResponse',a.requestNumber).success,
    'Guessing tracking number must not grant read')
actor.cid='CIV-A'
changeCidDuringQuery=true
assert(#call('getMyPublicRecordRequests')==0,'Identity change during query must deny response')
actor.cid='CIV-A'
changeLocationDuringQuery=true
assert(#call('getMyPublicRecordRequests')==0,'Leaving public counter during query must deny response')
actor.nearDesk=false
assert(not call('getMyPublicRecordsResponse',a.requestNumber).success,'Remote direct read must be denied')
print('PASS Stage 5 civilian intake, cooldown, counter, owner and mid-read isolation')
