-- Government SOP may read only its actual employer's categories and settings.
-- Database and framework calls are mocked; no live data is changed.
local callbacks, queries, writes = {}, {}, 0
local actors = {
    [1] = { job = 'bcgov', agency = 'bcgov', interfaceId = 'sagov', jobType = 'gov', authorized = true },
    [2] = { job = 'lscgov', agency = 'lscgov', interfaceId = 'sagov', jobType = 'gov', authorized = false },
    [3] = { job = 'sagov', agency = 'sagov', interfaceId = 'sadle', jobType = 'gov', authorized = true },
    [4] = { job = 'lspd', agency = 'lspd', interfaceId = 'sadle', jobType = 'leo', authorized = true },
}
local env = setmetatable({
    GetCurrentResourceName = function() return 'ps-mdt' end,
    ps = {
        registerCallback = function(name, fn) callbacks[name] = fn end,
        getJobName = function(src) return actors[src].job end,
    },
    CheckAuth = function(src) return actors[src] and actors[src].jobType == 'leo' end,
    GetMdtAccess = function(src)
        return actors[src] or { authorized = false }
    end,
    MySQL = {
        query = { await = function(query, args)
            assert(query:find('FROM mdt_sop_', 1, true))
            queries[#queries + 1] = { sql = query, args = args }
            if query:find('FROM mdt_sop_categories', 1, true) then
                return { {id = 17, title = 'Department Guide', icon = 'book', sort_order = 1} }
            end
            return { {id = 19, title = 'Attendance', content = 'Read only', sort_order = 1} }
        end },
        single = { await = function(query, args)
            queries[#queries + 1] = {sql = query, args = args}
            return { job = args[1], mission_statement = 'Department-specific policy', version = 2 }
        end },
        insert = { await = function() writes = writes + 1; error('unexpected write') end },
        update = { await = function() writes = writes + 1; error('unexpected write') end },
    },
}, { __index = _G })
assert(loadfile('server/backend/sop.lua', 't', env))()
local function invoke(name, source, ...)
    return assert(callbacks['ps-mdt:server:' .. name])(source, ...)
end
local categories = invoke('getSOPCategories', 1)
assert(#categories == 1 and categories[1].sections[1].title == 'Attendance')
assert(queries[1].args[1] == 'bcgov')
assert(invoke('getSOPSettings', 1).job == 'bcgov')
local before = #queries
assert(#invoke('getSOPCategories', 2) == 0)
assert(#invoke('getSOPCategories', 3) == 0)
assert(#queries == before, 'Unauthorized GOV should not query private SOP')
assert(not invoke('createSOPCategory', 1, { title = 'Injected' }).success)
assert(not invoke('updateSOPMission', 1, 'Injected').success)
assert(writes == 0)
assert(#invoke('getSOPCategories', 4) == 1)
assert(queries[#queries - 1].args[1] == 'lspd')
print('PASS government read-only SOP access is employer scoped')
