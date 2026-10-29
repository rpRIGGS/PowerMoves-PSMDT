-- Stage 5 client open lifecycle against mocked PSMDT/NUI events.
-- This runs without FiveM and verifies qb-target's event, not slash commands.
local nuiCallbacks, clientEvents = {}, {}
local openAttempts, tabletOpens, notifications, commands = 0, 0, 0, 0
local queueAllowed, acknowledge = true, true
local env
env = setmetatable({
    MDTOpen = false,
    GetCurrentResourceName = function() return 'ps-mdt' end,
    RegisterNUICallback = function(name, fn) nuiCallbacks[name] = fn end,
    RegisterNetEvent = function(name, fn) clientEvents[name] = fn end,
    RegisterCommand = function() commands = commands + 1 end,
    ps = {
        callback = function(name)
            assert(name == 'ps-mdt:server:getPublicRecordsOfficeQueue')
            return {success=queueAllowed, error=queueAllowed and nil or 'Not authorized'}
        end,
        notify = function() notifications = notifications + 1 end
    },
    OpenMDT = function() env.MDTOpen = true; tabletOpens = tabletOpens + 1 end,
    SendNUI = function(action)
        assert(action == 'openRecordsOffice')
        openAttempts = openAttempts + 1
        if acknowledge and openAttempts == 3 then
            local result
            nuiCallbacks.recordsOfficeReady({}, function(response) result = response end)
            assert(result and result.success == true)
        end
    end,
    CreateThread = function(fn) fn() end,
    Wait = function() end,
}, {__index = _G})
assert(loadfile('client/backend/public_records_office.lua', 't', env))()
local open = assert(clientEvents['ps-mdt:client:openRecordsOffice'])
assert(commands == 0, 'Records office cannot register a slash command')
open()
assert(tabletOpens == 1 and openAttempts == 3 and notifications == 0,
    'Client should retry event until authenticated NUI acknowledges')
assert(env.MDTOpen == true)
env.MDTOpen = false
queueAllowed = false
local previous = openAttempts
open()
assert(tabletOpens == 1 and openAttempts == previous and notifications == 1,
    'Denied staff must never open MDT records office')
queueAllowed = true
acknowledge = false
openAttempts = 0
open()
assert(tabletOpens == 2 and openAttempts == 25 and notifications == 2,
    'Missing NUI acknowledgement should be bounded and surfaced')
print('PASS Stage 5 target-to-MDT opening acknowledgement and no slash access')
