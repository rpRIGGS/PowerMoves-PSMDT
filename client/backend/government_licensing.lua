-- Stage 6: government staff management remains inside SAGOV.net on same MDT.
local resourceName = tostring(GetCurrentResourceName())
local callbacks = {
    getGovernmentLicenseQueue = 'getGovernmentLicenseQueue',
    decideGovernmentLicense = 'decideGovernmentLicense',
}
for name, target in pairs(callbacks) do
    RegisterNUICallback(name, function(data, cb)
        if not MDTOpen then
            cb({success=false, error='MDT is closed'})
            return
        end
        local result = ps.callback(resourceName .. ':server:' .. target, data or {})
        cb(result or {success=false, error='Government licensing unavailable'})
    end)
end
