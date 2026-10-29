-- Stage 6 real PSMDT SADOT eligibility source against mocked server natives.
-- No live FiveM vehicle, job or government permit is mutated.
local captures = {}
local actor = {
    job='towshop1',type='mechanic',cid='DRIVER-A',duty=true,
    vehicle=100,plate='TEST511',permit=true,changeDuringRead=false
}
local cfg={MdtAccess={Transportation={
    Enabled=false,JobType='mechanic',AllowedOperatorJobs={},
    RequireQualifiedVehicle=true,
}}}
local env=setmetatable({
    Config=cfg,
    exports=function(name,handler) captures[name]=handler end,
    ps={
        getJobName=function() return actor.job end,
        getJobType=function() return actor.type end,
        getIdentifier=function() return actor.cid end,
        getJobDuty=function() return actor.duty end,
    },
    GetPlayerPed=function() return 17 end,
    GetVehiclePedIsIn=function() return actor.vehicle end,
    GetVehicleNumberPlateText=function() return actor.plate end,
    MySQL={
        single={await=function(sql,parameters)
            assert(sql:find('mdt_government_business_licenses',1,true))
            assert(sql:find('b.status = \'approved\'',1,true))
            assert(sql:find('mdt_sadot_qualified_drivers',1,true))
            assert(sql:find('mdt_sadot_permitted_vehicles',1,true))
            assert(sql:find('p.revoked_at IS NULL',1,true))
            assert(sql:find('d.expires_at > UTC_TIMESTAMP()',1,true))
            assert(sql:find('v.expires_at > UTC_TIMESTAMP()',1,true))
            assert(parameters[1]==actor.cid and parameters[2]==actor.plate
                and parameters[3]==actor.job)
            if actor.changeDuringRead then actor.job='other_shop';actor.changeDuringRead=false end
            return actor.permit and {permit_id=1} or nil
        end}
    }
},{__index=_G})
assert(loadfile('server/backend/sadot_eligibility.lua','t',env))()
local eligible=assert(captures.IsSadotTowEligible)
assert(not eligible(1),'Disabled SADOT never grants tow claim')
cfg.MdtAccess.Transportation.Enabled=true
assert(not eligible(1),'Unknown operator job is not a permit')
cfg.MdtAccess.Transportation.AllowedOperatorJobs={'towshop1'}
assert(eligible(1),'All live credentials + explicitly configured job should pass')
actor.permit=false
assert(not eligible(1),'Revoked/missing/expired permit query must fail closed')
actor.permit=true
actor.duty=false
assert(not eligible(1),'Off-duty driver cannot accept 511')
actor.duty=true
actor.vehicle=0
assert(not eligible(1),'Driver must be in an approved vehicle')
actor.vehicle=100
actor.plate='  '
assert(not eligible(1),'Blank plate denied')
actor.plate='TEST511'
actor.type='ems'
assert(not eligible(1),'Wrong job type denied')
actor.type='mechanic'
actor.changeDuringRead=true
assert(not eligible(1),'Job transfer during SQL must fail closed')
actor.job='towshop1'
assert(eligible(1))
assert(not eligible(0),'Invalid source denied')
print('PASS Stage 6 SADOT disabled default, permit, driver, duty, vehicle and race checks')
