-- Stage 6 policy regression: exact departments and state hierarchy only.
-- No FiveM runtime, database or citizen content is required.
local config={MdtAccess={
    GovernmentJobs={
        sagov='state', bcgov='blaine_county',
        lscgov='los_santos_county', lsgov='los_santos_city'
    },
    GovernmentJurisdictions={
        state={label='State of San Andreas'},
        blaine_county={label='Blaine County',parent='state'},
        los_santos_county={label='Los Santos County',parent='state'},
        los_santos_city={label='City of Los Santos',parent='los_santos_county'}
    }
}}
local env=setmetatable({Config=config},{__index=_G})
assert(loadfile('server/backend/government_jurisdiction_policy.lua','t',env))()
local contains=assert(env.GovernmentJurisdictionContains)
local view=assert(env.CanViewGovernmentJurisdictionRecord)
assert(contains('state','blaine_county'))
assert(contains('state','los_santos_city'))
assert(contains('los_santos_county','los_santos_city'))
assert(not contains('blaine_county','los_santos_city'))
assert(not contains('los_santos_county','blaine_county'))
assert(not contains('los_santos_city','los_santos_county'))
assert(view('bcgov','blaine_county',false,false))
assert(view('lsgov','los_santos_city',false,false))
assert(not view('bcgov','los_santos_county',false,true),'County cannot see sibling')
assert(not view('lscgov','los_santos_city',false,true),'County parentage does not grant city records')
assert(not view('lsgov','los_santos_county',false,true),'City cannot see county records')
assert(not view('sagov','blaine_county',false,false),'State needs explicit oversight')
assert(view('sagov','blaine_county',false,true))
assert(view('sagov','los_santos_city',false,true))
assert(view('lsgov','blaine_county',true,false),'Published public data is visible')
assert(not view('lsgov','blaine_county','true',false),'A string is not publication')
assert(not view('mechanic','no_such_jurisdiction',true,true))
assert(not view('mechanic','los_santos_city',false,true),'Unknown jobs cannot see internal data')

-- New incorporated municipalities require only a validated jurisdiction map;
-- they do not inherit Blaine County's unpublished internal records.
config.MdtAccess.GovernmentJobs.grapeseedgov='grapeseed_city'
config.MdtAccess.GovernmentJurisdictions.grapeseed_city={
    label='Town of Grapeseed',parent='blaine_county'
}
assert(contains('state','grapeseed_city'))
assert(contains('blaine_county','grapeseed_city'))
assert(not view('bcgov','grapeseed_city',false,true))
assert(view('sagov','grapeseed_city',false,true))

-- Invalid parent references or cycles must fail closed, including when the
-- actor and target happen to be in the same bad configuration subtree.
config.MdtAccess.GovernmentJurisdictions.state.parent='los_santos_city'
assert(not contains('state','los_santos_city'))
assert(not contains('los_santos_city','los_santos_city'))
assert(not view('sagov','los_santos_city',false,true))
config.MdtAccess.GovernmentJurisdictions.state.parent=nil
config.MdtAccess.GovernmentJurisdictions.grapeseed_city.parent='unknown'
assert(not contains('state','grapeseed_city'))
print('PASS Stage 6 hierarchical, local-only, explicit-state-oversight and publication policy')
