-- Stage 6 local government operating budgets; never adjusts cash balances or tax.
local resourceName=tostring(GetCurrentResourceName())
local function access(source)
    if type(GetGovernmentBudgetAccess)~='function' then return nil end
    local ok,user=pcall(GetGovernmentBudgetAccess,source)
    local jobs=((Config or {}).MdtAccess or {}).GovernmentJobs or {}
    if not ok or type(user)~='table' or type(user.citizenid)~='string'
        or jobs[user.agency]~=user.jurisdiction then return nil end
    return user
end
local function same(source,old)
    local new=access(source)
    return new and old.citizenid==new.citizenid
        and old.agency==new.agency and old.jurisdiction==new.jurisdiction
        and old.canDraft==new.canDraft and old.canApprove==new.canApprove
        and old.hasStateOversight==new.hasStateOversight
end
local function safeText(str,limit)
    if type(str)~='string' then return nil end
    local v=str:match('^%s*(.-)%s*$')
    return #v>0 and #v<=limit and v or nil
end
local function number(x,minimum,maximum)
    local v=tonumber(x)
    return v and v%1==0 and v>=minimum and v<=maximum and v or nil
end
local function changed(result)
    return type(result)=='table' and tonumber(result.affectedRows)==1
end
local function hasTx()
    return type(MySQL)=='table' and
        type(rawget(MySQL,'startTransaction'))=='function'
end

ps.registerCallback(resourceName..':server:getGovernmentBudgets',function(source,payload)
    local a=access(source)
    if not a then return {success=false,error='Budget office unavailable'} end
    local agency=type(payload)=='table' and payload.agency or a.agency
    if agency==nil then agency=a.agency end
    local jobs=((Config or {}).MdtAccess or {}).GovernmentJobs or {}
    if type(agency)~='string' or not jobs[agency]
        or (agency~=a.agency and (a.agency~='sagov'
            or a.hasStateOversight~=true)) then
        return {success=false,error='Budget jurisdiction is private'}
    end
    local page=number(type(payload)=='table' and payload.page or 0,0,200)
    if not page then return {success=false,error='Invalid budget page'} end
    local ok,rows=pcall(MySQL.query.await,[[
        SELECT id,agency,jurisdiction,department,fiscal_year,revenue_estimate,
               expense_limit,notes,status,version,created_at,approved_at
        FROM mdt_government_budgets WHERE agency = ? AND jurisdiction = ?
        ORDER BY fiscal_year DESC,id DESC LIMIT ? OFFSET ?
    ]],{agency,jobs[agency],51,page*50})
    if not ok or not same(source,a) then
        return {success=false,error='Budget access changed'}
    end
    rows=type(rows)=='table' and rows or {}
    local more=#rows>50
    if more then rows[#rows]=nil end
    return {success=true,budgets=rows,page=page,hasMore=more,
        agency=agency,canDraft=agency==a.agency and a.canDraft==true,
        canApprove=agency==a.agency and a.canApprove==true,
        authorities=(function()
            local result={}
            for job,area in pairs(jobs) do
                if job==a.agency or (a.agency=='sagov' and a.hasStateOversight) then
                    result[#result+1]={job=job,jurisdiction=area}
                end
            end
            table.sort(result,function(x,y)return x.job<y.job end)
            return result
        end)()}
end)

ps.registerCallback(resourceName..':server:createGovernmentBudget',function(source,payload)
    local a=access(source)
    if not a or a.canDraft~=true or type(payload)~='table' then
        return {success=false,error='Budget drafting denied'}
    end
    local department=safeText(payload.department,100)
    local notes=safeText(payload.notes,6000)
    local year=number(payload.fiscalYear,2020,2100)
    local revenue=number(payload.revenueEstimate,0,1000000000000)
    local expense=number(payload.expenseLimit,0,1000000000000)
    if not department or not notes or not year or not revenue or not expense or not hasTx() then
        return {success=false,error='Invalid annual budget'}
    end
    local id
    local ok,committed=pcall(MySQL.startTransaction,function(query)
        if not same(source,a) then return false end
        local result=query([[
            INSERT INTO mdt_government_budgets
                (agency,jurisdiction,department,fiscal_year,revenue_estimate,
                 expense_limit,notes,created_by_citizenid)
            VALUES (?,?,?,?,?,?,?,?)
        ]],{a.agency,a.jurisdiction,department,year,revenue,expense,notes,a.citizenid})
        if not changed(result) or not number(result.insertId,1,9007199254740991) then return false end
        id=result.insertId
        local audit=query([[
            INSERT INTO mdt_government_budget_audit
                (budget_id,agency,actor_citizenid,action,reason)
            VALUES (?,?,?,'created','Annual department budget draft')
        ]],{id,a.agency,a.citizenid})
        return changed(audit) and same(source,a)==true
    end)
    if not ok or committed~=true then
        return {success=false,error='Budget not saved; duplicate department/year or access changed'}
    end
    return {success=true,id=id}
end)

ps.registerCallback(resourceName..':server:approveGovernmentBudget',function(source,payload)
    local a=access(source)
    if not a or a.canApprove~=true or type(payload)~='table' then
        return {success=false,error='Budget adoption denied'}
    end
    local id=number(payload.id,1,9007199254740991)
    local version=number(payload.version,1,2147483647)
    local reason=safeText(payload.reason,1000)
    if not id or not version or not reason or not hasTx() then
        return {success=false,error='Invalid budget adoption'}
    end
    local ok,committed=pcall(MySQL.startTransaction,function(query)
        local rows=query([[
            SELECT status,version FROM mdt_government_budgets
            WHERE id = ? AND agency = ? AND jurisdiction = ? FOR UPDATE
        ]],{id,a.agency,a.jurisdiction})
        if type(rows)~='table' or not rows[1] or rows[1].status~='draft'
            or tonumber(rows[1].version)~=version or not same(source,a) then return false end
        local changedBudget=query([[
            UPDATE mdt_government_budgets
            SET status='approved',version=version+1,
                approved_by_citizenid=?,approved_at=UTC_TIMESTAMP()
            WHERE id=? AND agency=? AND jurisdiction=?
                AND status='draft' AND version=?
        ]],{a.citizenid,id,a.agency,a.jurisdiction,version})
        if not changed(changedBudget) then return false end
        local audit=query([[
            INSERT INTO mdt_government_budget_audit
                (budget_id,agency,actor_citizenid,action,reason)
            VALUES (?,?,?,'approved',?)
        ]],{id,a.agency,a.citizenid,reason})
        return changed(audit) and same(source,a)==true
    end)
    if not ok or committed~=true then
        return {success=false,error='Budget changed, permission lost or adoption failed'}
    end
    return {success=true}
end)
