-- src/global/repository/baseRepository.lua
local BaseRepository = {}
BaseRepository.__index = BaseRepository

-- 이미 정의된 Lapis 모델을 주입받음
function BaseRepository:new(model)
    local repo = setmetatable({}, self)
    repo.model = model
    return repo
end

function BaseRepository:save(data)
    return self.model:create(data)
end

function BaseRepository:findById(id)
    return self.model:find(id)
end

function BaseRepository:findAll(...)
    return self.model:select(...)
end

function BaseRepository:update(id, data)
    local row = self.model:find(id)
    if not row then
        return nil, "not found"
    end
    row:update(data)
    return row
end

function BaseRepository:delete(id)
    local row = self.model:find(id)
    if not row then
        return false
    end
    return row:delete()
end

return BaseRepository