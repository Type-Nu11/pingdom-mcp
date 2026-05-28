local lapis = require("lapis")
local app = lapis.Application()

local function save_user_location(user_id, address, age)
  if not address then
    return nil, "address가 없습니다"
  end
  return {
    user_id = user_id,
    address = address,
    age = age
  }
end

app:get("/", function(self)
  return "alive"  -- 브라우저로 localhost:8080/ 열어서 이게 뜨면 서버는 정상
end)

app:post("/location", function(self)
  local ok, result_or_err = save_user_location(
      self.params.user_id,
      self.params.address,
      tonumber(self.params.age)
    )

  if not ok then
    -- 진짜 에러 메시지를 그대로 반환
    return { status = 500, json = { error = tostring(result_or_err) } }
  end

  return { json = { success = true, saved = ok } }
end)

return app
