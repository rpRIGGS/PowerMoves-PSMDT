-- Stage 6 local public finances live inside SAGOV MDT, never a separate UI.
local resourceName=tostring(GetCurrentResourceName())
for _,name in ipairs({'getGovernmentBudgets','createGovernmentBudget','approveGovernmentBudget'}) do
    RegisterNUICallback(name,function(data,cb)
        if not MDTOpen then
            cb({success=false,error='MDT is closed'})
            return
        end
        local result=ps.callback(resourceName..':server:'..name,data or {})
        cb(result or {success=false,error='Government budget service unavailable'})
    end)
end
