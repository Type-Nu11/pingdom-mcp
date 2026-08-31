local captured_sql
local captured_params

package.loaded["lapis.db"] = {
    query = function(sql, ...)
        captured_sql = sql
        captured_params = { ... }
        return {}
    end,
}
package.loaded["src.modules.baseRepository"] = {}
package.loaded["src.global.repository.locationRepository"] = nil

local repository = require("src.global.repository.locationRepository")
repository:aggregateInRadius(128.5955669, 35.9235922, 1500, 1987, 2006, "ANY", 7)

assert(captured_sql:find("ST_GeoHash", 1, true), "query should aggregate by geohash")
assert(captured_sql:find("COUNT(*)", 1, true), "query should aggregate counts in PostgreSQL")
assert(captured_sql:find("POWER((longitude - ?)", 1, true), "query should preserve meter-based distance")
assert(#captured_params == 16, "query should bind every aggregation parameter")
assert(captured_params[13] == 128.5955669, "longitude should be bound")
assert(captured_params[15] == 35.9235922, "latitude should be bound")
assert(captured_params[16] == 1500, "radius should be bound")

repository:summarizeInRadius(128.5955669, 35.9235922, 1500, 1987, 2006)
assert(captured_sql:find("gender_distribution", 1, true), "statistics query should include gender distribution")
assert(captured_sql:find("time_distribution", 1, true), "statistics query should include time distribution")
assert(captured_sql:find("day_distribution", 1, true), "statistics query should include day distribution")
assert(captured_sql:find("month_distribution", 1, true), "statistics query should include month distribution")

print("Location repository aggregation contract OK")
