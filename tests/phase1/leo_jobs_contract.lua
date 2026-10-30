-- PowerMoves LEO agency contract: compare the configured agency list to the
-- actual QBCore job definitions without substituting generic ranks.
local jobsText = assert(io.open('planning-reference/jobs.lua', 'r')):read('*a')
local configText = assert(io.open('config.lua', 'r')):read('*a')

local list = assert(configText:match('Config%.PoliceJobs%s*=%s*%{(.-)%}'), 'Missing Config.PoliceJobs')
local agencies = {}
for name in list:gmatch("'([^']+)'") do
    assert(not agencies[name], 'Duplicate LEO job: ' .. name)
    agencies[name] = true
end
assert(agencies.sadle, 'SADLE missing from LEO jobs')
for name in pairs(agencies) do
    local escaped = name:gsub('([^%w])', '%%%1')
    local start = assert(jobsText:find('\n%s*' .. escaped .. '%s*=%s*%{'), 'Missing QBCore job: ' .. name)
    local following = jobsText:sub(start, start + 300)
    assert(following:match("type%s*=%s*'leo'"), 'Incorrect job type: ' .. name)
    assert(following:find('grades%s*=%s*%{'), 'Missing QBCore grades: ' .. name)
end
assert(configText:match('Config%.PoliceJobType%s*=%s*"leo"'), 'LEO type mismatch')
local oversight = assert(configText:match('OversightJobs%s*=%s*%{(.-)%}'), 'No oversight jobs')
assert(oversight:match("'sadle'"), 'SADLE oversight missing')
assert(not oversight:match("'fib'") and not oversight:match("'gov'"), 'Invalid LEO oversight')
assert(configText:match("job%s*=%s*'sadle'%s*,%s*grade%s*=%s*11"), 'Attorney General grade mismatch')
print('PowerMoves LEO agency and oversight configuration: PASS')
