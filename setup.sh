#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$ROOT_DIR/.runtime"
VENV_DIR="$ROOT_DIR/.venv"
UI_DIR="$ROOT_DIR/frontends/ui"
ENV_FILE="$ROOT_DIR/deploy/.env"
BACKEND_PID_FILE="$RUNTIME_DIR/backend.pid"
FRONTEND_PID_FILE="$RUNTIME_DIR/frontend.pid"
BACKEND_LOG="$RUNTIME_DIR/backend.log"
FRONTEND_LOG="$RUNTIME_DIR/frontend.log"
BOOTSTRAP_MARKER="$RUNTIME_DIR/bootstrap.complete"
PORTS_FILE="$RUNTIME_DIR/ports.env"
COMPOSE_FILE="$ROOT_DIR/deploy/compose/docker-compose.yaml"

AIQ_PORT_MIN="${AIQ_PORT_MIN:-6000}"
AIQ_PORT_MAX="${AIQ_PORT_MAX:-6050}"
AIQ_RESERVED_PORTS="${AIQ_RESERVED_PORTS:-}"
BACKEND_PORT="${AIQ_BACKEND_PORT:-6042}"
FRONTEND_PORT="${AIQ_FRONTEND_PORT:-6043}"
NEXT_INTERNAL_PORT="${AIQ_NEXT_INTERNAL_PORT:-6044}"
POSTGRES_PORT="${AIQ_POSTGRES_PORT:-6045}"
CONFIG_FILE="${AIQ_CONFIG_FILE:-configs/config_web_default_llamaindex.yml}"
AIQ_SUPPORT_SERVICES="${AIQ_SUPPORT_SERVICES:-true}"
AIQ_REQUIRE_FULL_SOURCES="${AIQ_REQUIRE_FULL_SOURCES:-false}"

usage() {
  cat <<EOF
Usage: ./setup.sh [--up|--down|--clean]

Flags:
  --up     Bootstrap (once) and start backend + frontend
  --down   Stop backend + frontend started by this script
  --clean  Full reset: --down + remove volumes/artifacts/deps

Optional env vars:
  AIQ_PORT_MIN       Lowest host port setup.sh may use (default: 6000)
  AIQ_PORT_MAX       Highest host port setup.sh may use (default: 6050)
  AIQ_BACKEND_PORT   Backend port (default: 6042)
  AIQ_FRONTEND_PORT  Frontend port (default: 6043)
  AIQ_NEXT_INTERNAL_PORT Next.js dev port behind the gateway (default: 6044)
  AIQ_POSTGRES_PORT  Postgres host port (default: 6045)
  AIQ_CONFIG_FILE    Backend config (default: configs/config_web_default_llamaindex.yml)
  AIQ_SUPPORT_SERVICES Start/stop support services via compose (default: true)
  AIQ_REQUIRE_FULL_SOURCES Require NVIDIA/Tavily/Serper keys on --up (default: false)
EOF
}

log() {
  echo "[setup] $*"
}

ensure_runtime_dir() {
  mkdir -p "$RUNTIME_DIR"
}

load_env() {
  if [ ! -f "$ENV_FILE" ]; then
    log "Missing deploy/.env"
    log "Create it from template manually: cp deploy/.env.example deploy/.env"
    exit 1
  fi

  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a

  AIQ_PORT_MIN="${AIQ_PORT_MIN:-6000}"
  AIQ_PORT_MAX="${AIQ_PORT_MAX:-6050}"
  AIQ_RESERVED_PORTS="${AIQ_RESERVED_PORTS:-}"
  BACKEND_PORT="${AIQ_BACKEND_PORT:-$BACKEND_PORT}"
  FRONTEND_PORT="${AIQ_FRONTEND_PORT:-$FRONTEND_PORT}"
  NEXT_INTERNAL_PORT="${AIQ_NEXT_INTERNAL_PORT:-$NEXT_INTERNAL_PORT}"
  POSTGRES_PORT="${AIQ_POSTGRES_PORT:-$POSTGRES_PORT}"
  CONFIG_FILE="${AIQ_CONFIG_FILE:-$CONFIG_FILE}"
  AIQ_SUPPORT_SERVICES="${AIQ_SUPPORT_SERVICES:-$AIQ_SUPPORT_SERVICES}"
  AIQ_REQUIRE_FULL_SOURCES="${AIQ_REQUIRE_FULL_SOURCES:-$AIQ_REQUIRE_FULL_SOURCES}"
}

