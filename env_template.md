# .env for local docker-compose
```
PORT=
DB_HOST=
DB_PORT=
DB_USER=
DB_PASSWORD=
DB_NAME=
SESSION_SECRET=
GEMINI_API_KEY=
GEMINI_MODEL=
MCP_AUTH_TOKEN=
```

| 변수 | 필수 | 설명 |
| --- | --- | --- |
| `PORT` | | 컨테이너 내부 포트. 기본 8080 |
| `DB_*` | ✅ | Postgres 접속 정보. 앱이 PostGIS 함수를 쓰므로 확장이 설치된 DB 여야 한다 |
| `SESSION_SECRET` | | 현재 세션·쿠키를 쓰는 코드가 없어 사용되지 않는다. 인증 도입 시 랜덤 값으로 |
| `GEMINI_API_KEY` | ✅ | Google AI Studio 키. 없으면 추천 요청이 `LLM_NO_KEY` 로 실패한다 |
| `GEMINI_MODEL` | | 기본값 `gemini-3.1-flash-lite` |
| `MCP_AUTH_TOKEN` | | 설정하면 `/mcp` 가 `Authorization: Bearer <값>` 을 요구한다. 비워두면 무인증(로컬 개발용). **공개 URL 로 노출할 때는 반드시 설정할 것** — 열려 있으면 누구나 DB 조회와 LLM 호출을 태울 수 있다 |
