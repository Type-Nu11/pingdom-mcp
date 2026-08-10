<img width="7680" height="4320" alt="MCP_" src="https://github.com/user-attachments/assets/b8fd06ce-cfe3-41ee-a9ee-48b16d48c1d5" />

# Pingdom MCP Server

## Overview

Pingdom MCP Server는 Pingdom 서비스의 데이터와 비즈니스 로직을
AI Agent가 사용할 수 있도록 제공하는 **Model Context Protocol(MCP) 기반 Backend Server**입니다.

사용자 인증, 지도 기반 장소 검색, 사진 게시글,
장소 추천, 예약, 혜택, 사업자 운영 및 관리자 기능을
MCP Tool과 Resource 형태로 제공합니다.

AI Agent는 MCP Protocol을 통해 Pingdom의 도메인 기능을 호출할 수 있으며,
내부적으로 Lapis 기반 Lua Application Layer와 PostgreSQL/PostGIS 기반
Domain Layer에서 처리됩니다.

---

## Project Status

현재 **SNAPSHOT 개발 단계**입니다.

핵심 MCP Tool과 Domain Logic을 검증하고 있으며,
안정화 이전까지 Tool Schema, 데이터 구조 및 내부 구현은 변경될 수 있습니다.

| Item | Status |
|---|---|
| Development | `In Progress` |
| Release | `SNAPSHOT` |
| Stability | `Experimental` |
| Production Ready | `No` |

---

# Core Capabilities

| Domain | Description |
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
