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
| Load | Backend Server 수집 가능한 사용자 데이터 로드 |
| Place | 유동인구가 가장 활발한 장소 조회 |
| Privacy | 개인정보 처리 요청 관리 |

---

# Architecture

Pingdom MCP Server는
도메인 책임을 기준으로 분리한

**Event-Driven Modular Monolith + MCP Architecture**

구조를 사용합니다.

```text
AI Agent
    │
    │ MCP Protocol
    ▼
Lapis MCP Server
    │
    ├───────────────┐
    ▼               ▼
 MCP Tools       MCP Resources
    │
    ▼
Application Domain Layer
    │
 ┌──┼─────────────┐
 ▼  ▼             ▼
Service      Repository
Layer           Layer
 │               │
 ▼               ▼
PostgreSQL     Redis
PostGIS
 │
 ▼
Async Worker
 │
 ├──── S3
 ├──── FCM
 └──── Email Provider
```

## Docker

간단한 개발용 Docker 환경을 추가했습니다. 로컬에 Lua/Luarocks가 없어도 컨테이너로 앱을 실행할 수 있습니다.

빌드 및 실행:

```bash
docker-compose build --pull --no-cache
docker-compose up
```

기본적으로 앱은 컨테이너 내부 8080 포트를 사용하며, 호스트의 8080으로 포워딩됩니다. Postgres는 `db` 서비스로 함께 올라옵니다.

환경 변수는 루트의 `.env` 파일을 사용하세요. 예:

```env
# .env 예시
PORT=8080
DB_HOST=db
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=pingdom_dev
GEMINI_API_KEY=your_key_here
GEMINI_MODEL=gemini-3.1-flash-lite
```

=======
| Primary | Lua |
| Framework | Lapis |
| Database | PostgreSQL + PostGIS |
| Database Access | Pgmoon |
| Runtime | LuaJIT + Cqueues |
| Delivery | Docker |

## Getting Started

이 저장소를 확인하거나 실행하기 위해 필요한 최소 절차입니다.

### Requirements

- LuaJIT
- Docker
- PostgreSQL
- PostGIS Extension
- LLM API 사용을 위한 환경 구성

### Setup

```bash
git clone https://github.com/Type-Nu11/pingdom-mcp
cd pingdom-mcp
```

PostgreSQL 및 PostGIS 환경을 준비합니다.

PostgreSQL
PostGIS Extension
Usage
luajit app.lua

저장소 실행 방식은 개발 환경 구성에 따라 변경될 수 있습니다.

### Configuration

설정에 필요한 항목은 애플리케이션 초기화 파일 및 환경 구성을 기준으로 관리합니다.

app.lua
src/pingdomApplication.lua

실제 인증정보, API Key, 비밀 값 및 운영 환경 정보는 저장소에 커밋하지 않습니다.

### Verification

저장소 변경사항은 다음 방법으로 검증합니다.

luajit app.lua

검증 방식이 여러 개인 경우 목적별로 구분합니다.

Verification	Purpose
luajit app.lua	MCP Server 실행 및 기본 동작 확인
PostgreSQL + PostGIS 환경	위치 데이터 처리 검증
Docker 실행 환경	서비스 실행 환경 검증
Repository Structure
.
├── README.md
├── app.lua                         # MCP Server 실행 진입점
├── models.lua                      # 데이터 모델 정의
├── sql
│   └── seed_locations.sql          # 초기 위치 데이터 및 테스트 데이터
└── src
    ├── domain
    │   ├── location                # 위치 데이터 관련 도메인 로직
    │   └── recommendation          # 추천 관련 도메인 로직
    ├── global
    │   ├── exceptions               # 공통 예외 처리
    │   └── repository               # 공통 Repository 계층
    ├── modules
    │   ├── GeoEncoder.lua           # 위치 데이터 인코딩 처리
    │   ├── baseRepository.lua       # Repository 기본 기능
    │   ├── geohash.lua              # Geohash 기반 공간 데이터 처리
    │   └── groqClient.lua           # LLM API 연동 모듈
    └── pingdomApplication.lua       # 애플리케이션 초기화 및 구성

실제 구조를 기준으로 주요 디렉터리와 파일만 설명합니다.

Related Repositories
Repository	Relationship
Pingdom Backend Server	MCP 요청 전달 및 결과 활용
Pingdom Infrastructure	서비스 배포 및 운영 환경 관리

공개되어 있거나 접근 가능한 저장소만 연결합니다.

### Documentation
Document	Description
-	별도 공개 문서 없음
Release and Compatibility

현재 버전은 GA(General Availability) 단계입니다.

호환성에 영향을 주는 변경사항은 Release와 관련 문서를 통해 안내합니다.
변경사항은 저장소의 Release 또는 변경 이력을 기준으로 확인합니다.
### License

이 프로젝트는 MIT License를 따릅니다.

자세한 내용은 LICENSE 파일을 참고하세요.

Part of Pingdom
