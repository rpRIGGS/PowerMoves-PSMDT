-- State Tax Assessor functionality in the existing SAGOV MDT.
local resourceName=tostring(GetCurrentResourceName())
for _,name in ipairs({
    'getGovernmentPropertyAssessments',
    'queueGovernmentPropertyAssessment',
    'decideGovernmentPropertyAssessment',
}) do
    RegisterNUICallback(name,function(data,cb)
        if not MDTOpen then cb({success=false,error='MDT is closed'}) return end
        local reply=ps.callback(resourceName..':server:'..name,data or {})
        cb(reply or {success=false,error='Assessor service unavailable'})
    end)
end
