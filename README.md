<img width="7680" height="4320" alt="MCP_" src="https://github.com/user-attachments/assets/b8fd06ce-cfe3-41ee-a9ee-48b16d48c1d5" />

## Overview

이 저장소는 Pingdom 프로젝트의 **MCP Server 영역**을 관리합니다.

Pingdom Backend Server와 연동되어 사용자 정보를 기반으로 유동인구 데이터를 조회하고,  
LLM 모델을 활용하여 분석 및 정리된 결과를 제공하는 MCP 기반 AI 처리 서버입니다.

본 저장소는 Pingdom 서비스에서 AI 모델과 Backend Server 사이의 연결 계층 역할을 수행합니다.  
사용자의 요청 정보를 기반으로 위치 데이터를 처리하고, LLM을 활용하여 의미 있는 결과를 생성합니다.

유동인구 데이터 자체를 직접 수집하지 않으며, 제공되는 데이터를 기반으로 분석 및 가공하는 역할을 담당합니다.

## Project Status

현재 **GA(General Availability)** 단계입니다.

안정화된 서비스를 제공하며, 기능, 구성, 인터페이스 및 제공 결과의 변경은 Release와
변경 이력을 통해 관리합니다.

| Item | Status |
|---|---|
| Development | `Generally Available` |
| Release | `GA` |
| Stability | `Stable` |

## Repository Role

| Item | Description |
|---|---|
| Type | `Service` |
| Responsibility | MCP 기반 AI 데이터 처리 및 Backend Server 연동 |
| Primary Output | AI 분석 결과 및 데이터 처리 결과 |
| Target | Pingdom Backend Server 및 LLM 기반 처리 시스템 |

## Scope

### Included

- 사용자 정보 기반 유동인구 데이터 조회
- 위치 데이터 처리 및 변환
- LLM 모델 기반 데이터 분석 및 정리
- MCP Server 인터페이스 제공
- Backend Server와 AI 처리 시스템 연결

### Not Included

- 유동인구 데이터 직접 수집
- 사용자 인증 및 권한 관리
- Pingdom 핵심 비즈니스 API 제공
- 데이터 저장소 운영 및 관리

## Key Capabilities

- **사용자 정보 기반 유동인구 조회**: 사용자 요청 정보와 위치 데이터를 기반으로 유동인구 정보를 조회합니다.
- **공간 데이터 처리**: Geohash 및 위치 인코딩 기반으로 위치 데이터를 처리합니다.
- **LLM 기반 데이터 분석**: LLM 모델을 활용하여 조회 데이터를 분석하고 정리합니다.
- **AI 결과 생성**: Backend Server에서 활용 가능한 형태의 분석 결과를 제공합니다.

## Technology and Tools

| Category | Technology |
|---|---|
| Primary | Lua 5.3 |
| Framework | Lapis |
| Database | PostgreSQL, PostGIS |
| Database Access | Pgmoon |
| Runtime | Cqueues |
| AI | Gemini API |
| Delivery | Docker, Docker Compose, GitHub Actions |

## Getting Started

### Requirements

- Git
- Docker 및 Docker Compose
- 추천 분석을 실행할 경우 Gemini API Key와 분석 데이터

### Setup

```bash
git clone https://github.com/Type-Nu11/pingdom-mcp.git
cd pingdom-mcp
```

[환경 변수 템플릿](env_template.md)을 기준으로 루트에 `.env`를 작성합니다.

### Usage

```bash
docker compose build
docker compose up -d
```

개발용 Compose는 PostGIS 데이터베이스를 함께 실행하고 앱의 내부 `8080` 포트를
호스트 `8081`로 전달합니다. 생존 상태는 `http://localhost:8081/health`에서 확인합니다.
컨테이너는 `lapis server`로 실행합니다. `lua app.lua`는 서버 실행 명령이 아닙니다.

## Configuration

설정은 `config.lua`, `.env` 및 [환경 변수 템플릿](env_template.md)에서 관리합니다.

```dotenv
PORT=8080
DB_HOST=db
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=pingdom_dev
GEMINI_API_KEY=your_key_here
GEMINI_MODEL=gemini-3.1-flash-lite
```

위 DB 값은 개발용 Compose 기준입니다. 공개 MCP 연결에는 `MCP_AUTH_TOKEN`을 설정하고
클라이언트가 `mcp-token` 헤더로 전달해야 합니다. 실제 인증정보와 운영 비밀 값은 커밋하지 않습니다.

### GitHub Actions 배포

`main` 브랜치에 push하면 `.github/workflows/deploy-mcp.yml`이 운영 인스턴스에 SSH로 접속해
최신 커밋을 가져오고 Docker Compose로 MCP 앱을 재빌드합니다. 배포 대상 저장소의 GitHub Actions
Secrets에 아래 값을 등록해야 합니다.

| Secret | Description |
|---|---|
| `DEPLOY_HOST` | 운영 서버 호스트명 또는 IP |
| `DEPLOY_USER` | SSH 로그인 사용자 |
| `DEPLOY_PATH` | MCP 저장소의 절대 경로(루트 `/` 제외) |
| `DEPLOY_SSH_KEY` | 배포용 Ed25519 개인 키 |
| `DEPLOY_KNOWN_HOSTS` | `ssh-keyscan`으로 생성한 운영 서버 호스트 키 |

운영 서버에는 Docker Compose v2, `curl`, `sudo`가 설치되어 있어야 하며, 배포 사용자가
`sudo -n docker compose`를 실행할 수 있어야 합니다. `.env`는 서버의 `DEPLOY_PATH`에 미리
생성하고 `MCP_AUTH_TOKEN`, `GEMINI_API_KEY`, 외부 DB 접속 정보를 운영 값으로 설정합니다.

