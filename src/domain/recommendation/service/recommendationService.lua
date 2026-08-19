-- src/domain/recommendation/service/recommendationService.lua
-- 업종 + 지역 → Gemini(함수콜)로 "타깃 인구통계"만 추론 → 반경 내 포인트 조회 → geohash 모듈로 셀 집계
-- → 점수화·랭킹·역지오코딩은 코드에서 결정적으로 처리(한글 깨짐/환각 방지) → 구조화 JSON 반환
local geo          = require("src.modules.GeoEncoder")
local geohash      = require("src.modules.geohash")
local locationRepo = require("src.global.repository.locationRepository")
local tool         = require("src.domain.recommendation.tool.recommendationTool")
local llmClient    = require("src.ai.llmClient")
local cjson        = require("cjson")

local THIS_YEAR = 2026
local TOP_N     = 5

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

-- 호출자가 직접 지정한 타깃 조건. 지정된 값은 LLM 추론보다 항상 우선한다.
local ARG_KEYS = { "region", "age_min", "age_max", "gender", "radius_m" }

local function normalize_gender(g)
    if type(g) ~= "string" or g == "" then return nil end
    g = g:upper()
    if g == "M" or g == "F" then return g end
    return "ANY"
end

local function explicit_args(input, region)
    return {
        region   = region,
        age_min  = tonumber(input.age_min),
        age_max  = tonumber(input.age_max),
        gender   = normalize_gender(input.gender),
        radius_m = tonumber(input.radius_m),
    }
end

-- input: { message=자유질문 } 또는 { business=업종, region=지역 }
--        MCP 툴 경로처럼 { region, age_min, age_max, gender, radius_m } 를 직접 넘길 수도 있다.
function RecommendationService.recommend(input)
    local business = input.business or input["업종"]
    local region   = input.region   or input["지역"]
    local message  = input.message  or input["질문"]
    if not message and not (business or region) then
        return nil, "INVALID_INPUT"
    end

    local given = explicit_args(input, region)
    local args

    -- 1) 타깃 결정: 지역·연령이 모두 주어졌으면 LLM 추론을 생략(결정적·빠름),
    --    아니면 LLM 강제 툴 호출로 추론한 뒤 명시된 값으로 덮어쓴다.
    if given.region and given.age_min and given.age_max then
        args = given
        args.gender = args.gender or "ANY"
    else
        local user_content = tool.buildUserMessage({
            business = business,
            region = region,
            message = message,
        })

        local ai = llmClient.createClient("gemini")

        local resp, err = ai:chat({
            messages    = {
                { role = "system", content = tool.SYSTEM_PROMPT },
                { role = "user",   content = user_content },
            },
            tools       = tool.getTools(),
            tool_choice = "required",
        })

        if not resp then return nil, err end
        if resp.error then return nil, "LLM_ERROR:" .. (resp.error.message or "") end

        local msg = resp.choices and resp.choices[1] and resp.choices[1].message
        if not msg then return nil, "LLM_EMPTY" end

        local call = tool.parseToolCall(msg)
        if not call then return nil, "LLM_NO_TOOLCALL" end

        local ok, decoded = pcall(cjson.decode, call["function"].arguments)
        if not ok then return nil, "LLM_BAD_ARGS" end

        args = decoded
        for _, k in ipairs(ARG_KEYS) do
            if given[k] ~= nil then args[k] = given[k] end
        end
    end

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
