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

운영은 `docker-compose.production.yml`만 사용합니다. 개발용 Compose와 병합하지 않습니다.
서버 `.env`에 다음 연결 대상을 설정하고, 사용자와 비밀번호는 해당 운영 DB의 접속 정보로
지정하세요. 아래 값은 같은 호스트에서 실행하는 Pingdom Backend의 Compose 구성 기준입니다.

```env
DB_HOST=postgres
DB_PORT=5432
DB_NAME=pingdom
DB_USER=<운영 DB 사용자>
DB_PASSWORD=<운영 DB 비밀번호>
MCP_DB_NETWORK=pingdom_default
```

`MCP_DB_NETWORK`는 PostgreSQL 컨테이너가 이미 참여한 Docker 네트워크 이름입니다.
서로 다른 호스트의 DB라면 해당 네트워크에서 접근 가능한 실제 `DB_HOST`를 사용합니다.
필수 값이 비어 있으면 배포를 중단하며 개발용 DB로 대체하지 않습니다.

| 변수 | 필수 | 설명 |
| --- | --- | --- |
| `PORT` | | 컨테이너 내부 포트. 기본 8080 |
| `DB_*` | ✅ | Postgres 접속 정보. 앱이 PostGIS 함수를 쓰므로 확장이 설치된 DB 여야 한다 |
| `MCP_DB_NETWORK` | 운영 필수 | 기존 PostgreSQL 컨테이너에 접근할 외부 Docker 네트워크 이름 |
| `SESSION_SECRET` | | 현재 세션·쿠키를 쓰는 코드가 없어 사용되지 않는다. 인증 도입 시 랜덤 값으로 |
| `GEMINI_API_KEY` | ✅ | Google AI Studio 키. 없으면 추천 요청이 `LLM_NO_KEY` 로 실패한다 |
| `GEMINI_MODEL` | | 기본값 `gemini-3.1-flash-lite` |
| `MCP_AUTH_TOKEN` | | 설정하면 `/mcp` 가 `mcp-token: <값>` 헤더를 요구한다. 비워두면 무인증(로컬 개발용). **공개 URL 로 노출할 때는 반드시 설정할 것** — 열려 있으면 누구나 DB 조회와 LLM 호출을 태울 수 있다 |
