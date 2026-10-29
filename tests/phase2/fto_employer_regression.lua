-- Stage 2 FTO employer isolation. Production server callback, mocked framework/SQL.
local callbacks, reads = {}, {}
local actor = { job = 'lspd', domain = 'police', cid = 'CID-A', authorized = true }
local rows = {}
local env = setmetatable({
    GetCurrentResourceName = function() return 'ps-mdt' end,
    CreateThread = function() end,
    Config = { DojJobs = {} },
    ps = {
        registerCallback = function(name, fn) callbacks[name] = fn end,
        getJobName = function() return actor.job end,
        getJobType = function() return 'leo' end,
        getIdentifier = function() return actor.cid end,
    },
    CheckAuth = function() return actor.authorized end,
    CheckPermission = function() return true end,
    CanManageMdtPersonnel = function(_, citizenid)
        return citizenid == 'CID-TRAINER' or citizenid == 'CID-TRAINEE'
    end,
    GetMdtDomain = function() return actor.domain end,
    MySQL = {
        query = { await = function(sql, args)
            reads[#reads + 1] = {sql=sql,args=args}
            if sql:find('FROM mdt_fto_assignments a',1,true) then
                assert(sql:find('a.agency_job = ?',1,true), 'FTO list must bind exact employer')
                assert(not sql:find('a.agency_job IS NULL',1,true), 'NULL employer must not enter manager view')
                assert(args[1] == actor.domain and args[2] == 'lspd', 'Wrong employer scope')
                return rows
            end
            return {}
        end },
        single = { await = function(sql, args)
            if sql:find('SELECT a.*, p.name',1,true) then
                return rows[1]
            end
            return nil
        end },
    },
}, {__index = _G})
assert(loadfile('server/backend/fto.lua', 't', env))()
local function invoke(name, ...) return assert(callbacks['ps-mdt:server:' .. name])(...) end
rows = {{id=5,job_type='police',agency_job='lspd',trainee_citizenid='CID-B',trainer_citizenid='CID-C'}}
local list = invoke('getFTOList', 1, 1, {})
assert(#list.entries == 1)
local entry = invoke('getFTO', 1, 5)
assert(entry.success, 'Own agency record should be accessible')
rows[1].agency_job = nil
assert(not invoke('getFTO', 1, 5).success, 'NULL legacy owner must be withheld')
rows[1].agency_job = 'bcso'
assert(not invoke('getFTO', 1, 5).success, 'Other agency record must be withheld')
rows[1].agency_job = 'lspd'
rows = {{id=5,job_type='police',agency_job='lspd'}}
-- A player changing employer during the list query cannot see old employer results.
local original = env.MySQL.query.await
env.MySQL.query.await = function(sql,args)
    local result = original(sql,args)
    actor.job = 'bcso'
    return result
end
assert(#invoke('getFTOList',1,1,{}).entries == 0, 'Employer transfer must invalidate query')
actor.job = 'lspd'
local transcript = assert(callbacks['ps-mdt:server:getMyTrainingTranscript'])
env.MySQL.query.await = function(sql,args)
    if sql:find('WHERE a.trainee_citizenid = ?',1,true) then
        assert(args[1]=='CID-A')
        actor.cid='CID-CHANGED'
        return {{fto_number='FTO-OLD',status='completed'}}
    end
    return original(sql,args)
end
assert(#transcript(1)==0, 'Character switch must invalidate permanent milestone transcript')
actor.cid='CID-A'
actor.job, actor.cid = 'lspd', 'CID-A'
local rosterHistory = assert(callbacks['ps-mdt:server:getOfficerFTOHistory'])
env.MySQL.query.await = function(sql,args)
    assert(sql:find('a.agency_job = ?',1,true), 'Roster DOR history must restrict employer')
    assert(sql:find('a.job_type = ?',1,true), 'Roster DOR history must restrict domain')
    assert(args[1]=='CID-A' and args[2]=='police' and args[3]=='lspd')
    return {{id=8, latest_rating=4}}
end
assert(#rosterHistory(1,'CID-A')==1, 'Current employer history remains available')
env.MySQL.query.await = function(sql,args)
    actor.job='bcso'
    return {{id=8, latest_rating=4}}
end
assert(#rosterHistory(1,'CID-A')==0, 'Employer transfer must suppress former DOR scores')
local create = assert(callbacks['ps-mdt:server:createFTOAssignment'])
assert(not create(1,{trainee_citizenid='OTHER-AGENCY',trainer_citizenid='CID-TRAINER'}).success,
    'Managers must not enroll trainees from other departments')
assert(not create(1,{trainee_citizenid='CID-TRAINEE',trainer_citizenid='OTHER-AGENCY'}).success,
    'Managers must not appoint outside field trainers')
print('PASS FTO employer scopes, confidential DOR ratings and same-department training checks')
