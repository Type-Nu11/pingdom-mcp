#!/usr/bin/env bash
# MCP Streamable HTTP 전송 계층 검증. 서버가 떠 있어야 한다.
#   ./tests/mcp_http_smoke.sh [BASE_URL]   (기본 http://localhost:8081)
set -uo pipefail

BASE="${1:-http://localhost:8081}"
MCP="$BASE/mcp"
ACCEPT='Accept: application/json, text/event-stream'
CT='Content-Type: application/json'
fails=0

check() { # check <이름> <기대> <실제>
    if [ "$2" = "$3" ]; then
        echo "ok   - $1"
    else
        echo "FAIL - $1 (기대: $2, 실제: $3)"
        fails=$((fails + 1))
    fi
}

# 1) initialize → 200 + Mcp-Session-Id 헤더
resp=$(curl -sS -D /tmp/mcp_h -o /tmp/mcp_b -w '%{http_code}' -X POST "$MCP" -H "$CT" -H "$ACCEPT" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"spring-ai-mcp","version":"1.0"}}}')
check "initialize 200" "200" "$resp"
SESSION=$(grep -i '^mcp-session-id:' /tmp/mcp_h | tr -d '\r' | awk '{print $2}')
[ -n "$SESSION" ] && echo "ok   - Mcp-Session-Id 발급됨 ($SESSION)" || { echo "FAIL - Mcp-Session-Id 헤더 없음"; fails=$((fails+1)); }
check "협상된 protocolVersion" "2025-06-18" "$(python3 -c 'import json;print(json.load(open("/tmp/mcp_b"))["result"]["protocolVersion"])' 2>/dev/null)"

SESS_H="Mcp-Session-Id: $SESSION"
VER_H="MCP-Protocol-Version: 2025-06-18"

# 2) notifications/initialized → 202, 본문 없음
code=$(curl -sS -o /tmp/mcp_b -w '%{http_code}' -X POST "$MCP" -H "$CT" -H "$ACCEPT" -H "$SESS_H" -H "$VER_H" \
    -d '{"jsonrpc":"2.0","method":"notifications/initialized"}')
check "notifications/initialized 202" "202" "$code"
check "알림 응답 본문 없음" "0" "$(wc -c < /tmp/mcp_b | tr -d ' ')"

# 3) tools/list
code=$(curl -sS -o /tmp/mcp_b -w '%{http_code}' -X POST "$MCP" -H "$CT" -H "$ACCEPT" -H "$SESS_H" -H "$VER_H" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
check "tools/list 200" "200" "$code"
check "tool 이름" "recommend_location" "$(python3 -c 'import json;print(json.load(open("/tmp/mcp_b"))["result"]["tools"][0]["name"])' 2>/dev/null)"
check "inputSchema 존재" "object" "$(python3 -c 'import json;print(json.load(open("/tmp/mcp_b"))["result"]["tools"][0]["inputSchema"]["type"])' 2>/dev/null)"

# 4) tools/call
code=$(curl -sS -o /tmp/mcp_b -w '%{http_code}' -m 180 -X POST "$MCP" -H "$CT" -H "$ACCEPT" -H "$SESS_H" -H "$VER_H" \
    -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"recommend_location","arguments":{"region":"대구 수성구","age_min":20,"age_max":39,"gender":"F","radius_m":2000}}}')
check "tools/call 200" "200" "$code"
python3 - <<'PY'
import json
d = json.load(open("/tmp/mcp_b"))["result"]
p = json.loads(d["content"][0]["text"])
t = p["target"]
print("ok   - tools/call 인자 존중" if (t["age_min"], t["age_max"], t["gender"]) == (20, 39, "F")
      else f"FAIL - tools/call 인자 무시됨: {t}")
print(f"       추천 {len(p['recommendations'])}건, isError={d.get('isError')}")
PY

# 5) ping
code=$(curl -sS -o /tmp/mcp_b -w '%{http_code}' -X POST "$MCP" -H "$CT" -H "$ACCEPT" -H "$SESS_H" -H "$VER_H" \
    -d '{"jsonrpc":"2.0","id":4,"method":"ping"}')
check "ping 200" "200" "$code"
check "ping 결과는 빈 객체" "{}" "$(python3 -c 'import json;print(json.dumps(json.load(open("/tmp/mcp_b"))["result"]))' 2>/dev/null)"

# 6) 세션 없는 요청 → 400 / 모르는 세션 → 404
# 세션은 선택 사항 — 헤더 없이도 동작해야 한다 (Gemini Remote MCP 등)
check "세션 헤더 없이도 200" "200" "$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$MCP" -H "$CT" -H "$ACCEPT" \
    -d '{"jsonrpc":"2.0","id":5,"method":"tools/list"}')"
check "모르는 세션 404" "404" "$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$MCP" -H "$CT" -H "$ACCEPT" \
    -H 'Mcp-Session-Id: deadbeef' -d '{"jsonrpc":"2.0","id":6,"method":"tools/list"}')"

# 7) 지원하지 않는 프로토콜 버전 → 400
check "미지원 버전 400" "400" "$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$MCP" -H "$CT" -H "$ACCEPT" \
    -H "$SESS_H" -H 'MCP-Protocol-Version: 1999-01-01' -d '{"jsonrpc":"2.0","id":7,"method":"tools/list"}')"

# 8) 깨진 JSON → 400
check "파싱 실패 400" "400" "$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$MCP" -H "$CT" -H "$ACCEPT" \
    -H "$SESS_H" -H "$VER_H" -d '{not json')"

# 9) GET → 405 (서버 주도 SSE 미지원)
check "GET 405" "405" "$(curl -sS -o /dev/null -w '%{http_code}' "$MCP" -H "$ACCEPT")"

# 10) DELETE 로 세션 종료 → 204, 이후 같은 세션은 404
check "DELETE 204" "204" "$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "$MCP" -H "$SESS_H")"
check "종료된 세션 404" "404" "$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$MCP" -H "$CT" -H "$ACCEPT" \
    -H "$SESS_H" -H "$VER_H" -d '{"jsonrpc":"2.0","id":8,"method":"tools/list"}')"

echo
if [ "$fails" -eq 0 ]; then echo "MCP HTTP smoke OK"; else echo "실패 $fails 건"; exit 1; fi
