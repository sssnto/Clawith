#!/bin/bash
# Clawith — Restart Script
# Stops existing services and starts backend + frontend.
# Usage: ./restart.sh

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$ROOT/backend"
FRONTEND_DIR="$ROOT/frontend"
BACKEND_LOG="/tmp/clawith_backend.log"
FRONTEND_LOG="/tmp/clawith_frontend.log"
BACKEND_PID="/tmp/clawith_backend.pid"
FRONTEND_PID="/tmp/clawith_frontend.pid"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'

# ── Load .env ────────────────────────────────────
if [ -f "$ROOT/.env" ]; then
    set -a
    source "$ROOT/.env"
    set +a
fi

# Default DATABASE_URL if not set
: "${DATABASE_URL:=postgresql+asyncpg://clawith:clawith@localhost:5432/clawith?ssl=disable}"
export DATABASE_URL

# Extract PG port from DATABASE_URL (e.g. localhost:5433 → 5433)
PG_PORT=$(echo "$DATABASE_URL" | grep -oP 'localhost:\K[0-9]+' 2>/dev/null || echo "$DATABASE_URL" | sed -n 's/.*localhost:\([0-9]*\).*/\1/p')
PG_PORT=${PG_PORT:-5432}

cleanup() {
    echo -e "${YELLOW}🔄 Stopping existing services...${NC}"
    # Kill by PID file first
    for pidfile in "$BACKEND_PID" "$FRONTEND_PID"; do
        if [ -f "$pidfile" ]; then
            kill -9 "$(cat "$pidfile")" 2>/dev/null || true
            rm -f "$pidfile"
        fi
    done
    # Kill by port as fallback
    if command -v lsof &>/dev/null; then
        lsof -ti:8008 | xargs kill -9 2>/dev/null || true
        lsof -ti:3008 | xargs kill -9 2>/dev/null || true
    else
        fuser -k 8008/tcp 2>/dev/null || true
        fuser -k 3008/tcp 2>/dev/null || true
    fi
    sleep 1
}

wait_for_port() {
    local port=$1 name=$2 max=$3
    for i in $(seq 1 "$max"); do
        if curl -s -o /dev/null -m 1 "http://localhost:$port" 2>/dev/null; then
            echo -e "  ${GREEN}✅ $name ready (${i}s)${NC}"
            return 0
        fi
        sleep 1
    done
    echo -e "  ${RED}❌ $name failed to start in ${max}s${NC}"
    return 1
}

# Add local PG to PATH if setup.sh installed it
if [ -d "$ROOT/.pg/bin" ]; then
    export PATH="$ROOT/.pg/bin:$PATH"
fi
# Also check common non-standard PG locations
for dir in /www/server/pgsql/bin /usr/local/pgsql/bin; do
    if [ -x "$dir/pg_isready" ] && ! command -v pg_isready &>/dev/null; then
        export PATH="$dir:$PATH"
    fi
done

cleanup

# ── Ensure PostgreSQL is running ─────────────────
if command -v pg_isready &>/dev/null; then
    if ! pg_isready -h localhost -p "$PG_PORT" -q 2>/dev/null; then
        echo -e "${YELLOW}🐘 Starting PostgreSQL (port $PG_PORT)...${NC}"

        STARTED=false
        # Try 1: local instance managed by setup.sh
        if [ -f "$ROOT/.pgdata/PG_VERSION" ] && command -v pg_ctl &>/dev/null; then
            pg_ctl -D "$ROOT/.pgdata" -l "$ROOT/.pgdata/pg.log" start >/dev/null 2>&1 && STARTED=true
        fi
        # Try 2: brew (macOS)
        if [ "$STARTED" = false ] && command -v brew &>/dev/null; then
            brew services start postgresql@15 2>/dev/null || brew services start postgresql 2>/dev/null || true
            STARTED=true
        fi
        # Try 3: systemctl (Linux)
        if [ "$STARTED" = false ] && command -v systemctl &>/dev/null; then
            sudo systemctl start postgresql 2>/dev/null || true
            STARTED=true
        fi

        # Wait for PG to be ready
        for i in $(seq 1 10); do
            if pg_isready -h localhost -p "$PG_PORT" -q 2>/dev/null; then
                echo -e "  ${GREEN}✅ PostgreSQL ready (${i}s)${NC}"
                break
            fi
            sleep 1
            if [ "$i" -eq 10 ]; then
                echo -e "  ${RED}❌ PostgreSQL failed to start on port $PG_PORT${NC}"
                echo "  Check your PostgreSQL installation or run setup.sh first."
                exit 1
            fi
        done
    else
        echo -e "${GREEN}🐘 PostgreSQL already running (port $PG_PORT)${NC}"
    fi
else
    echo -e "${YELLOW}🐘 pg_isready not found — assuming PostgreSQL is running on port $PG_PORT${NC}"
fi

# ── Start backend ────────────────────────────────
echo -e "${YELLOW}🚀 Starting backend...${NC}"
cd "$BACKEND_DIR"
nohup env PYTHONUNBUFFERED=1 \
    PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-}" \
    DATABASE_URL="$DATABASE_URL" \
    .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8008 \
    > "$BACKEND_LOG" 2>&1 &
echo $! > "$BACKEND_PID"
wait_for_port 8008 "Backend" 10

# ── Start frontend ───────────────────────────────
echo -e "${YELLOW}🚀 Starting frontend...${NC}"
cd "$FRONTEND_DIR"
nohup node_modules/.bin/vite --host 0.0.0.0 --port 3008 \
    > "$FRONTEND_LOG" 2>&1 &
echo $! > "$FRONTEND_PID"
wait_for_port 3008 "Frontend" 8

# ── Verify proxy ─────────────────────────────────
echo -e "${YELLOW}🔍 Verifying API proxy...${NC}"
HEALTH=$(curl -s -m 3 http://localhost:3008/api/health 2>/dev/null || echo "FAIL")
if echo "$HEALTH" | grep -q "ok"; then
    echo -e "  ${GREEN}✅ Proxy working${NC}"
else
    echo -e "  ${YELLOW}⚠️  Proxy may need a moment, backend direct check:${NC}"
    curl -s http://localhost:8008/api/health && echo ""
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  Clawith running!${NC}"
echo -e "${GREEN}  Frontend: http://localhost:3008${NC}"
echo -e "${GREEN}  Backend:  http://localhost:8008${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "  Backend log:  tail -f $BACKEND_LOG"
echo -e "  Frontend log: tail -f $FRONTEND_LOG"
