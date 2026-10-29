-- Stage 6: existing SAGOV MDT legislative actions, not slash commands.
local resourceName=tostring(GetCurrentResourceName())
for _,action in ipairs({
    'getGovernmentLegislation','createGovernmentMeasure','editGovernmentMeasure',
    'openGovernmentMeasureVote','castGovernmentOfficialVote',
    'getGovernmentOfficialVotes','certifyGovernmentMeasure',
    'publishGovernmentMeasure',
}) do
    RegisterNUICallback(action,function(data,cb)
        if not MDTOpen then
            cb({success=false,error='MDT is closed'})
            return
        end
        local reply=ps.callback(resourceName..':server:'..action,data or {})
        cb(reply or {success=false,error='Legislative service unavailable'})
    end)
end
