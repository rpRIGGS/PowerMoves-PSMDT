-- Stage 6 licensing lives inside SAGOV.net's existing MDT, not a separate UI.
local resourceName=tostring(GetCurrentResourceName())
local actions={
    getGovernmentBusinessLicenses='getGovernmentBusinessLicenses',
    decideGovernmentBusinessLicense='decideGovernmentBusinessLicense',
}
for nui,callback in pairs(actions) do
    RegisterNUICallback(nui,function(data,cb)
        if not MDTOpen then cb({success=false,error='MDT is closed'}) return end
        local reply=ps.callback(resourceName..':server:'..callback,data or {})
        cb(reply or {success=false,error='Licensing service unavailable'})
    end)
end
