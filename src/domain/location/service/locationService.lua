local locationRepo = require("src.domain.postgisWrapper.repository.locationRepository2")

local LocationService = {}

function LocationService.wrap(data)
    if not data.account_id then
        return nil, "account_id is required"
    end

    local result, err = locationRepo:save({
        account_id = data.account_id,
        birth_year = data.birth_year,
        gender = data.gender,
        lng = data.lng,
        lat = data.lat
    })

    if err then
        return nil, "INTERNAL_SERVER_ERROR"
    end

    return result
end

function LocationService.birthYearAndGender(data)
    -- 레포 정의가 (gender, birth_year) 순서임에 주의
    return locationRepo:findByGenderAndBirthYear(data.gender, data.birth_year)
end

return LocationService