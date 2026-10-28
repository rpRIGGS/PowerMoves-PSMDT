local resourceName = tostring(GetCurrentResourceName())

function NUIUpdateAuthWithData(jobData)
    -- Job data is a refresh signal, never a client-side eligibility decision.
    NUIUpdateAuth()
end

local function onJobUpdate(JobInfo)
    local job = JobInfo or ps.getJob()
    ps.debug('Updated job info:', job)

    if MDTOpen then
        local access = GetMdtAuthData()
        if not access.authorized then
            CloseMDT()
            ps.notify('MDT closed - Access revoked', 'error')
        else
            SendNUI('updateAuth', access)
        end
    end
end

local function onSetDuty(duty)
    if MDTOpen then
        local access = GetMdtAuthData()
        if not access.authorized then
            CloseMDT()
            ps.notify('MDT closed - Access revoked', 'error')
        else
            SendNUI('updateAuth', access)
        end
    end
end

RegisterNetEvent('QBCore:Client:SetDuty', function(duty)
    ps.debug('SetDuty event received:', duty)
    onSetDuty(duty)
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    ps.debug('OnJobUpdate event received:', JobInfo)
    onJobUpdate(JobInfo)
end)

RegisterNetEvent('esx:setJob', function(job)
    ps.debug('esx:setJob event received:', job)
    onJobUpdate(job)
end)

-- Send Profile Data
RegisterNetEvent(resourceName..':client:sendProfile', function(data)
    if MDTOpen then
        SendNUI('updateProfile', data)
    end
end)

-- Handle player death
if GetResourceState('baseevents') == 'started' then
    RegisterNetEvent('baseevents:onPlayerDied', function()
        if MDTOpen then
            ps.debug('Player died')
            CloseMDT()
        end
    end)
end
