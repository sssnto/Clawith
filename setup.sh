#!/usr/bin/env bash
# ────────────────────────────────────────────────
# Clawith — First-time Setup Script
# Sets up backend, frontend, database, and seed data.
# ────────────────────────────────────────────────
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ROOT="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}  🦞 Clawith — First-time Setup${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

# ── 1. Environment file ──────────────────────────
echo -e "${YELLOW}[1/6]${NC} Checking environment file..."
if [ ! -f "$ROOT/.env" ]; then
    cp "$ROOT/.env.example" "$ROOT/.env"
    echo -e "  ${GREEN}✓${NC} Created .env from .env.example"
    echo -e "  ${YELLOW}⚠${NC}  Please edit .env to set SECRET_KEY and JWT_SECRET_KEY before production use."
else
    echo -e "  ${GREEN}✓${NC} .env already exists"
fi

# ── 2. PostgreSQL setup ──────────────────────────
echo ""
echo -e "${YELLOW}[2/6]${NC} Setting up PostgreSQL..."

# --- Helper: find psql binary ---
find_psql() {
    # Check PATH first
    if command -v psql &>/dev/null; then
        command -v psql
        return 0
    fi
    # Search common non-standard locations
    local search_paths=(
        "/www/server/pgsql/bin"
        "/usr/local/pgsql/bin"
        "/usr/lib/postgresql/15/bin"
        "/usr/lib/postgresql/14/bin"
        "/usr/lib/postgresql/16/bin"
        "/opt/homebrew/opt/postgresql@15/bin"
        "/opt/homebrew/opt/postgresql/bin"
    )
    for dir in "${search_paths[@]}"; do
        if [ -x "$dir/psql" ]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
}

# --- Helper: find a free port starting from $1 ---
find_free_port() {
    local port=$1
    while ss -tlnp 2>/dev/null | grep -q ":${port} " || \
          lsof -iTCP:${port} -sTCP:LISTEN 2>/dev/null | grep -q LISTEN; do
        echo -e "  ${YELLOW}⚠${NC}  Port $port is in use, trying $((port+1))..."
        port=$((port+1))
    done
    echo "$port"
}

PG_PORT=5432
PG_MANAGED_BY_US=false

if PG_BIN_DIR=$(find_psql 2>/dev/null); then
    # If find_psql returned a directory (not a full path), add to PATH
    if [ -d "$PG_BIN_DIR" ]; then
        export PATH="$PG_BIN_DIR:$PATH"
    fi
    echo -e "  ${GREEN}✓${NC} Found psql: $(which psql)"

    # Check if PG is running and we can connect
    if pg_isready -h localhost -p 5432 -q 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} PostgreSQL is running on port 5432"
        PG_PORT=5432

        # Try to create role and database using peer/trust auth
        if ! psql -h localhost -p $PG_PORT -U "$USER" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='clawith'" 2>/dev/null | grep -q 1; then
            if createuser -h localhost -p $PG_PORT clawith 2>/dev/null; then
                psql -h localhost -p $PG_PORT -U "$USER" -d postgres -c "ALTER ROLE clawith WITH LOGIN PASSWORD 'clawith';" &>/dev/null
                echo -e "  ${GREEN}✓${NC} Created PostgreSQL role: clawith"
            else
                echo -e "  ${YELLOW}⚠${NC}  Could not create role via existing PG — will set up a local instance"
                PG_BIN_DIR=""  # Force local PG setup below
            fi
        else
            echo -e "  ${GREEN}✓${NC} Role 'clawith' already exists"
        fi

        if [ -n "$PG_BIN_DIR" ] || command -v psql &>/dev/null; then
            if ! psql -h localhost -p $PG_PORT -U "$USER" -lqt 2>/dev/null | cut -d\| -f1 | grep -qw clawith; then
                createdb -h localhost -p $PG_PORT -O clawith clawith 2>/dev/null && echo -e "  ${GREEN}✓${NC} Created database: clawith"
            else
                echo -e "  ${GREEN}✓${NC} Database 'clawith' already exists"
            fi
        fi
    else
        echo -e "  ${YELLOW}⚠${NC}  PostgreSQL binaries found but service is not running on port 5432"
        echo "  Will set up a local instance..."
        PG_BIN_DIR=""  # Force local PG setup below
    fi
fi

