local db = require("lapis.db")

local function save_user_location(user_id, address, age)
    local lng, lat = geocode(address)
  
    if not lng then
      return nil, "주소를 좌표로 변환하지 못했습니다"
    end
  
    return db.insert("user_locations", {
      user_id = user_id,
      address = address,
      age = age,
      geom = db.raw(db.interpolate_query(
        "ST_SetSRID(ST_MakePoint(?, ?), 4326)", lng, lat
      ))
    })
end


return save_user_location