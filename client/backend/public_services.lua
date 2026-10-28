-- In-world civilian public service desks. Uses existing PSMDT forms,
-- not a second MDT or a civilian government role.
local registeredZones = {}

local serviceHandlers = {
    ia_complaint = {
        label = 'File Internal Affairs Complaint',
        icon = 'fas fa-file-circle-exclamation',
        open = function()
            -- Existing civilian form remains the single implementation.
            if GetResourceState(GetCurrentResourceName()) ~= 'started' then return end
            SendNUIMessage({ action = 'showComplaintForm', data = {} })
            SetNuiFocus(true, true)
        end,
    },
}

local function log(message)
    if Config and Config.PublicServices and Config.PublicServices.Debug then
        print('[ps-mdt] Public services: ' .. message)
    end
end

local function finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function validCoords(coords)
    return coords and finite(coords.x) and finite(coords.y) and finite(coords.z)
end

local function getOptions(location)
    local options = {}
    local services = type(location.services) == 'table' and location.services or {}
    for _, serviceId in ipairs(services) do
        local service = serviceHandlers[serviceId]
        if service then
            options[#options + 1] = {
                icon = service.icon,
                label = service.label,
                action = service.open,
            }
        else
            log(('Service %s is not yet implemented; not showing it at %s'):format(
                tostring(serviceId), tostring(location.id)))
        end
    end
    return options
end

local function addLocation(target, location, defaults)
    if type(location) ~= 'table' or type(location.id) ~= 'string'
        or location.id == '' then return end
    local options = getOptions(location)
    if #options == 0 then return end
    local radius = tonumber(location.radius) or 1.5
    local distance = tonumber(location.distance) or tonumber(defaults.DefaultDistance) or 2.0
    if not finite(distance) or distance <= 0 then distance = 2.0 end
    if not finite(radius) or radius <= 0 then radius = 1.5 end

    local name = 'psmdt_public_' .. location.id
    if registeredZones[name] then return end
    local debugPoly = defaults.Debug == true
    local ok = false

    if location.shape == 'poly' then
        local points = location.points
        if type(points) ~= 'table' or #points < 3
            or not finite(tonumber(location.minZ))
            or not finite(tonumber(location.maxZ))
            or tonumber(location.maxZ) <= tonumber(location.minZ) then
            log('Invalid polygon ' .. location.id)
            return
        end
        for _, point in ipairs(points) do
            if not point or not finite(point.x) or not finite(point.y) then
                log('Invalid polygon point at ' .. location.id)
                return
            end
        end
        ok = pcall(function()
            target:AddPolyZone(name, points, {
                name = name, minZ = tonumber(location.minZ),
                maxZ = tonumber(location.maxZ), debugPoly = debugPoly,
            }, { options = options, distance = distance })
        end)
    else
        if not validCoords(location.coords) then
            log('Missing vector3 coords for ' .. location.id)
            return
        end
        ok = pcall(function()
            target:AddCircleZone(name, location.coords, radius, {
                name = name, useZ = true, debugPoly = debugPoly,
            }, { options = options, distance = distance })
        end)
    end
    if ok then
        registeredZones[name] = true
        log('Registered ' .. name)
    else
        log('Failed to register ' .. name .. ' with qb-target')
    end
end

local function registerPublicLocations()
    local settings = Config and Config.PublicServices
    if not settings or settings.Enabled ~= true then return end
    local resource = settings.TargetResource or 'qb-target'
    if GetResourceState(resource) ~= 'started' then
        log('Target resource is not started: ' .. resource)
        return
    end
    local target = exports[resource]
    for _, location in ipairs(settings.Locations or {}) do
        addLocation(target, location, settings)
    end
end

CreateThread(function()
    Wait(1000)
    registerPublicLocations()
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    local settings = Config and Config.PublicServices
    if settings and resourceName == (settings.TargetResource or 'qb-target') then
        Wait(250)
        registerPublicLocations()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    local settings = Config and Config.PublicServices
    local targetResource = settings and settings.TargetResource or 'qb-target'
    if GetResourceState(targetResource) ~= 'started' then return end
    for name in pairs(registeredZones) do
        pcall(function() exports[targetResource]:RemoveZone(name) end)
    end
end)
