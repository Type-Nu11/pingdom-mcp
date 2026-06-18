-- src/domain/recommendation/service/recommendationService.lua
-- 업종 + 지역 → Groq(함수콜)로 "타깃 인구통계"만 추론 → 반경 내 포인트 조회 → geohash 모듈로 셀 집계
-- → 점수화·랭킹·역지오코딩은 코드에서 결정적으로 처리(한글 깨짐/환각 방지) → 구조화 JSON 반환
local groq         = require("src.modules.groqClient")
local geo          = require("src.modules.GeoEncoder")
local geohash      = require("src.modules.geohash")
local locationRepo = require("src.global.repository.locationRepository")
local env          = require("src.global.config.env")
local cjson        = require("cjson")

local THIS_YEAR = 2026
local TOP_N     = 5

local SYSTEM_PROMPT = [[
너는 상권 입지 분석 챗봇이다. 직원의 질문에서 조건을 파악해 recommend_location 툴을
반드시 1회 호출하라. (설명 문장 출력 금지, 툴 호출만)

조건 파악:
- 지역(region): 질문에 나온 지역명을 그대로.
- 연령(age_min/age_max): 질문에 나이대가 있으면 그대로 사용. 없고 업종만 있으면 그 업종의
  핵심 고객 나이대를 추론. (age_min ≤ age_max, 정수)
- 성별(gender): 질문에 있으면 'M'/'F', 없으면 'ANY'.
- radius_m 기본 1500.
]]

local TOOLS = {
    {
        type = "function",
        ["function"] = {
            name = "recommend_location",
            description = "업종 타깃 인구통계로 지역 내 입지를 조회한다",
            parameters = {
                type = "object",
                properties = {
                    region   = { type = "string",  description = "예: '대구 북구'" },
                    radius_m = { type = "integer", description = "검색 반경(m), 기본 1500" },
                    age_min  = { type = "integer", description = "타깃 최소 나이 (예: 20)" },
                    age_max  = { type = "integer", description = "타깃 최대 나이 (예: 45)" },
                    gender   = { type = "string",  enum = { "M", "F", "ANY" } },
                },
                required = { "region", "age_min", "age_max", "gender" },
            },
        },
    },
}

-- Llama 가 tool_calls 대신 본문에 <function=NAME>{json}</function> 로 새는 경우 파싱 폴백
local function parse_inline_call(content)
    if type(content) ~= "string" then return nil end
    local name, args = content:match("<function=([%w_]+)>%s*(%b{})")
    if not name then return nil end
    return { ["function"] = { name = name, arguments = args } }
end

