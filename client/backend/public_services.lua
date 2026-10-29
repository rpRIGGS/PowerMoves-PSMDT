-- In-world civilian public service desks. Uses existing PSMDT forms,
-- not a second MDT or a civilian government role.
local registeredZones = {}

local resourceName = tostring(GetCurrentResourceName())

local function publicRecordsDialog(agency)
    if not lib or not lib.inputDialog then return end
    local fields = lib.inputDialog('Public Records Request — ' .. agency, {
        {type = 'input', label = 'Records requested', description = 'Brief subject', required = true, max = 160},
        {type = 'textarea', label = 'Describe the records', required = true, max = 4000},
    })
    if not fields then return end
    local result = ps.callback(resourceName .. ':server:submitPublicRecordRequest', {
        agency = agency, subject = fields[1], description = fields[2],
    })
    if lib.notify then lib.notify({
        title = result and result.success and 'Request submitted' or 'Request not submitted',
        description = result and (result.requestNumber or result.error) or 'Service unavailable',
        type = result and result.success and 'success' or 'error',
    }) end
end

-- Browse explicit public-safe copies at a configured service counter.
-- The server checks applicant ownership, expiry, revocation and proximity.
local function myPublicReleaseCopies(requests)
    if not lib or not lib.inputDialog or not lib.alertDialog then return end
    local choices = {}
    for _, item in ipairs(requests or {}) do
        if item.status == 'approved' and type(item.request_number) == 'string' then
            choices[#choices + 1] = {
                value = item.request_number,
                label = item.request_number .. ' — ' .. tostring(item.subject or ''),
            }
        end
    end
    if #choices == 0 then return end
    local selected = lib.inputDialog('View Public Release Copies', {
        {type = 'select', label = 'Approved request', options = choices, required = true}
    })
    if not selected then return end
    local result = ps.callback(resourceName .. ':server:getMyPublicReleaseCopies', selected[1])
    if not result or not result.success then
        lib.notify({title = 'Records Office', description = result and result.error or 'Copies unavailable', type = 'error'})
        return
    end
    local copies = result.copies or {}
    if #copies == 0 then
        lib.alertDialog({header = 'Public Release Copies', content = 'No currently valid public copies for that request.'})
        return
    end
    local options = {}
    for _, copy in ipairs(copies) do
        options[#options + 1] = {
            value = tostring(copy.id),
            label = tostring(copy.title) .. ' (expires ' .. tostring(copy.expires_at) .. ')'
        }
    end
    local chosen = lib.inputDialog('Read Public Release Copy', {
        {type = 'select', label = 'Available copies', options = options, required = true}
    })
    if not chosen then return end
    for _, copy in ipairs(copies) do
        if tostring(copy.id) == tostring(chosen[1]) then
            lib.alertDialog({
                header = tostring(copy.title),
                content = tostring(copy.public_text or ''),
            })
            return
        end
    end
end

local function myPublicRecordRequests()
    local result = ps.callback(resourceName .. ':server:getMyPublicRecordRequests')
    if not lib or not lib.alertDialog then return end
    if type(result) ~= 'table' or #result == 0 then
        lib.alertDialog({header = 'My Public Records Requests', content = 'No requests found.'})
        return
    end
    local lines = {}
    for _, row in ipairs(result) do
        lines[#lines + 1] = ('**%s** — %s (%s)\n%s'):format(
            tostring(row.request_number or 'Pending'),
            tostring(row.subject or ''), tostring(row.status or 'submitted'),
            tostring(row.agency or ''))
    end
    lib.alertDialog({header = 'My Public Records Requests', content = table.concat(lines, '\n\n')})
    local completed = {}
    for _, item in ipairs(result) do
        if (item.status == 'approved' or item.status == 'denied')
            and type(item.request_number) == 'string' then
            completed[#completed + 1] = {
                label = item.request_number .. ' (' .. tostring(item.status) .. ') — ' .. tostring(item.subject or ''),
                value = item.request_number
            }
        end
    end
    if #completed > 0 and lib.inputDialog then
        local selection = lib.inputDialog('Read a records-office decision', {
            {type = 'select', label = 'Completed request', options = completed, required = true}
        })
        if selection then
            local response = ps.callback(resourceName .. ':server:getMyPublicRecordsResponse', selection[1])
            if response and response.success and response.response then
                lib.alertDialog({header = 'Public records response', content = tostring(response.response.response_text)})
            else
                lib.notify({title = 'Records response', description = 'Response unavailable', type = 'error'})
            end
        end
    end
    -- Separate from the administrative decision notice: approved requests may
    -- have one or more active, time-limited, explicitly authored public copies.
    myPublicReleaseCopies(result)
end

