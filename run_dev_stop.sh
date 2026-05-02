#!/usr/bin/env bash
set -euo pipefail

BACKEND_PORT="${BACKEND_PORT:-5679}"
FRONTEND_PORT="${FRONTEND_PORT:-3013}"

get_listen_pids() {
  local port="$1"
  ss -ltnp "sport = :${port}" 2>/dev/null \
    | awk -F'pid=' 'NR>1 && NF>1 { split($2, a, ","); print a[1] }' \
    | awk '!seen[$0]++'
}

kill_port() {
  local port="$1"
  local pids
  pids="$(get_listen_pids "$port" || true)"
  if [[ -z "${pids:-}" ]]; then
    echo "[stop] No process listening on :$port"
    return
  fi

  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    echo "[stop] Killing PID $pid on :$port"
    kill "$pid" >/dev/null 2>&1 || true
  done <<< "$pids"

  sleep 0.3

  pids="$(get_listen_pids "$port" || true)"
  if [[ -n "${pids:-}" ]]; then
    while IFS= read -r pid; do
      [[ -z "$pid" ]] && continue
      echo "[stop] Force killing PID $pid on :$port"
      kill -9 "$pid" >/dev/null 2>&1 || true
    done <<< "$pids"
  fi
}

kill_port "$BACKEND_PORT"
kill_port "$FRONTEND_PORT"

echo "Done. Ports cleaned: $BACKEND_PORT, $FRONTEND_PORT"