# --- Local PG instance: download + initdb if needed ---
if [ -z "$PG_BIN_DIR" ] && ! (PGPASSWORD=clawith psql -h localhost -p 5432 -U clawith -d clawith -c "SELECT 1" &>/dev/null); then
    echo -e "  ${CYAN}↓${NC} No usable PostgreSQL found — setting up a local instance..."
    PG_MANAGED_BY_US=true
    PGDATA="$ROOT/.pgdata"
    PG_LOCAL="$ROOT/.pg"

    # Download prebuilt PostgreSQL if not already present
    if [ ! -x "$PG_LOCAL/bin/psql" ]; then
        echo "  Downloading PostgreSQL binary..."
        ARCH=$(uname -m)
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')

        if [ "$OS" = "linux" ] && [ "$ARCH" = "x86_64" ]; then
            PG_URL="https://github.com/nicholasgasior/docker-postgres-portable/releases/download/15.4/postgres-15.4-linux-x86_64.tar.gz"
            # Fallback: use the system's package manager download if available
        elif [ "$OS" = "darwin" ]; then
            echo -e "  ${YELLOW}⚠${NC}  On macOS, please install PostgreSQL via Homebrew:"
            echo "    brew install postgresql@15 && brew services start postgresql@15"
            echo "    Then re-run: bash setup.sh"
            exit 1
        else
            echo -e "  ${RED}✗${NC} Unsupported platform: $OS/$ARCH"
            echo "  Please install PostgreSQL manually. See README for details."
            exit 1
        fi

        mkdir -p "$PG_LOCAL"
        if curl -fsSL "$PG_URL" -o /tmp/clawith_pg.tar.gz 2>/dev/null; then
            tar -xzf /tmp/clawith_pg.tar.gz -C "$PG_LOCAL" --strip-components=1 2>/dev/null || \
            tar -xzf /tmp/clawith_pg.tar.gz -C "$PG_LOCAL" 2>/dev/null
            rm -f /tmp/clawith_pg.tar.gz
            echo -e "  ${GREEN}✓${NC} PostgreSQL binary downloaded"
        else
            echo -e "  ${YELLOW}⚠${NC}  Download failed. Trying to use system PostgreSQL binaries..."
            # Try to find initdb/pg_ctl even if psql wasn't in PATH
            for dir in /www/server/pgsql /usr/local/pgsql /usr/lib/postgresql/15; do
                if [ -x "$dir/bin/initdb" ]; then
                    ln -sf "$dir" "$PG_LOCAL"
                    echo -e "  ${GREEN}✓${NC} Linked system PG binaries from $dir"
                    break
                fi
            done
        fi
    fi

    if [ -x "$PG_LOCAL/bin/initdb" ]; then
        export PATH="$PG_LOCAL/bin:$PATH"

        # Find a free port
        PG_PORT=$(find_free_port 5432)

        # Initialize data directory
        if [ ! -f "$PGDATA/PG_VERSION" ]; then
            echo "  Initializing database cluster..."
            initdb -D "$PGDATA" -U postgres --auth=trust -E UTF8 --locale=C >/dev/null 2>&1
            # Configure port
            sed -i "s/#port = 5432/port = $PG_PORT/" "$PGDATA/postgresql.conf" 2>/dev/null || \
            sed -i '' "s/#port = 5432/port = $PG_PORT/" "$PGDATA/postgresql.conf" 2>/dev/null
            sed -i "s/#listen_addresses = 'localhost'/listen_addresses = 'localhost'/" "$PGDATA/postgresql.conf" 2>/dev/null || \
            sed -i '' "s/#listen_addresses = 'localhost'/listen_addresses = 'localhost'/" "$PGDATA/postgresql.conf" 2>/dev/null
            echo -e "  ${GREEN}✓${NC} Database cluster initialized (port $PG_PORT)"
        else
            # Read configured port from existing cluster
            PG_PORT=$(grep "^port = " "$PGDATA/postgresql.conf" 2>/dev/null | awk '{print $3}')
            PG_PORT=${PG_PORT:-5432}
            echo -e "  ${GREEN}✓${NC} Existing data directory found (port $PG_PORT)"
        fi

        # Start PostgreSQL
        if ! pg_isready -h localhost -p "$PG_PORT" -q 2>/dev/null; then
            pg_ctl -D "$PGDATA" -l "$PGDATA/pg.log" start >/dev/null 2>&1
            sleep 2
            if pg_isready -h localhost -p "$PG_PORT" -q 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} PostgreSQL started on port $PG_PORT"
            else
                echo -e "  ${RED}✗${NC} Failed to start PostgreSQL. Check $PGDATA/pg.log"
                exit 1
            fi
        else
            echo -e "  ${GREEN}✓${NC} PostgreSQL already running on port $PG_PORT"
        fi

        # Create role and database
        if ! psql -h localhost -p "$PG_PORT" -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='clawith'" 2>/dev/null | grep -q 1; then
            createuser -h localhost -p "$PG_PORT" -U postgres clawith 2>/dev/null || true
            psql -h localhost -p "$PG_PORT" -U postgres -c "ALTER ROLE clawith WITH LOGIN PASSWORD 'clawith';" &>/dev/null
            echo -e "  ${GREEN}✓${NC} Created role: clawith"
        fi
        if ! psql -h localhost -p "$PG_PORT" -U postgres -lqt 2>/dev/null | cut -d\| -f1 | grep -qw clawith; then
            createdb -h localhost -p "$PG_PORT" -U postgres -O clawith clawith 2>/dev/null
            echo -e "  ${GREEN}✓${NC} Created database: clawith"
        fi
    else
        echo -e "  ${RED}✗${NC} Could not set up PostgreSQL automatically."
        echo "  Please install PostgreSQL manually. See README for details."
        exit 1
    fi