local function publicGovernmentNotices()
    if not lib or not lib.inputDialog or not lib.alertDialog then return end
    local page = 0
    while page >= 0 and page <= 200 do
        local response = ps.callback(resourceName .. ':server:getPublicGovernmentNotices', {page=page})
        if not response or response.success ~= true then
            lib.notify({title='Government Notices',
                description=response and response.error or 'Notice service unavailable',
                type='error'})
            return
        end
        local items = type(response.notices)=='table' and response.notices or {}
        local options = {}
        for index, item in ipairs(items) do
            options[#options+1] = {
                value = tostring(index),
                label = tostring(item.title or 'Public notice') .. ' — '
                    .. tostring(item.jurisdiction or '')
            }
        end
        if page > 0 then options[#options+1] = {value='previous',label='Previous page'} end
        if response.hasMore then options[#options+1] = {value='next',label='Next page'} end
        if #options == 0 then
            lib.alertDialog({header='Government Public Notices',
                content='No published notices are available.'})
            return
        end
        local selection = lib.inputDialog('Government Public Notices', {
            {type='select',label='Published notices — page ' .. (page+1),
                options=options,required=true}
        })
        if not selection then return end
        if selection[1]=='next' then
            page=page+1
        elseif selection[1]=='previous' then
            page=page-1
        else
            local index=tonumber(selection[1])
            local item=index and items[index] or nil
            if item then
                lib.alertDialog({
                    header=tostring(item.title or 'Public notice'),
                    content=tostring(item.body or ''),
                })
            end
        end
    end
end

-- Public licensing uses exactly the same configured qb-target counter zones
-- as IA and records requests. It does not create a business or charge a fee.
local function applyForBusinessLicense(agency)
    if not lib or not lib.inputDialog then return end
    local fields=lib.inputDialog('Local Business License — ' .. tostring(agency), {
        {type='input',label='Business name',required=true,max=160},
        {type='input',label='Business type',required=true,max=80},
        {type='textarea',label='Proposed business activity',required=true,max=4000},
        {type='input',label='Property reference (optional)',max=120},
    })
    if not fields then return end
    local result=ps.callback(resourceName..':server:applyForBusinessLicense',{
        agency=agency,name=fields[1],businessType=fields[2],
        description=fields[3],propertyReference=fields[4] or '',
    })
    if lib.notify then lib.notify({
        title=result and result.success and 'License application received' or 'License application rejected',
        description=result and (result.success and 'Application #' .. tostring(result.applicationId)
            or result.error) or 'Licensing office unavailable',
        type=result and result.success and 'success' or 'error'
    }) end
end
local function myBusinessLicenseApplications()
    if not lib or not lib.alertDialog then return end
    local result=ps.callback(resourceName..':server:getMyBusinessLicenseApplications')
    if not result or not result.success then
        lib.notify({title='Business Licensing',description=result and result.error or 'Unavailable',type='error'})
        return
    end
    local rows=result.applications or {}
    if #rows==0 then
        lib.alertDialog({header='My Business Licenses',content='No applications found.'})
        return
    end
    local details={}
    for _,item in ipairs(rows) do
        details[#details+1]=('**%s** — %s (%s)\\nAuthority: %s\\nLicense: %s\\nDecision: %s')
            :format(tostring(item.business_name),tostring(item.status),
                tostring(item.id),tostring(item.agency),
                tostring(item.license_number or 'Not issued'),
                tostring(item.decision_reason or 'Awaiting review'))
    end
    lib.alertDialog({header='My Business Licenses',content=table.concat(details,'\\n\\n')})
end

local serviceHandlers = {
    business_license_apply = {
        label='Apply for Local Business License',
        icon='fas fa-store',
        open=function(location) applyForBusinessLicense(location.agency) end,
    },
    business_license_status = {
        label='My Business License Applications',
        icon='fas fa-id-card',
        open=function() myBusinessLicenseApplications() end,
    },
    government_notices = {
        label = 'Government Public Notices',
        icon = 'fas fa-landmark',
        open = function() publicGovernmentNotices() end,
    },
    records_office = {
        label = 'Records Office',
        icon = 'fas fa-folder-open',
        open = function()
            TriggerEvent('ps-mdt:client:openRecordsOffice')
        end,
    },
    public_records_request = {
        label = 'Request Public Records',
        icon = 'fas fa-file-lines',
        open = function(location)
            publicRecordsDialog(location.agency)
        end,
    },
    public_records_status = {
        label = 'My Records Requests',
        icon = 'fas fa-list-check',
        open = function()
            myPublicRecordRequests()
        end,
    },
    ia_complaint = {
        label = 'File Internal Affairs Complaint',
        icon = 'fas fa-file-circle-exclamation',
        open = function()
            -- Reuse the exact /complaint and openComplaint entry point.
            TriggerEvent('ps-mdt:client:openComplaint')
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
        if service and (serviceId == 'public_records_request'
            or serviceId == 'business_license_apply')
            and (type(location.agency) ~= 'string' or location.agency == '') then
            log('Skipping records request at a location with no receiving agency: ' .. tostring(location.id))
        elseif service then
            options[#options + 1] = {
                icon = service.icon,
                label = service.label,
                action = function() service.open(location) end,
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

    if location.shape ~= 'poly' and location.shape ~= 'circle' and location.shape ~= nil then
        log('Unsupported public service zone shape at ' .. location.id)
        return
    end

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
        -- The target resource loses its zones on restart; our Lua state does not.
        -- Clear stale registration markers before restoring configured service desks.
        registeredZones = {}
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
