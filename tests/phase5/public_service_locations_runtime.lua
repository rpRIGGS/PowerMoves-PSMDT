-- Stage 5 geometry regression: configured vectors and polygons are enforced
-- by the server-side access policy; no server or FiveM client is required.
local pos = {x=10, y=10, z=30}
local env=setmetatable({
    Config={PublicServices={
        Enabled=true,DefaultDistance=1.0,Locations={
            {id='town',agency='lspd',shape='circle',coords={x=10,y=10,z=30},
             radius=1.0,services={'public_records_request','public_records_status','records_office'}},
            {id='county',agency='bcso',shape='poly',minZ=25,maxZ=33,
             points={{x=30,y=30},{x=40,y=30},{x=40,y=40},{x=30,y=40}},
             services={'public_records_request','records_office'}}
        }
    }},
    GetPlayerPed=function(source) return source == 1 and 99 or 0 end,
    GetEntityCoords=function(ped) assert(ped == 99);return pos end,
}, {__index=_G})
assert(loadfile('server/backend/public_service_locations.lua','t',env))()
local allows=assert(env.PublicServiceDeskAllows)
assert(allows(1,'lspd','records_office'))
assert(allows(1,'lspd','public_records_request'))
assert(not allows(1,'bcso','records_office'),'Wrong agency location must deny')
assert(not allows(1,'lspd','not_supported'),'Unknown service must deny')
assert(not allows(2,'lspd','records_office'),'Unknown player must deny')
pos={x=32,y=32,z=29}
assert(allows(1,'bcso','records_office'),'Inside polygon must allow')
assert(not allows(1,'lspd','records_office'),'Outside LSPD circle must deny')
pos={x=32,y=32,z=41}
assert(not allows(1,'bcso','records_office'),'Outside polygon Z range must deny')
pos={x=1000,y=1000,z=30}
assert(not allows(1,'lspd','public_records_request'),'Remote calls must deny')
-- An invalid or unbounded zone setting must not grant global access.
pos={x=10,y=10,z=30}
local town=env.Config.PublicServices.Locations[1]
town.radius=math.huge
assert(not allows(1,'lspd','records_office'),'Infinite radius must be rejected')
town.radius=1.0
pos.x=0/0
assert(not allows(1,'lspd','records_office'),'NaN coordinates must be rejected')
pos={x=10,y=10,z=30}
env.Config.PublicServices.Enabled=false
assert(not allows(1,'lspd','records_office'),'Disabled service must deny')
print('PASS Stage 5 server circle/poly vector and agency isolation checks')
