local db = require("lapis.db")
local BaseRepository = require("src.global.repository.baseRepository")

local LocationRepository = setmetatable({}, { __index = BaseRepository })

function LocationRepository:save(data)
    if not data.account_id then
        return nil, "account_id is required"
    end

    return db.query([[
        INSERT INTO locations (account_id, birth_year, gender, geom, created_at)
        VALUES (?, ?, ?, ST_SetSRID(ST_MakePoint(?, ?), 4326), now())
        RETURNING id
    ]], data.account_id, tonumber(data.birth_year), data.gender, tonumber(data.lng), tonumber(data.lat))
end

-- 조회
function LocationRepository:findByFilters(gender, birth_year, created_at)
    if not gender and not birth_year and not created_at then
        return nil, "at least one filter is required"
    end

    local where, params = {}, {}

    if gender then
        table.insert(where, "gender = ?")
        table.insert(params, gender)
    end
    if birth_year then
        table.insert(where, "birth_year = ?")
        table.insert(params, tonumber(birth_year))
    end
    if created_at then
        table.insert(where, "created_at = ?")
        table.insert(params, created_at)
    end

    local sql = [[
        SELECT account_id, birth_year, gender,
               ST_X(geom) AS lng,
               ST_Y(geom) AS lat,
               created_at
        FROM observations
        WHERE ]] .. table.concat(where, " AND ")

    return db.query(sql, table.unpack(params))
end

return LocationRepository
