-- Read-only regression of production evidence SQL authorization predicates.
local callbacks, reads = {}, {}
local players = {
    [1] = { citizenid = 'CID-LSPD', agency = 'lspd', interfaceId = 'sadle', authorized = true },
    [2] = { citizenid = 'CID-COURT', agency = 'sadoj', interfaceId = 'sadoj', authorized = true },
    [3] = { citizenid = 'CID-OFF', agency = 'lspd', interfaceId = 'sadle', authorized = false },
}
local function collect(kind, sql, args)
    reads[#reads + 1] = { kind = kind, sql = sql, args = args }
    assert(sql:find('scoped_case.assigned_department = ?', 1, true), 'Case employer scope is required')
    assert(sql:find('mdt_evidence_items.created_by = ?', 1, true), 'Unlinked collector scope is required')
    if kind == 'count' then return {total = 0} end
    return {}
end
local env = setmetatable({
    GetCurrentResourceName = function() return 'ps-mdt' end,
    RegisterNetEvent = function() end,
    ps = {
        registerCallback = function(name, fn) callbacks[name] = fn end,
        getIdentifier = function(src) return players[src].citizenid end,
    },
    CheckAuth = function(src) return players[src] ~= nil and players[src].authorized end,
    CheckPermission = function(src, _) return players[src] ~= nil and players[src].authorized end,
    GetMdtAccess = function(src) return players[src] end,
    NormalizeSearch = function(_) return 'query', '%query%' end,
    MySQL = {
        single = { await = function(sql, args) return collect('count', sql, args) end },
        query = { await = function(sql, args) return collect('list', sql, args) end },
    },
}, {__index = _G})
assert(loadfile('server/backend/evidence.lua', 't', env))()
local function invoke(name, ...)
    return assert(callbacks['ps-mdt:server:' .. name])(...)
end
local first = invoke('getEvidenceItems', 1, 1, 10, {})
assert(first.success and first.data.total == 0)
assert(#reads == 2)
assert(reads[1].args[1] == 'lspd' and reads[1].args[2] == 0 and reads[1].args[3] == 'CID-LSPD')
reads = {}
local search = invoke('searchEvidenceItems', 2, 'query', 1, 10)
assert(search.success and search.data.total == 0)
assert(#reads == 2)
assert(reads[1].args[6] == 'sadoj' and reads[1].args[7] == 1 and reads[1].args[8] == 'CID-COURT')
reads = {}
assert(not invoke('getEvidenceItems', 3).success)
assert(#reads == 0)
print('PASS agency-scoped evidence reads and searches')
