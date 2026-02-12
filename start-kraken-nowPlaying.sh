#!/usr/bin/env bash
set -euo pipefail

PORT=27123
SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/server/server"

fail() { echo "❌ $*" >&2; exit 1; }
warn() { echo "⚠️  $*" >&2; }
ok()   { echo "✅ $*"; }

[ -d "$SERVER_DIR" ] || fail "Server directory not found: $SERVER_DIR"
cd "$SERVER_DIR"

command -v node >/dev/null 2>&1 || fail "Node.js not found in PATH. Install Node LTS."
command -v npm  >/dev/null 2>&1 || fail "npm not found in PATH."

ok "Node: $(node -v) | npm: $(npm -v)"

[ -f package.json ] || fail "Missing package.json in $SERVER_DIR"
[ -f server.js ] || fail "Missing server.js in $SERVER_DIR"
ok "Found package.json and server.js"

# Port check (best effort)
if command -v lsof >/dev/null 2>&1; then
  if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    warn "Port $PORT appears to be in use. If server is already running, ignore."
  fi
elif command -v ss >/dev/null 2>&1; then
  if ss -ltn | grep -q ":$PORT "; then
    warn "Port $PORT appears to be in use. If server is already running, ignore."
  fi
fi

if [ ! -d node_modules ]; then
  warn "node_modules not found. Installing dependencies..."
  npm install
  ok "Dependencies installed."
else
  ok "Dependencies already installed."
fi

ok "Starting server on http://127.0.0.1:$PORT/ (Ctrl+C to stop)"
npm start