validate_required_keys() {
  if [ -z "${NVIDIA_API_KEY:-}" ]; then
    log "Missing NVIDIA_API_KEY in deploy/.env"
    exit 1
  fi

  if [ "$AIQ_REQUIRE_FULL_SOURCES" = "true" ]; then
    if [ -z "${TAVILY_API_KEY:-}" ]; then
      log "Missing TAVILY_API_KEY in deploy/.env (required for full-source mode)."
      exit 1
    fi

    if [ -z "${SERPER_API_KEY:-}" ]; then
      log "Missing SERPER_API_KEY in deploy/.env (required for full-source mode)."
      exit 1
    fi
  fi
}

has_docker_compose() {
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

start_support_services() {
  if [ "$AIQ_SUPPORT_SERVICES" != "true" ]; then
    log "Support services disabled (AIQ_SUPPORT_SERVICES=$AIQ_SUPPORT_SERVICES)."
    return
  fi

  if [ ! -f "$COMPOSE_FILE" ]; then
    log "Compose file not found ($COMPOSE_FILE). Skipping support services."
    return
  fi

  if ! has_docker_compose; then
    log "Docker Compose not available. Skipping support services."
    return
  fi

  POSTGRES_PORT="$(resolve_service_port "$POSTGRES_PORT" "POSTGRES")"

  log "Starting support services (postgres) via Docker Compose on host port $POSTGRES_PORT..."
  (
    cd "$ROOT_DIR/deploy/compose"
    POSTGRES_PORT="$POSTGRES_PORT" docker compose --env-file ../.env -f docker-compose.yaml up -d postgres
  )
}

stop_support_services() {
  if [ "$AIQ_SUPPORT_SERVICES" != "true" ]; then
    return
  fi

  if [ ! -f "$COMPOSE_FILE" ]; then
    return
  fi

  if ! has_docker_compose; then
    return
  fi

  log "Stopping support services (postgres)..."
  (
    cd "$ROOT_DIR/deploy/compose"
    POSTGRES_PORT="$POSTGRES_PORT" docker compose --env-file ../.env -f docker-compose.yaml stop postgres >/dev/null 2>&1 || true
  )
}

clean_support_services() {
  if [ ! -f "$COMPOSE_FILE" ]; then
    return
  fi

  if ! has_docker_compose; then
    return
  fi

  log "Removing compose services, containers, and volumes..."
  (
    cd "$ROOT_DIR/deploy/compose"
    POSTGRES_PORT="$POSTGRES_PORT" docker compose --env-file ../.env -f docker-compose.yaml down -v --remove-orphans >/dev/null 2>&1 || true
  )
}

start_detached() {
  local log_file="$1"
  shift

  if command -v setsid >/dev/null 2>&1; then
    setsid env "$@" >"$log_file" 2>&1 &
  elif command -v nohup >/dev/null 2>&1; then
    nohup env "$@" >"$log_file" 2>&1 &
  else
    env "$@" >"$log_file" 2>&1 &
  fi

  echo "$!"
}

activate_venv() {
  if [ -f "$VENV_DIR/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    export PATH="/usr/bin:/bin:$PATH"
    return
  fi
  if [ -f "$VENV_DIR/Scripts/activate" ]; then
    # shellcheck disable=SC1091
    source "$VENV_DIR/Scripts/activate"
    export PATH="/usr/bin:/bin:$PATH"
    return
  fi
  log "Virtual environment activation script not found in $VENV_DIR"
  exit 1
}

is_pid_running() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

read_pid() {
  local pid_file="$1"
  if [ -f "$pid_file" ]; then
    tr -d '[:space:]' < "$pid_file"
  fi
}

is_port_in_use() {
  local port="$1"

  if command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v ss >/dev/null 2>&1; then
    if ss -ltn | awk '{print $4}' | grep -E "(^|:)${port}$" >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v netstat >/dev/null 2>&1; then
    if netstat -an 2>/dev/null | grep -E "[:.]${port}[[:space:]].*(LISTEN|LISTENING)" >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v powershell.exe >/dev/null 2>&1; then
    if AIQ_CHECK_PORT="$port" powershell.exe -NoProfile -Command 'try { $c = Get-NetTCPConnection -LocalPort ([int]$env:AIQ_CHECK_PORT) -State Listen -ErrorAction Stop | Select-Object -First 1; if ($c) { exit 0 } } catch {}; exit 1' >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v docker >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    local published_ports
    published_ports="$(docker ps --format '{{.Ports}}' 2>/dev/null || true)"
    if AIQ_DOCKER_PORTS="$published_ports" python3 - "$port" <<'PY'
import os
import re
import sys

target = int(sys.argv[1])
ports = os.environ.get("AIQ_DOCKER_PORTS", "")
for match in re.finditer(r"(?:^|[, ])(?:\d+\.\d+\.\d+\.\d+|\[::\]|localhost):(\d+)(?:-(\d+))?->", ports):
    start = int(match.group(1))
    end = int(match.group(2) or start)
    if start <= target <= end:
        raise SystemExit(0)
raise SystemExit(1)
PY
    then
      return 0
    fi
  fi

  # Fallback: if we cannot check, assume free to avoid false blocks.
  return 1
}

wait_for_port() {
  local port="$1"
  local name="$2"
  local attempts="${AIQ_SERVICE_START_ATTEMPTS:-180}"

  local attempt=0
  while [ "$attempt" -lt "$attempts" ]; do
    attempt=$((attempt + 1))
    if is_port_in_use "$port"; then
      log "$name is ready on port $port"
      return 0
    fi
    sleep 1
  done

  log "$name did not become ready on port $port within ${attempts}s"
  return 1
}

wait_for_service_start() {
  local pid_file="$1"
  local port="$2"
  local name="$3"
  local attempts="${AIQ_SERVICE_START_ATTEMPTS:-180}"
  local pid

  local attempt=0
  while [ "$attempt" -lt "$attempts" ]; do
    attempt=$((attempt + 1))
    pid="$(read_pid "$pid_file")"
    if ! is_pid_running "$pid"; then
      log "$name process exited before port $port became ready"
      return 1
    fi

    if is_port_in_use "$port"; then
      sleep 2
      pid="$(read_pid "$pid_file")"
      if ! is_pid_running "$pid"; then
        log "$name process exited after initially opening port $port"
        return 1
      fi
      log "$name is ready on port $port"
      return 0
    fi
    sleep 1
  done

  log "$name did not become ready on port $port within ${attempts}s"
  return 1
}

ensure_port_available_for_service() {
  return 0
}

find_available_port() {
  local start_port="$1"
  local max_port="${2:-$AIQ_PORT_MAX}"
  local port="$start_port"

  if [ "$port" -lt "$AIQ_PORT_MIN" ] || [ "$port" -gt "$max_port" ]; then
    port="$AIQ_PORT_MIN"
  fi

  while [ "$port" -le "$max_port" ]; do
    if ! is_port_in_use "$port" && ! is_port_reserved "$port"; then
      echo "$port"
      return 0
    fi
    port=$((port + 1))
  done

  return 1
}

is_port_reserved() {
  local port="$1"
  case " $AIQ_RESERVED_PORTS " in
    *" $port "*) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_service_port() {
  local requested_port="$1"
  local service_name="$2"
  local resolved_port

  resolved_port="$(find_available_port "$requested_port" "$AIQ_PORT_MAX" || true)"
  if [ -z "$resolved_port" ]; then
    log "Unable to find available port for $service_name in range $AIQ_PORT_MIN-$AIQ_PORT_MAX" >&2
    exit 1
  fi

  if [ "$resolved_port" != "$requested_port" ]; then
    log "Port $requested_port is unavailable or outside $AIQ_PORT_MIN-$AIQ_PORT_MAX. Using $service_name port $resolved_port instead." >&2
  fi

  echo "$resolved_port"
}

write_runtime_ports_file() {
  ensure_runtime_dir

  cat > "$PORTS_FILE" <<EOF
# Generated by setup.sh --up
BACKEND_PORT=$BACKEND_PORT
FRONTEND_PORT=$FRONTEND_PORT
NEXT_INTERNAL_PORT=$NEXT_INTERNAL_PORT
POSTGRES_PORT=$POSTGRES_PORT
AIQ_PORT_MIN=$AIQ_PORT_MIN
AIQ_PORT_MAX=$AIQ_PORT_MAX
BACKEND_URL=http://localhost:$BACKEND_PORT
FRONTEND_URL=http://localhost:$FRONTEND_PORT
NEXT_INTERNAL_URL=http://localhost:$NEXT_INTERNAL_PORT
EOF

  log "Saved runtime ports to $PORTS_FILE"
}

bootstrap_once() {
  ensure_runtime_dir

  local needs_bootstrap="false"

  if [ ! -d "$VENV_DIR" ]; then
    needs_bootstrap="true"
  elif [ ! -f "$BOOTSTRAP_MARKER" ]; then
    needs_bootstrap="true"
  fi

  if [ "$needs_bootstrap" = "false" ]; then
    activate_venv
    if ! python -c "import nat" >/dev/null 2>&1; then
      needs_bootstrap="true"
    fi
  fi

  if [ "$needs_bootstrap" = "false" ]; then
    if [ ! -d "$UI_DIR/node_modules" ]; then
      needs_bootstrap="true"
    fi
  fi

  if [ "$needs_bootstrap" = "false" ]; then
    log "Bootstrap already complete. Skipping venv/dependency installation."
    return
  fi

  log "Bootstrapping environment for UI/API runtime (venv + minimal dependencies)..."

  resolve_python() {
    local candidates=(
      "python3"
      "python"
      "py -3.11"
      "py -3"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
      if $candidate -c "import sys; raise SystemExit(0 if (3, 11) <= sys.version_info < (3, 14) else 1)" >/dev/null 2>&1; then
        echo "$candidate"
        return 0
      fi
    done

    return 1
  }

  local py_bin
  py_bin="$(resolve_python || true)"
  if [ -z "$py_bin" ]; then
    log "Python 3.11, 3.12, or 3.13 not found. Install a supported Python and retry."
    exit 1
  fi

  if [ ! -d "$VENV_DIR" ]; then
    $py_bin -m venv "$VENV_DIR"
  fi

  activate_venv

  local uv_bin
  uv_bin="$(command -v uv || true)"
  if [ -z "$uv_bin" ] && [ -x "$HOME/.local/bin/uv" ]; then
    uv_bin="$HOME/.local/bin/uv"
  fi

  pip_install_with_retry() {
    local max_attempts="${PIP_INSTALL_MAX_ATTEMPTS:-3}"
    local attempt=1

    while [ "$attempt" -le "$max_attempts" ]; do
      if python -m pip install --retries 10 --timeout 120 "$@"; then
        return 0
      fi

      if [ "$attempt" -lt "$max_attempts" ]; then
        log "pip install failed (attempt $attempt/$max_attempts). Retrying..."
      fi
      attempt=$((attempt + 1))
    done

    log "pip install failed after $max_attempts attempts: $*"
    return 1
  }

  if [ -n "$uv_bin" ]; then
    log "Using uv for faster dependency sync..."
    (
      cd "$ROOT_DIR"
      "$uv_bin" sync --package aiq-agent
      "$uv_bin" pip install -e ./frontends/aiq_api
      "$uv_bin" pip install -e ./sources/tavily_web_search
      "$uv_bin" pip install -e ./sources/google_scholar_paper_search
    )
  else
    log "uv not found. Falling back to pip installation."
    pip_install_with_retry --upgrade pip
    # Install workspace-local packages first so root dependency resolution
    # does not attempt to fetch them from PyPI.
    pip_install_with_retry -e "$ROOT_DIR/sources/knowledge_layer"
    pip_install_with_retry "knowledge-layer[llamaindex,foundational_rag]"
    pip_install_with_retry -e "$ROOT_DIR/sources/tavily_web_search"
    pip_install_with_retry -e "$ROOT_DIR/sources/google_scholar_paper_search"
    pip_install_with_retry -e "$ROOT_DIR/frontends/aiq_api"
    pip_install_with_retry -e "$ROOT_DIR"
  fi

  if command -v npm >/dev/null 2>&1; then
    (cd "$UI_DIR" && npm ci)
  fi

  : > "$BOOTSTRAP_MARKER"
  log "Bootstrap complete."
}

run_backend_process() {
  cd "$ROOT_DIR"
  load_env
  BACKEND_PORT="${AIQ_RESOLVED_BACKEND_PORT:-$BACKEND_PORT}"
  activate_venv
  export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"
  exec nat serve --config_file "$CONFIG_FILE" --host 0.0.0.0 --port "$BACKEND_PORT"
}

run_frontend_process() {
  cd "$UI_DIR"
  load_env
  BACKEND_PORT="${AIQ_RESOLVED_BACKEND_PORT:-$BACKEND_PORT}"
  FRONTEND_PORT="${AIQ_RESOLVED_FRONTEND_PORT:-$FRONTEND_PORT}"
  NEXT_INTERNAL_PORT="${AIQ_RESOLVED_NEXT_INTERNAL_PORT:-$NEXT_INTERNAL_PORT}"
  export BACKEND_URL="${BACKEND_URL:-http://localhost:$BACKEND_PORT}"
  export NEXT_PUBLIC_BACKEND_URL="$BACKEND_URL"
  export AIQ_FRONTEND_HOST="${AIQ_FRONTEND_HOST:-0.0.0.0}"
  export PORT="$FRONTEND_PORT"
  export NEXT_DEV_PORT="$NEXT_INTERNAL_PORT"
  export NEXT_INTERNAL_URL="http://localhost:$NEXT_INTERNAL_PORT"
  exec npm run dev
}

start_backend() {
  local existing_pid
  existing_pid="$(read_pid "$BACKEND_PID_FILE")"

  if is_pid_running "$existing_pid"; then
    log "Backend already running (PID $existing_pid)."
    return
  fi

  BACKEND_PORT="$(resolve_service_port "$BACKEND_PORT" "BACKEND")"
  local resolved_backend_port="$BACKEND_PORT"

  log "Starting backend on port $BACKEND_PORT (config: $CONFIG_FILE)..."
  start_detached "$BACKEND_LOG" \
    AIQ_RESOLVED_BACKEND_PORT="$resolved_backend_port" \
    "$ROOT_DIR/setup.sh" --run-backend > "$BACKEND_PID_FILE"
  wait_for_service_start "$BACKEND_PID_FILE" "$BACKEND_PORT" "Backend"
}

start_frontend() {
  local existing_pid
  local previous_reserved_ports
  existing_pid="$(read_pid "$FRONTEND_PID_FILE")"

  if is_pid_running "$existing_pid"; then
    log "Frontend already running (PID $existing_pid)."
    return
  fi

  stop_unix_ui_orphans
  stop_windows_ui_orphans

  previous_reserved_ports="$AIQ_RESERVED_PORTS"
  AIQ_RESERVED_PORTS="$AIQ_RESERVED_PORTS $BACKEND_PORT $POSTGRES_PORT"
  FRONTEND_PORT="$(resolve_service_port "$FRONTEND_PORT" "FRONTEND")"
  AIQ_RESERVED_PORTS="$AIQ_RESERVED_PORTS $FRONTEND_PORT"
  NEXT_INTERNAL_PORT="$(resolve_service_port "$NEXT_INTERNAL_PORT" "NEXT_INTERNAL")"
  AIQ_RESERVED_PORTS="$previous_reserved_ports"
  local resolved_backend_port="$BACKEND_PORT"
  local resolved_frontend_port="$FRONTEND_PORT"
  local resolved_next_internal_port="$NEXT_INTERNAL_PORT"

  if [ ! -d "$UI_DIR/node_modules" ]; then
    log "Installing frontend dependencies..."
    (cd "$UI_DIR" && npm ci)
  fi

  log "Starting frontend on port $FRONTEND_PORT..."
  start_detached "$FRONTEND_LOG" \
    AIQ_RESOLVED_BACKEND_PORT="$resolved_backend_port" \
    AIQ_RESOLVED_FRONTEND_PORT="$resolved_frontend_port" \
    AIQ_RESOLVED_NEXT_INTERNAL_PORT="$resolved_next_internal_port" \
    "$ROOT_DIR/setup.sh" --run-frontend > "$FRONTEND_PID_FILE"
  wait_for_service_start "$FRONTEND_PID_FILE" "$FRONTEND_PORT" "Frontend"
}

stop_service() {
  local name="$1"
  local pid_file="$2"
  local pid
  pid="$(read_pid "$pid_file")"

  if is_pid_running "$pid"; then
    log "Stopping $name (PID $pid)..."
    if command -v taskkill.exe >/dev/null 2>&1; then
      taskkill.exe /PID "$pid" /T /F >/dev/null 2>&1 || true
    else
      kill -- "-$pid" >/dev/null 2>&1 || true
      kill "$pid" >/dev/null 2>&1 || true
    fi
    sleep 1
    if is_pid_running "$pid"; then
      kill -9 -- "-$pid" >/dev/null 2>&1 || true
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  else
    log "$name is not running."
  fi

  rm -f "$pid_file"
}

stop_windows_ui_orphans() {
  if ! command -v powershell.exe >/dev/null 2>&1; then
    return
  fi

  local ui_path="$UI_DIR"
  if command -v cygpath >/dev/null 2>&1; then
    ui_path="$(cygpath -w "$UI_DIR")"
  fi

  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "\
    \$ui = [IO.Path]::GetFullPath('${ui_path//\'/\'\'}'); \
    Get-CimInstance Win32_Process | \
      Where-Object { \$_.CommandLine -and \$_.CommandLine.Contains(\$ui) } | \
      ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }" \
    >/dev/null 2>&1 || true
}

stop_unix_ui_orphans() {
  if ! command -v pgrep >/dev/null 2>&1; then
    return
  fi

  local pids
  pids="$(pgrep -f "$UI_DIR" 2>/dev/null || true)"
  if [ -z "$pids" ]; then
    return
  fi

  log "Stopping orphan frontend processes for $UI_DIR..."
  for pid in $pids; do
    if [ "$pid" != "$$" ]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done

  sleep 1
  pids="$(pgrep -f "$UI_DIR" 2>/dev/null || true)"
  for pid in $pids; do
    if [ "$pid" != "$$" ]; then
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  done
}

do_up() {
  ensure_runtime_dir
  load_env
  validate_required_keys
  start_support_services
  bootstrap_once
  start_backend
  start_frontend
  write_runtime_ports_file

  log "All services are up:"
  log "  Backend : http://localhost:$BACKEND_PORT"
  log "  Frontend: http://localhost:$FRONTEND_PORT"
  if [ "$AIQ_SUPPORT_SERVICES" = "true" ]; then
    log "  Support : postgres via docker compose on port $POSTGRES_PORT (if available)"
  fi
  log "Logs:"
  log "  $BACKEND_LOG"
  log "  $FRONTEND_LOG"
  log "Ports:"
  log "  $PORTS_FILE"
}

do_down() {
  ensure_runtime_dir
  stop_service "Frontend" "$FRONTEND_PID_FILE"
  stop_unix_ui_orphans
  stop_windows_ui_orphans
  stop_service "Backend" "$BACKEND_PID_FILE"
  stop_support_services
  log "All services stopped."
}

do_clean() {
  do_down

  clean_support_services

  log "Removing local runtime artifacts..."
  rm -rf "$RUNTIME_DIR"
  rm -rf "$VENV_DIR"
  rm -rf "$UI_DIR/node_modules"
  rm -rf "$ROOT_DIR/.tmp"
  rm -f "$ROOT_DIR/jobs.db" "$ROOT_DIR/checkpoints.db" "$ROOT_DIR/summaries.db"

  log "Clean reset complete."
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

case "$1" in
  --up)
    do_up
    ;;
  --down)
    do_down
    ;;
  --clean)
    do_clean
    ;;
  -h|--help)
    usage
    ;;
  --run-backend)
    run_backend_process
    ;;
  --run-frontend)
    run_frontend_process
    ;;
  *)
    usage
    exit 1
    ;;
esac
