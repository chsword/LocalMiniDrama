#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$ROOT_DIR/backend-node"
FRONTEND_DIR="$ROOT_DIR/frontweb"

BACKEND_PORT="${BACKEND_PORT:-5679}"
FRONTEND_PORT="${FRONTEND_PORT:-3013}"

if command -v pnpm >/dev/null 2>&1; then
  PKG_TOOL="pnpm"
  INSTALL_CMD=(pnpm install --registry=https://registry.npmmirror.com)
  RUN_CMD=(pnpm run dev)
else
  PKG_TOOL="npm"
  INSTALL_CMD=(npm install)
  RUN_CMD=(npm run dev)
fi

get_listen_pid() {
  local port="$1"
  ss -ltnp "sport = :${port}" 2>/dev/null \
    | awk -F'pid=' 'NR>1 && NF>1 { split($2, a, ","); print a[1]; exit }'
}

kill_port_if_needed() {
  local port="$1"
  local pid
  pid="$(get_listen_pid "$port" || true)"
  if [[ -n "${pid:-}" ]]; then
    echo "[port] Killing process on :$port (PID $pid)"
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi
}

ensure_deps() {
  local dir="$1"
  if [[ ! -d "$dir/node_modules" ]]; then
    echo "[deps] Installing dependencies in $dir via $PKG_TOOL"
    (
      cd "$dir"
      "${INSTALL_CMD[@]}"
    )
  fi
}

BACKEND_PID=""
FRONTEND_PID=""

cleanup() {
  local code=$?
  set +e
  if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
    kill "$BACKEND_PID" >/dev/null 2>&1
  fi
  if [[ -n "${FRONTEND_PID:-}" ]] && kill -0 "$FRONTEND_PID" >/dev/null 2>&1; then
    kill "$FRONTEND_PID" >/dev/null 2>&1
  fi
  wait "$BACKEND_PID" "$FRONTEND_PID" >/dev/null 2>&1
  exit "$code"
}

trap cleanup INT TERM EXIT

echo "[0/4] Checking ports..."
kill_port_if_needed "$BACKEND_PORT"
kill_port_if_needed "$FRONTEND_PORT"

echo "[1/4] Checking dependencies..."
ensure_deps "$BACKEND_DIR"
ensure_deps "$FRONTEND_DIR"

echo "[2/4] Starting backend on :$BACKEND_PORT"
(
  cd "$BACKEND_DIR"
  "${RUN_CMD[@]}"
) &
BACKEND_PID=$!

echo "[3/4] Starting frontend on :$FRONTEND_PORT"
(
  cd "$FRONTEND_DIR"
  "${RUN_CMD[@]}"
) &
FRONTEND_PID=$!

echo "[4/4] Ready"
echo "Frontend: http://localhost:$FRONTEND_PORT"
echo "Backend : http://localhost:$BACKEND_PORT"
echo "Health  : http://localhost:$BACKEND_PORT/health"

echo "Press Ctrl+C to stop both services."

wait -n "$BACKEND_PID" "$FRONTEND_PID"
status=$?
echo "A dev service exited (status=$status), stopping the other one..."
exit "$status"
