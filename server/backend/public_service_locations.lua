-- Stage 5 public-service location policy. All access checks are server-side.
-- Client qb-target interaction is presentation only, never authorization.
local function serviceEnabled(location, serviceId)
    if type(location.services) ~= 'table' then return false end
    for _, id in ipairs(location.services) do
        if id == serviceId then return true end
    end
    return false
end

local function inPolygon(x, y, points)
    if type(points) ~= 'table' or #points < 3 then return false end
    local inside = false
    local j = #points
    for i = 1, #points do
        local a, b = points[i], points[j]
        if not a or not b or type(a.x) ~= 'number' or type(a.y) ~= 'number'
            or type(b.x) ~= 'number' or type(b.y) ~= 'number' then return false end
        if (a.y > y) ~= (b.y > y) then
            local crossing = (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x
            if x < crossing then inside = not inside end
        end
        j = i
    end
    return inside
end

-- Restrict services to configured counter zones. An agency argument of nil
-- permits a citizen to check their own status at any registered status desk.
function PublicServiceDeskAllows(src, agency, serviceId)
    local cfg = Config and Config.PublicServices
    if not cfg or cfg.Enabled ~= true or type(cfg.Locations) ~= 'table' then return false end
    if type(src) ~= 'number' or src < 1 or type(serviceId) ~= 'string' then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    if not pos or type(pos.x) ~= 'number' or type(pos.y) ~= 'number'
        or type(pos.z) ~= 'number' then return false end
    for _, place in ipairs(cfg.Locations) do
        if type(place) == 'table' and (agency == nil or place.agency == agency)
            and serviceEnabled(place, serviceId) then
            if place.shape == 'poly' then
                local low, high = tonumber(place.minZ), tonumber(place.maxZ)
                if low and high and high > low and pos.z >= low and pos.z <= high
                    and inPolygon(pos.x, pos.y, place.points) then return true end
            elseif place.shape == 'circle' or place.shape == nil then
                local center = place.coords
                if center and type(center.x) == 'number' and type(center.y) == 'number'
                    and type(center.z) == 'number' then
                    local radius = tonumber(place.radius) or 1.5
                    local reach = tonumber(place.distance) or tonumber(cfg.DefaultDistance) or 2.0
                    if radius > 0 and reach > 0 and math.abs(pos.z - center.z) <= 3.0 then
                        local dx, dy = pos.x - center.x, pos.y - center.y
                        if dx * dx + dy * dy <= (radius + reach) ^ 2 then return true end
                    end
                end
            end
        end
    end
    return false
end
