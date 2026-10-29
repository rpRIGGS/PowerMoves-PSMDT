-- Government notices live inside the existing SAGOV MDT.
-- NUI callbacks never trust job, jurisdiction or user-supplied role assertions.
local resourceName = tostring(GetCurrentResourceName())
local callbacks = {
    getGovernmentNotices = 'getGovernmentNotices',
    createGovernmentNotice = 'createGovernmentNotice',
    editGovernmentNotice = 'editGovernmentNotice',
    publishGovernmentNotice = 'publishGovernmentNotice',
}
for name, callback in pairs(callbacks) do
    RegisterNUICallback(name, function(data, cb)
        if not MDTOpen then
            cb({success=false, error='MDT is closed'})
            return
        end
        local result = ps.callback(resourceName .. ':server:' .. callback, data or {})
        cb(result or {success=false, error='Government notice service unavailable'})
    end)
end
