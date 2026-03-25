# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Clawith is an open-source multi-agent collaboration platform. Every AI agent has a persistent identity, long-term memory, and workspace — they work together as a crew and with users. The platform supports multiple communication channels (Discord, Slack, Feishu, DingTalk, WeCom, Teams), autonomous trigger systems, and skill discovery via Smithery/ModelScope.

## Tech Stack

**Backend:** FastAPI · SQLAlchemy (async) · PostgreSQL · Redis · Alembic · JWT/RBAC · MCP Client (Streamable HTTP)
**Frontend:** React 19 · TypeScript · Vite · Zustand · TanStack React Query · React Router · react-i18next · Custom CSS (Linear-style dark theme)

## Commands

```bash
# Setup
bash setup.sh         # Production install
bash setup.sh --dev   # Dev install (includes pytest, ruff)

# Run locally
bash restart.sh       # Starts backend + frontend (auto-detects Docker)

# Docker
docker compose up -d --build   # Full deployment

# Backend (inside backend/)
cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8008

# Frontend (inside frontend/)
cd frontend && npx vite --host 0.0.0.0 --port 3008

# Linting
ruff check backend/app

# Testing
pytest backend -v
```

## Architecture

```
frontend/ (React 19 + Vite)
├── src/pages/        # Page components (AgentDetail, Chat, Plaza, etc.)
├── src/components/    # Reusable UI components
├── src/services/api.ts  # API client
├── src/stores/       # Zustand state stores
└── src/i18n/         # Translations (en, zh)

backend/app/
├── api/              # 30+ API route modules (auth, agents, tasks, triggers, etc.)
├── models/           # SQLAlchemy ORM models (user, agent, task, trigger, skill, etc.)
├── services/         # Business logic (agent_manager, trigger_daemon, llm_client, etc.)
├── core/             # Security, middleware, logging, permissions
├── schemas/           # Pydantic request/response schemas
└── main.py           # FastAPI app entry + lifespan events (seeding, background tasks)
```

## Key Design Patterns

- **Agent Identity:** Each agent has `soul.md` (personality), `memory.md`, and a private workspace persisted to `backend/agent_data/<agent-id>/`
- **Trigger System:** Agents use 6 trigger types (cron, once, interval, poll, on_message, webhook) managed by `trigger_daemon`
- **Multi-channel:** Each channel (Discord, Slack, Feishu, etc.) has a dedicated stream/gateway manager service
- **RBAC:** Organization-based isolation with role-based access control via JWT
- **Background Tasks:** Started in `main.py` lifespan — trigger daemon, channel WebSocket managers, audit logging

## Database

- PostgreSQL with async SQLAlchemy (asyncpg driver)
- Alembic for migrations (backend/alembic/versions/)
- Seed data loaded on startup: tenants, builtin tools, agent templates, skills, default agents

## Agent Workspace

Agent files (soul.md, memory, skills, workspace) are stored at `backend/agent_data/<agent-id>/` on the host, mounted as `/data/agents/` in containers.