fi

# Ensure DATABASE_URL is correct in .env
DB_URL="postgresql+asyncpg://clawith:clawith@localhost:${PG_PORT}/clawith?ssl=disable"
if grep -q "^DATABASE_URL=" "$ROOT/.env" 2>/dev/null; then
    # Update existing DATABASE_URL
    sed -i "s|^DATABASE_URL=.*|DATABASE_URL=${DB_URL}|" "$ROOT/.env" 2>/dev/null || \
    sed -i '' "s|^DATABASE_URL=.*|DATABASE_URL=${DB_URL}|" "$ROOT/.env" 2>/dev/null
elif grep -q "^# DATABASE_URL=" "$ROOT/.env" 2>/dev/null; then
    # Uncomment and set
    sed -i "s|^# DATABASE_URL=.*|DATABASE_URL=${DB_URL}|" "$ROOT/.env" 2>/dev/null || \
    sed -i '' "s|^# DATABASE_URL=.*|DATABASE_URL=${DB_URL}|" "$ROOT/.env" 2>/dev/null
else
    echo "DATABASE_URL=${DB_URL}" >> "$ROOT/.env"
fi
echo -e "  ${GREEN}✓${NC} DATABASE_URL set (port $PG_PORT)"

# ── 3. Backend setup ─────────────────────────────
echo ""
echo -e "${YELLOW}[3/6]${NC} Setting up backend..."
cd "$ROOT/backend"

if [ ! -d ".venv" ]; then
    echo "  Creating Python virtual environment..."
    python3 -m venv .venv
    echo -e "  ${GREEN}✓${NC} Virtual environment created"
fi

echo "  Installing dependencies..."
.venv/bin/pip install -e ".[dev]" -q 2>&1 | tail -1
echo -e "  ${GREEN}✓${NC} Backend dependencies installed"

# ── 4. Frontend setup ────────────────────────────
echo ""
echo -e "${YELLOW}[4/6]${NC} Setting up frontend..."
cd "$ROOT/frontend"

if [ ! -d "node_modules" ]; then
    echo "  Installing npm packages..."
    npm install --silent 2>&1 | tail -1
fi
echo -e "  ${GREEN}✓${NC} Frontend dependencies installed"

# ── 5. Database setup ────────────────────────────
echo ""
echo -e "${YELLOW}[5/6]${NC} Setting up database..."
cd "$ROOT/backend"

# Source .env for DATABASE_URL
if [ -f "$ROOT/.env" ]; then
    set -a
    source "$ROOT/.env"
    set +a
fi

# ── 6. Seed data ─────────────────────────────────
echo ""
echo -e "${YELLOW}[6/6]${NC} Running database seed..."

if .venv/bin/python seed.py 2>&1 | while IFS= read -r line; do echo "  $line"; done; then
    echo ""
else
    echo ""
    echo -e "  ${RED}✗ Seed failed.${NC}"
    echo "  Common fixes:"
    echo "    1. Make sure PostgreSQL is running"
    echo "    2. Set DATABASE_URL in .env, e.g.:"
    echo "       DATABASE_URL=postgresql+asyncpg://clawith:clawith@localhost:5432/clawith?ssl=disable"
    echo "    3. Create the database first:"
    echo "       createdb clawith"
    echo ""
    echo "  After fixing, re-run: bash setup.sh"
    exit 1
fi

# ── Summary ──────────────────────────────────────
echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 Setup complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo "  To start the application:"
echo ""
echo -e "  ${CYAN}Option A: One-command start${NC}"
echo "    bash restart.sh"
echo ""
echo -e "  ${CYAN}Option B: Manual start${NC}"
echo "    # Terminal 1 — Backend"
echo "    cd backend && .venv/bin/uvicorn app.main:app --reload --port 8008"
echo ""
echo "    # Terminal 2 — Frontend"
echo "    cd frontend && npm run dev -- --port 3008"
echo ""
echo -e "  ${CYAN}Option C: Docker${NC}"
echo "    docker compose up -d"
echo ""
echo "  The first user to register becomes the platform admin."
echo ""