-- 후보 셀들을 점수화 후 상위 TOP_N 반환 (min-max 정규화)
local function score_and_rank(rows)
    local function bounds(key)
        local mn, mx = math.huge, -math.huge
        for _, r in ipairs(rows) do
            local v = tonumber(r[key]) or 0
            if v < mn then mn = v end
            if v > mx then mx = v end
        end
        return mn, mx
    end
    local function norm(v, mn, mx)
        if mx <= mn then return 0 end
        return (v - mn) / (mx - mn)
    end

    local a0, a1 = bounds("age_match")
    local g0, g1 = bounds("gender_match")
    local f0, f1 = bounds("total_foot")

    local scored = {}
    for _, r in ipairs(rows) do
        local s = 0.40 * norm(tonumber(r.age_match) or 0, a0, a1)
                + 0.20 * norm(tonumber(r.gender_match) or 0, g0, g1)
                + 0.40 * norm(tonumber(r.total_foot) or 0, f0, f1)
        scored[#scored + 1] = {
            lat   = tonumber(r.lat),
            lng   = tonumber(r.lng),
            score = math.floor(s * 100 + 0.5) / 100,
            metrics = {
                total_foot   = tonumber(r.total_foot),
                age_match    = tonumber(r.age_match),
                gender_match = tonumber(r.gender_match),
                avg_hour     = tonumber(r.avg_hour),
            },
        }
    end
    table.sort(scored, function(x, y) return x.score > y.score end)

    local top = {}
    for i = 1, math.min(TOP_N, #scored) do
        scored[i].rank = i
        top[i] = scored[i]
    end
    return top
end

-- 구조화 결과 → 깔끔한 한국어 답변 문장(코드 생성, LLM 한글 깨짐 방지)
local function build_answer(target, recs, opts)
    opts = opts or {}
    local g = (target.gender == "M" and "남성")
           or (target.gender == "F" and "여성")
           or "성별무관"
    if #recs == 0 then
        return "조건에 맞는 유동인구 데이터가 충분하지 않습니다. 지역이나 연령 범위를 넓혀보세요."
    end
    local lines = {}
    lines[#lines + 1] = string.format(
        "%s %s~%s세 / %s 기준으로 유동인구가 많은 추천 입지 Top%d입니다.",
        target.region or "", tostring(target.age_min or "?"),
        tostring(target.age_max or "?"), g, #recs)
    if opts.widened then
        lines[#lines + 1] = string.format(
            "(인근에 데이터가 적어 반경을 %dm로 넓혀 검색했습니다.)", opts.radius or 0)
    end
    for _, r in ipairs(recs) do
        lines[#lines + 1] = string.format(
            "%d위. %s (점수 %.2f)\n   · 유동인구 %s명, 타깃연령 %s명, 평균활동 %s시",
            r.rank, r.address or "주소 미상", r.score,
            tostring(r.metrics.total_foot), tostring(r.metrics.age_match),
            tostring(r.metrics.avg_hour))
    end
    return table.concat(lines, "\n")
end

local RecommendationService = {}

-- input: { message=자유질문 } 또는 { business=업종, region=지역 }
function RecommendationService.recommend(input)
    local business = input.business or input["업종"]
    local region   = input.region   or input["지역"]
    local message  = input.message  or input["질문"]
    if not message and not (business or region) then
        return nil, "INVALID_INPUT"
    end
    local user_content = message
        or ("업종: %s\n지역: %s"):format(business or "", region or "")

    local api_key = env.get("GROQ_API_KEY")
    if not api_key or api_key == "" then
        return nil, "LLM_NO_KEY"
    end
    local model = env.get("GROQ_MODEL", "llama-3.3-70b-versatile")

    -- 1) LLM: 타깃 추론 → 강제 툴 호출
    local resp, err = groq.chat({
        model       = model,
        messages    = {
            { role = "system", content = SYSTEM_PROMPT },
            { role = "user",   content = user_content },
        },
        tools       = TOOLS,
        tool_choice = "required",
    }, api_key)

    if not resp then return nil, err end
    if resp.error then return nil, "LLM_ERROR:" .. (resp.error.message or "") end

    local msg = resp.choices and resp.choices[1] and resp.choices[1].message
    if not msg then return nil, "LLM_EMPTY" end

    local call = msg.tool_calls and msg.tool_calls[1] or parse_inline_call(msg.content)
    if not call then return nil, "LLM_NO_TOOLCALL" end

    local ok, args = pcall(cjson.decode, call["function"].arguments)
    if not ok then return nil, "LLM_BAD_ARGS" end

    -- 2) 지역 → 좌표
    local lng, lat = geo.geocode(args.region or region)
    if not lng then return nil, "GEOCODE_FAILED" end

    -- 나이 → birth_year 변환은 코드에서 (LLM 산수 오류 방지). 순서 뒤집힘도 보정.
    local age_min = tonumber(args.age_min); if age_min then age_min = math.floor(age_min) end
    local age_max = tonumber(args.age_max); if age_max then age_max = math.floor(age_max) end
    if age_min and age_max and age_min > age_max then age_min, age_max = age_max, age_min end
    local by_min = age_max and (THIS_YEAR - age_max) or nil   -- 고령 → 작은 연도
    local by_max = age_min and (THIS_YEAR - age_min) or nil   -- 연소 → 큰 연도

    local target = {
        business       = business,
        region         = args.region or region,
        age_min        = age_min,
        age_max        = age_max,
        birth_year_min = by_min,
        birth_year_max = by_max,
        gender         = args.gender or "ANY",
    }

    -- 3) 반경 내 포인트 조회 → geohash 모듈로 셀 집계 (결과 비면 반경 넓혀 1회 재검색)
    local function aggregate(radius)
        local points, perr = locationRepo:findInRadius(lng, lat, radius)
        if perr then return nil, perr end
        return geohash.aggregate(points or {}, {
            by_min = by_min,
            by_max = by_max,
            gender = args.gender,
        })
    end

    local radius  = tonumber(args.radius_m) or 1500
    local rows, rerr = aggregate(radius)
    if rerr then return nil, rerr end

    local widened = false
    if not rows or #rows == 0 then
        radius  = math.max(radius * 4, 5000)
        widened = true
        rows, rerr = aggregate(radius)
        if rerr then return nil, rerr end
    end

    if not rows or #rows == 0 then
        return {
            answer          = build_answer(target, {}),
            target          = target,
            center          = { lat = lat, lng = lng },
            recommendations = {},
        }
    end

    -- 4) 점수화·랭킹 (코드)
    local ranked = score_and_rank(rows)

    -- 5) 상위 N 역지오코딩 (좌표 → 한국어 주소)
    for _, c in ipairs(ranked) do
        c.address = geo.reverse(c.lat, c.lng) or "주소 미상"
    end

    -- 6) 자연어 답변 + 구조화 데이터
    return {
        answer          = build_answer(target, ranked, { widened = widened, radius = radius }),
        target          = target,
        center          = { lat = lat, lng = lng },
        searched_radius_m = radius,
        recommendations = ranked,
    }
end

return RecommendationService
