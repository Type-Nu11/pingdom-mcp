local locationRepo = require("src.global.repository.locationRepository")

local LocationService = {}

function LocationService.wrap(data)
    if not data.account_id then
        return nil, "INVALID_INPUT"
    end

    local result, err = locationRepo:save(data)
    if err then
        return nil, err   -- 이미 맵 키 (INVALID_INPUT 등)
    end
    return result
end

function LocationService.search(data)
    local result, err = locationRepo:findByFilters(
        data.gender, data.birth_year, data.created_at
    )
    if err then
        return nil, err
    end
    return result
end

return LocationService