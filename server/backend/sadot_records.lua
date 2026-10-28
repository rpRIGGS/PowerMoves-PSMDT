-- SADOT durable records owned by the PSMDT shared database.
-- PS-Dispatch sends dispatch lifecycle notifications through a server export;
-- reporting remains in the existing PSMDT reports module.
local ready = false
local function ensureSchema()
    if ready then return true end
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pm_sadot_tows (
                tow_ref VARCHAR(64) NOT NULL PRIMARY KEY,
                dispatch_id INT NOT NULL,
                status VARCHAR(24) NOT NULL,
                revision INT NOT NULL DEFAULT 0,
                caller_citizenid VARCHAR(64) DEFAULT NULL,
                caller_name VARCHAR(128) DEFAULT NULL,
                information VARCHAR(256) DEFAULT NULL,
                street VARCHAR(128) DEFAULT NULL,
                plate VARCHAR(24) DEFAULT NULL,
                origin_x DOUBLE DEFAULT NULL,
                origin_y DOUBLE DEFAULT NULL,
                origin_z DOUBLE DEFAULT NULL,
                driver_citizenid VARCHAR(64) DEFAULT NULL,
                driver_job VARCHAR(64) DEFAULT NULL,
                assigned_at DATETIME DEFAULT NULL,
                completed_at DATETIME DEFAULT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                KEY idx_sadot_plate (plate),
                KEY idx_sadot_status (status),
                KEY idx_sadot_caller (caller_citizenid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
        -- Inspection reports append immutable entries; they do not falsely
        -- certify that a vehicle has actually reached a garage or impound lot.
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pm_sadot_tow_inspections (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                tow_ref VARCHAR(64) NOT NULL,
                driver_citizenid VARCHAR(64) NOT NULL,
                driver_job VARCHAR(64) NOT NULL,
                plate VARCHAR(24) NOT NULL,
                vehicle_model VARCHAR(100) NOT NULL,
                vehicle_condition VARCHAR(256) NOT NULL,
                destination VARCHAR(160) NOT NULL,
                notes VARCHAR(512) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                KEY idx_tow_inspection_ref (tow_ref),
                KEY idx_tow_inspection_plate (plate)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS pm_sadot_tow_events (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                tow_ref VARCHAR(64) NOT NULL,
                revision INT NOT NULL,
                event_type VARCHAR(24) NOT NULL,
                actor_citizenid VARCHAR(64) DEFAULT NULL,
                actor_job VARCHAR(64) DEFAULT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_sadot_event_version (tow_ref, revision),
                KEY idx_sadot_event_ref (tow_ref)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
    end)
    if not ok then
        print('[ps-dispatch] SADOT tow ledger unavailable: ' .. tostring(err))
        return false
    end
    ready = true
    return true
end

CreateThread(function()
    ensureSchema()
end)

local function clip(value, limit)
    if value == nil then return nil end
    return tostring(value):sub(1, limit)
end

-- Server-internal transition events, never RegisterNetEvent: clients cannot
-- write audit entries or spoof assignments. Versioning prevents out-of-order
-- asynchronous SQL operations from rolling a record backward.
exports('RecordSadotTowEvent', function(event, record)
    if type(record) ~= 'table' or type(record.ref) ~= 'string' then return end
    if event ~= 'requested' and event ~= 'assigned'
        and event ~= 'released' and event ~= 'completed'
        and event ~= 'expired' then return end
    if not ensureSchema() then return end
    local version = tonumber(record.revision)
    if not version or version < 0 or version % 1 ~= 0 then return end
    local status = event
    local driver = clip(record.driver, 64)
    local job = clip(record.driverJob, 64)
    local ref = clip(record.ref, 64)
    local coordinates = record.coords or {}
    local ok, err = pcall(function()
        MySQL.query.await([[
            INSERT INTO pm_sadot_tows
                (tow_ref, dispatch_id, status, revision, caller_citizenid,
                 caller_name, information, street, plate, origin_x, origin_y,
                 origin_z, driver_citizenid, driver_job, assigned_at, completed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                    IF(? = 'assigned', NOW(), NULL),
                    IF(? = 'completed', NOW(), NULL))
            ON DUPLICATE KEY UPDATE
                status = IF(VALUES(revision) > revision, VALUES(status), status),
                driver_citizenid = IF(VALUES(revision) > revision, VALUES(driver_citizenid), driver_citizenid),
                driver_job = IF(VALUES(revision) > revision, VALUES(driver_job), driver_job),
                assigned_at = IF(VALUES(revision) > revision AND VALUES(status) = 'assigned', NOW(), assigned_at),
                completed_at = IF(VALUES(revision) > revision AND VALUES(status) = 'completed', NOW(), completed_at),
                revision = GREATEST(revision, VALUES(revision))
        ]], {
            ref, tonumber(record.dispatchId) or 0, status, version,
            clip(record.caller, 64) or '', clip(record.callerName, 128) or '',
            clip(record.information, 256) or '', clip(record.street, 128) or '',
            clip(record.plate, 24) or '', tonumber(coordinates.x) or 0,
            tonumber(coordinates.y) or 0, tonumber(coordinates.z) or 0,
            driver or '', job or '', status, status
        })
        MySQL.insert.await([[
            INSERT IGNORE INTO pm_sadot_tow_events
                (tow_ref, revision, event_type, actor_citizenid, actor_job)
            VALUES (?, ?, ?, ?, ?)
        ]], {ref, version, status, clip(record.actor, 64) or '', clip(record.actorJob, 64) or ''})
    end)
    if not ok then print('[ps-dispatch] SADOT record write failed: ' .. tostring(err)) end
end)

-- Server-only records. UI reads will need separately scoped MDT authorization.
exports('GetSadotTow', function(ref)
    if not ensureSchema() or type(ref) ~= 'string' then return nil end
    return MySQL.single.await('SELECT * FROM pm_sadot_tows WHERE tow_ref = ? LIMIT 1', {ref})
end)
exports('GetSadotTowEvents', function(ref)
    if not ensureSchema() or type(ref) ~= 'string' then return {} end
    return MySQL.query.await('SELECT * FROM pm_sadot_tow_events WHERE tow_ref = ? ORDER BY revision ASC', {ref}) or {}
end)
exports('GetSadotTowByPlate', function(plate)
    if not ensureSchema() or type(plate) ~= 'string' then return {} end
    return MySQL.query.await('SELECT * FROM pm_sadot_tows WHERE plate = ? ORDER BY created_at DESC LIMIT 50', {plate:sub(1, 24)}) or {}
end)

