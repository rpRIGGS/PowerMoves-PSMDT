-- Stage 6 jurisdiction/record visibility policy for the existing SAGOV MDT.
-- This helper grants no permissions by itself. Callers must authenticate actors
-- and prove explicit state oversight before passing hasStateOversight=true.
local function configuredJurisdictions()
    local access = Config and Config.MdtAccess or {}
    return access.GovernmentJurisdictions or {}
end

local function validJurisdiction(key)
    local jurisdictions = configuredJurisdictions()
    return type(key) == 'string' and key ~= ''
        and type(jurisdictions[key]) == 'table'
end

-- A valid rooted ancestor chain, not a county's default personnel entitlement.
-- Rejects missing parent definitions and circular config.
function GovernmentJurisdictionContains(ancestor, descendant)
    if not validJurisdiction(ancestor) or not validJurisdiction(descendant) then return false end
    local jurisdictions = configuredJurisdictions()
    local seen = {}
    local current = descendant
    while current do
        if seen[current] then return false end
        seen[current] = true
        if not validJurisdiction(current) then return false end
        if current == ancestor then return true end
        local parent = jurisdictions[current].parent
        if parent ~= nil and (type(parent) ~= 'string' or parent == current) then return false end
        current = parent
    end
    return false
end

-- Published/approved public records are visible across local governments.
-- Unpublished records are local-only, except for an explicitly authorized
-- state-office oversight role. County/city parentage NEVER grants visibility.
function CanViewGovernmentJurisdictionRecord(actorJob, targetJurisdiction, published, hasStateOversight)
    if not validJurisdiction(targetJurisdiction) then return false end
    if published == true then return true end
    local policy = Config and Config.MdtAccess or {}
    local jobs = policy.GovernmentJobs or {}
    local actorJurisdiction = type(actorJob) == 'string' and jobs[actorJob] or nil
    if not validJurisdiction(actorJurisdiction) then return false end
    if actorJurisdiction == targetJurisdiction then return true end
    if actorJob ~= 'sagov' or hasStateOversight ~= true then return false end
    return GovernmentJurisdictionContains(actorJurisdiction, targetJurisdiction)
end
