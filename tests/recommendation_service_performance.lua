local aggregate_calls = 0
local reverse_calls = 0
local aggregate_mode = "non_empty"

local function aggregated_row()
    return {
        { cell = "wydj", total_foot = 100, age_match = 70, gender_match = 100,
          avg_hour = 18.5, lat = 35.9236, lng = 128.5956 },
        { cell = "wydk", total_foot = 90, age_match = 65, gender_match = 90,
          avg_hour = 18.0, lat = 35.9237, lng = 128.5957 },
        { cell = "wydm", total_foot = 80, age_match = 60, gender_match = 80,
          avg_hour = 17.5, lat = 35.9238, lng = 128.5958 },
        { cell = "wydn", total_foot = 70, age_match = 55, gender_match = 70,
          avg_hour = 17.0, lat = 35.9239, lng = 128.5959 },
        { cell = "wydp", total_foot = 60, age_match = 50, gender_match = 60,
          avg_hour = 16.5, lat = 35.9240, lng = 128.5960 },
    }
end

package.loaded["src.modules.GeoEncoder"] = {
    geocode = function(region)
        assert(region == "대구광역시 북구 서변동")
        return 128.5955669, 35.9235922
    end,
    reverse = function()
        reverse_calls = reverse_calls + 1
        return "대구광역시 북구 서변동"
    end,
}
package.loaded["src.global.repository.locationRepository"] = {
    aggregateInRadius = function(_, lng, lat, radius, by_min, by_max, gender, precision)
        aggregate_calls = aggregate_calls + 1
        assert(lng == 128.5955669 and lat == 35.9235922)
        local expected_radius = aggregate_mode == "empty" and (radius == 1500 or radius == 6000 or radius == 15000)
            or radius == 1500
        assert(expected_radius and by_min == 1987 and by_max == 2006)
        assert(gender == "ANY" and precision == 7)
        if aggregate_mode == "empty" then return {} end
        return aggregated_row()
    end,
}
package.loaded["src.domain.recommendation.tool.recommendationTool"] = {}
package.loaded["src.ai.llmClient"] = {}
package.loaded["src.domain.recommendation.service.recommendationService"] = nil

local service = require("src.domain.recommendation.service.recommendationService")
local result, err = service.recommend({
    region = "대구광역시 북구 서변동",
    age_min = 20,
    age_max = 39,
    gender = "ANY",
    radius_m = 1500,
})

assert(not err, err)
assert(aggregate_calls == 1, "non-empty results should execute one aggregate query")
assert(reverse_calls == 1, "only the top-ranked result should execute reverse geocoding")
assert(#result.recommendations == 5)
assert(result.recommendations[1].address == "대구광역시 북구 서변동")
assert(result.recommendations[2].address == "대구광역시 북구 서변동 인근 후보")

aggregate_mode = "empty"
aggregate_calls = 0
reverse_calls = 0

local empty_result, empty_error = service.recommend({
    region = "대구광역시 북구 서변동",
    age_min = 20,
    age_max = 39,
    gender = "ANY",
    radius_m = 1500,
})

assert(not empty_error, empty_error)
assert(aggregate_calls == 3, "empty results should execute the initial query and both bounded fallback queries")
assert(reverse_calls == 0, "empty results should not execute reverse geocoding")
assert(empty_result.searched_radius_m == nil, "empty result should preserve the existing response contract")
assert(#empty_result.recommendations == 0)

print("Recommendation service performance contract OK")