운영 배포는 `docker-compose.production.yml`만 사용합니다. 개발용 `docker-compose.yml`은
`DB_HOST=db`, `DB_NAME=pingdom_dev`를 고정하므로 운영 배포에 병합하지 않습니다.
운영용 파일은 DB 접속 정보가 없으면 실패하며 별도 DB나 볼륨을 생성하지 않습니다.
기존 개발용 DB 컨테이너와 볼륨도 자동 삭제하지 않습니다.

첫 배포 전에 서버 `.env`의 `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`을
Backend의 분석 데이터가 적재된 DB에 맞추고 `MCP_DB_NETWORK`를 해당 PostgreSQL의
기존 Docker 네트워크 이름으로 지정하세요. 같은 호스트의 기본 Backend 구성은
`DB_HOST=postgres`, `DB_NAME=pingdom`, `MCP_DB_NETWORK=pingdom_default`입니다.
접속 비밀번호는 저장소나 Actions 로그에 출력하지 않습니다. 구체적인 항목은
[환경 변수 템플릿](env_template.md)을 참고하세요.

배포는 GitHub Actions concurrency로 중복 실행을 직렬화합니다. 새 이미지 빌드 후
같은 Compose 설정으로 `scripts/check-database.lua`를 실행해 PostGIS와
`mcp_spatial_raw_data`, `map_place`의 필수 컬럼 및 SELECT 권한을 읽기 전용으로 검사합니다.
검사가 실패하면 앱을 교체하지 않습니다. 검사에서는 원시 행을 읽거나 스키마를 변경하지 않습니다.
Docker healthcheck와 `GET /health`가 `200`을 반환해야 배포를 성공 처리합니다.
이 검사는 실제 `recommend_location` 분석이나 PDF 생성 성공까지 보장하지 않으므로,
배포 후 인증된 분석 요청으로 PDF 응답을 별도로 확인해야 합니다. L7 Proxy 또는 별도 로드밸런서가
앞단에서 이 포트를 바라보면 새 컨테이너가 healthy 상태가 된 뒤 트래픽을 넘길 수 있습니다.
배포 서버 체크아웃에 추적 파일 변경이 남아 있어도 기존 변경은 삭제하지 않고 Git stash에
보관한 뒤 배포합니다. 운영 설정은 저장소 파일이 아니라 서버의 `.env`로 관리해야 합니다.

수동 배포도 동일한 파일을 사용합니다.

```bash
docker compose -f docker-compose.production.yml config --quiet
docker compose -f docker-compose.production.yml build app
docker compose -f docker-compose.production.yml run --rm --no-deps -T app lua5.3 scripts/check-database.lua
docker compose -f docker-compose.production.yml up -d --no-build --no-deps --wait app
```

## Verification

변경 범위와 실행 환경에 맞는 검사를 선택합니다.

| Verification | Purpose |
|---|---|
| `python3 scripts/test-production-compose.py` | 개발·운영 Compose 분리 계약 검사 |
| `lua5.3 tests/mcp_protocol.lua` | MCP 프로토콜 처리 검사 |
| `lua5.3 tests/rest_mcp_bridge.lua` | REST와 MCP 연결 계약 검사 |
| `curl -f http://localhost:8081/health` | 실행 중인 앱의 생존 상태 확인 |

Lua 검사는 해당 런타임과 필요한 모듈이 설치된 환경에서 실행합니다. DB 및 Gemini를 사용하는
분석 검증은 별도로 수행합니다. `/health` 성공만으로 추천 분석이나 PDF 응답의 성공을 판단하지 않습니다.

## Repository Structure

```text
.
├── app.lua                        # Lapis 애플리케이션 진입점
├── config.lua                     # 실행 환경과 데이터베이스 설정
├── src
│   ├── ai                         # LLM 어댑터
│   ├── domain                     # 위치·추천 도메인
│   ├── global                     # 환경변수, 예외 및 데이터 접근
│   ├── mcp                        # MCP 전송, 프로토콜 및 세션
│   ├── modules                    # 공간 데이터와 Gemini 연동
│   └── pingdomApplication.lua     # HTTP 라우트 등록
├── scripts                        # 데이터베이스·Compose 검증
├── tests                          # 프로토콜·서비스 검사
├── sql                            # 스키마와 초기 데이터
├── docker-compose.yml             # 개발용 앱과 PostGIS
├── docker-compose.production.yml  # 기존 운영 DB에 연결하는 앱
├── Dockerfile
└── README.md
```

### Architecture

요청은 Lapis HTTP 라우트에서 MCP 또는 REST 컨트롤러로 전달되고,
위치·추천 서비스와 Repository를 통해 PostgreSQL/PostGIS 및 Gemini와 연동됩니다.
구체적인 진입점은 `src/pingdomApplication.lua`와 `src/mcp/`에서 관리합니다.

## Related Repositories

| Repository | Relationship |
|---|---|
| [pingdom-api](https://github.com/Type-Nu11/pingdom-api) | MCP 요청 전달 및 분석 결과 활용 |
| [pingdom-infra](https://github.com/Type-Nu11/pingdom-infra) | MCP 요청 인증과 프록시 라우팅 |

## Documentation

| Document | Description |
|---|---|
| [Environment](env_template.md) | 개발·운영 환경변수와 MCP 인증 설정 |

## Release and Compatibility

현재 버전은 GA(General Availability) 단계입니다.

변경사항은 저장소의 Release 또는 Git 변경 이력을 기준으로 확인합니다.
호환성에 영향을 주는 변경사항은 관련 문서와 변경 이력을 통해 안내합니다.

## License

이 프로젝트의 사용 및 배포 조건은 [MIT License](LICENSE)를 따릅니다.

---

<div align="center">

Part of **Pingdom**

</div>
