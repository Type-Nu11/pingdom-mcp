-- src/mcp/sessionStore.lua
-- MCP 세션 보관소.
--
-- 개발 환경은 config 의 reload_modules = true 때문에 요청마다 모듈이 다시 로드된다.
-- 모듈 지역 변수에 세션을 두면 매 요청 초기화되어 발급 직후의 세션도 404 가 된다.
-- 그래서 실제 저장 테이블은 모듈 리로드에 영향받지 않는 전역에 앵커링한다.
--
-- 프로세스 메모리이므로 cqueues 단일 워커 기준이다.
-- 워커를 늘리거나 인스턴스를 여러 개 띄우면 공유 저장소(예: Redis)로 옮겨야 한다.

local ANCHOR_KEY = "__mcp_session_store"

local SESSION_TTL = 30 * 60   -- 초

local M = {}

local function store()
    local anchor = rawget(_G, ANCHOR_KEY)
    if not anchor then
        anchor = {}
        rawset(_G, ANCHOR_KEY, anchor)
    end
    return anchor
end

local function new_id()
    local ok, rand = pcall(require, "openssl.rand")
    if ok then
        local bytes = rand.bytes(16)
        return (bytes:gsub(".", function(c)
            return string.format("%02x", string.byte(c))
        end))
    end
    return string.format("%x-%x", os.time(), math.random(0, 0xffffffff))
end

function M.prune(now)
    now = now or os.time()
    local sessions = store()
    for id, session in pairs(sessions) do
        if now - session.last_seen > SESSION_TTL then
            sessions[id] = nil
        end
    end
end

-- 새 세션 발급 → session_id 반환
function M.create(now)
    now = now or os.time()
    local id = new_id()
    store()[id] = { created_at = now, last_seen = now }
    return id
end

-- 살아있는 세션이면 last_seen 을 갱신하고 반환, 없으면 nil
function M.touch(id, now)
    if not id then return nil end
    local session = store()[id]
    if not session then return nil end
    session.last_seen = now or os.time()
    return session
end

function M.destroy(id)
    if not id then return false end
    local sessions = store()
    if not sessions[id] then return false end
    sessions[id] = nil
    return true
end

function M.count()
    local n = 0
    for _ in pairs(store()) do n = n + 1 end
    return n
end

return M
