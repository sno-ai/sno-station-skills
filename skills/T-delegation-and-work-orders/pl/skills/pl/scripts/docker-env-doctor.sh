#!/usr/bin/env bash
# docker-env-doctor.sh — deterministic start/restart verdict for dev Docker services.
# Agents should not restart a running service without a RESTART_OK verdict from this
# script: the decision is code, not model discretion.
# Needs: docker, jq, curl, flock, ss, git, GNU coreutils/findutils (checked at start).
#
# Modes:
#   docker-env-doctor.sh <service>                 judge only (prints verdict)
#   docker-env-doctor.sh <service> --want start|restart   judge a specific intent
#   docker-env-doctor.sh <service> --execute       judge under a per-service file
#       lock and, if the verdict allows, run the graceful rebuild IMMEDIATELY in
#       the same lock scope (closes the verdict→action race window).
#       ENV_DOCTOR_REBUILD_CMD may name an executable that accepts the service;
#       otherwise --execute uses docker compose up -d --build --force-recreate.
#       Residual risk stated openly: external clients submitting new work do not
#       consult the lock — that gap is inherent to any restart tool; the lock
#       reduces the window to the revalidate→rebuild instant.
#       The lock file lives in ${SNO_SCRATCH:-${TMPDIR:-/tmp}}.
#
# Optional settings: ENV_DOCTOR_REBUILD_CMD (above); ENV_DOCTOR_COUNTER_REQUIRED_RE (services
# matching it must pass a work-counter probe); ENV_DOCTOR_QUEUES (space-separated Redis queues
# to check for pending work).
#
# FAIL-CLOSED PRINCIPLE: this script
# authorizes touching live services, so every signal it cannot POSITIVELY
# verify blocks the action (INDETERMINATE). Command success is checked
# separately from empty results everywhere, including the matchers.
#
# Exit codes: 0 = action allowed (START or RESTART_OK) / executed successfully
#             3 = BLOCKED_BUSY    (someone else's work is on the service)
#             4 = NO_GROUNDS      (running fine; no restart justification)
#             5 = INDETERMINATE   (a safety signal could not be verified; no action)
#             2 = usage/resolution/lock error
#
# Locked thresholds (env-overridable only for tests, never in dispatches):
ERR_WINDOW="${ENV_DOCTOR_ERR_WINDOW:-10m}"      # error log window
ERR_THRESHOLD="${ENV_DOCTOR_ERR_THRESHOLD:-20}" # error lines in window
BUSY_WINDOW="${ENV_DOCTOR_BUSY_WINDOW:-5m}"     # traffic window
# Services matching this regex must pass a work-counter probe before a restart is allowed;
# it is matched on the requested alias AND the resolved container name, so aliases cannot bypass it:
COUNTER_REQUIRED_RE="${ENV_DOCTOR_COUNTER_REQUIRED_RE:-}"
COUNTER_KEY_RE='queue|pending|in_?flight|active'
set -uo pipefail

die() { echo "docker-env-doctor: $*" >&2; exit 2; }
for tool in docker jq grep curl find date flock mktemp ss; do
  command -v "$tool" >/dev/null || die "required tool missing: $tool"
done

SVC="${1:-}"; [ -n "$SVC" ] || die "usage: docker-env-doctor.sh <service> [--want start|restart | --execute]"
# Some dev containers carry the checkout directory name as a prefix.
PROJ="$(basename -- "$(git rev-parse --show-toplevel 2>/dev/null)")"
WANT="auto"; EXECUTE=0
if [ "$#" -gt 1 ]; then
  case "$2" in
    --want)
      [ "$#" -eq 3 ] || die "--want needs exactly one value: start|restart"
      case "$3" in start|restart) WANT="$3" ;; *) die "--want must be exactly 'start' or 'restart' (got '$3')" ;; esac ;;
    --execute)
      [ "$#" -eq 2 ] || die "--execute takes no further arguments"
      EXECUTE=1 ;;
    *) die "unknown option '$2' (use --want start|restart, or --execute)" ;;
  esac
fi

# --- execute mode: canonical lock, judge under lock, act on allowing verdict --
if [ "$EXECUTE" -eq 1 ]; then
  # Pre-judge WITHOUT the lock only to learn the canonical container identity —
  # aliases must map to one lock.
  PREOUT=$("$0" "$SVC"); PRERC=$?
  if [ "$PRERC" -ne 0 ]; then printf '%s\n' "$PREOUT"; exit "$PRERC"; fi
  CANON=$(printf '%s\n' "$PREOUT" | grep -oP 'resolved target: \K[^]]+' | head -1)
  [ "$CANON" = "new container" ] && CANON=""
  LOCKKEY="${CANON:-$SVC}"
  LOCK="${SNO_SCRATCH:-${TMPDIR:-/tmp}}/docker-env-doctor-$(printf '%s' "$LOCKKEY" | tr -c 'a-zA-Z0-9_-' '_').lock"
  exec 9>"$LOCK" || die "cannot open lock file $LOCK"
  flock -n 9 || die "another docker-env-doctor holds the lock for '$LOCKKEY' — retry later"
  # Authoritative judgment happens UNDER the lock (the pre-judge may be stale):
  OUT=$("$0" "$SVC"); RC=$?
  printf '%s\n' "$OUT"
  case "$RC" in
    0) ;;                      # START or RESTART_OK — proceed under the held lock
    *) exit "$RC" ;;
  esac
  VERD=$(printf '%s\n' "$OUT" | grep -oP '^VERDICT: \K.+' | head -1)
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "--execute must run inside the service's repo"
  CONT=$(printf '%s\n' "$OUT" | grep -oP 'resolved target: \K[^]]+' | head -1)
  [ "$CONT" = "new container" ] && CONT=""
  resolve_cont() { # rebuild may create the container fresh (START path)
    local names
    names=$(docker ps -a --format '{{.Names}}' | grep -F -- "$SVC") || return 1
    [ "$(printf '%s\n' "$names" | wc -l)" -eq 1 ] || return 1
    printf '%s\n' "$names"
  }
  # A RESTART_OK execution demands a parsed
  # container AND a successful baseline inspection — 'none' may never stand in
  # for an existing container's StartedAt.
  BEFORE="none"
  if [ "$VERD" = "RESTART_OK" ]; then
    [ -n "$CONT" ] || die "RESTART_OK but resolved target unparsable — refusing to execute"
    BEFORE=$(docker inspect -f '{{.State.StartedAt}}' "$CONT" 2>/dev/null) || die "baseline StartedAt inspection failed for $CONT — refusing to execute"
    [ -n "$BEFORE" ] || die "baseline StartedAt empty for $CONT — refusing to execute"
  fi
  # A new StartedAt plus running/healthy confirms the container changed.
  # A successful command with an unchanged container is not enough.
  REBUILD=(docker compose up -d --build --force-recreate "$SVC")
  [ -z "${ENV_DOCTOR_REBUILD_CMD:-}" ] || REBUILD=("$ENV_DOCTOR_REBUILD_CMD" "$SVC")
  RLOG=$(mktemp)
  echo "executing: ${REBUILD[*]}   (lock held: $LOCK; build log: $RLOG)"
  setsid bash -c 'cd -- "$1"; shift; exec "$@"' _ "$ROOT" "${REBUILD[@]}" >"$RLOG" 2>&1 &
  RPID=$!
  DEADLINE=$((SECONDS + 300)); OK=""; STABLE=0; LAST_NEW=""
  while [ "$SECONDS" -lt "$DEADLINE" ]; do
    sleep 3
    [ -z "$CONT" ] && CONT=$(resolve_cont || true)
    if [ -n "$CONT" ]; then
      NOWST=$(docker inspect -f '{{.State.StartedAt}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONT" 2>/dev/null || echo "?|?|?")
      STARTED_AT="${NOWST%%|*}"; REST="${NOWST#*|}"; RSTATE="${REST%%|*}"; RHEALTH="${REST#*|}"
      if [ "$STARTED_AT" != "?" ] && [ -n "$STARTED_AT" ] && [ "$STARTED_AT" != "$BEFORE" ] && [ "$RSTATE" = "running" ]; then
        if [ "$RHEALTH" = "healthy" ]; then
          OK=1; break   # healthcheck contract satisfied — authoritative
        elif [ "$RHEALTH" = "none" ]; then
          # Without a healthcheck, one 'running' sample proves nothing —
          # demand 4 consecutive stable polls (~12s) with an unchanging new
          # StartedAt (a crash loop resets StartedAt and the counter with it).
          if [ "$STARTED_AT" = "$LAST_NEW" ]; then STABLE=$((STABLE+1)); else STABLE=1; LAST_NEW="$STARTED_AT"; fi
          [ "$STABLE" -ge 4 ] && { OK=1; break; }
        else
          STABLE=0   # starting/unhealthy — keep waiting for healthy
        fi
      fi
    fi
    if ! kill -0 "$RPID" 2>/dev/null; then
      wait "$RPID"; RRC=$?
      if [ "$RRC" -ne 0 ]; then
        echo "rebuild process exited rc=$RRC before the container came up — build log kept: $RLOG (last lines:)" >&2
        tail -15 "$RLOG" >&2; exit 2
      fi
    fi
  done
  kill -- -"$RPID" 2>/dev/null; wait "$RPID" 2>/dev/null
  if [ -n "$OK" ]; then
    echo "post-action: $CONT restarted (new StartedAt $STARTED_AT), state=running/$RHEALTH$( [ "$RHEALTH" = none ] && printf ' (stable %s polls)' "$STABLE" ) ✓"
    echo "build log kept: $RLOG"
    echo "reminder: send the PL an info card through Reach (audit)"
    exit 0
  fi
  echo "post-action: no fresh healthy container within 300s — REAL FAILURE. Build log kept: $RLOG (last lines:)" >&2
  tail -15 "$RLOG" >&2
  exit 2
fi

CONTAINER=""
verdict() { # verdict <VERDICT> <exit> <evidence...>
  local v="$1" code="$2"; shift 2
  echo "VERDICT: $v"
  echo "service: $SVC  container: ${CONTAINER:-<none>}"
  local ev; for ev in "$@"; do echo "  - $ev"; done
  case "$v" in
    START)      echo "allowed: $0 $SVC --execute   [resolved target: ${CONTAINER:-new container}]";;
    RESTART_OK) echo "allowed: $0 $SVC --execute   [resolved target: $CONTAINER] -- lock+revalidate+graceful rebuild; direct kill/pkill remains FORBIDDEN"
                echo "after:   --execute verifies health; then send the PL an info card through Reach (audit)";;
    BLOCKED_BUSY)  echo "action:  do NOT restart; send the PL a Reach card with the evidence above";;
    NO_GROUNDS)    echo "action:  no restart; investigate via docker logs $SVC, fix the actual cause";;
    INDETERMINATE) echo "action:  a safety signal could not be verified — no action authorized. Fix the probe path or inspect manually, then re-run";;
  esac
  # audit trail (best-effort)
  local root; root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$root" ]; then
    local dir="$root/ai-doc/ACTIVE/PL"
    [ -d "$dir" ] && jq -cn --arg t "$(date -u +%Y%m%dT%H%M%SZ)" --arg s "$SVC" --arg c "${CONTAINER:-}" \
      --arg v "$v" --arg w "$WANT" --arg e "$*" \
      '{ts:$t,service:$s,container:$c,verdict:$v,want:$w,evidence:$e}' \
      >> "$dir/docker-env-doctor-verdicts.jsonl" 2>/dev/null
  fi
  exit "$code"
}

# --- resolve container (fixed-string; matcher ERROR ≠ no-match; both fail closed differently) --
if ! ALL=$(docker ps -a --format '{{.Names}}' 2>&1); then
  verdict INDETERMINATE 5 "container enumeration failed (docker ps -a): ${ALL:-no output} — cannot distinguish 'absent' from 'unknown'; no action authorized"
fi
for cand in "$SVC" "$PROJ-$SVC"; do
  printf '%s\n' "$ALL" | grep -Fxq -- "$cand"; rc=$?
  if [ "$rc" -eq 0 ]; then CONTAINER="$cand"; break
  elif [ "$rc" -ge 2 ]; then verdict INDETERMINATE 5 "container matcher errored (grep rc=$rc) — cannot resolve '$SVC'; no action authorized"
  fi
done
if [ -z "$CONTAINER" ]; then
  MATCHES=$(printf '%s\n' "$ALL" | grep -F -- "$SVC"); rc=$?
  [ "$rc" -ge 2 ] && verdict INDETERMINATE 5 "container matcher errored (grep rc=$rc) — cannot resolve '$SVC'; no action authorized"
  NMATCH=$(printf '%s\n' "$MATCHES" | grep -c . || true)
  if [ "$NMATCH" -gt 1 ]; then
    die "ambiguous service '$SVC' matches multiple containers: $(echo "$MATCHES" | tr '\n' ' ')— pass the exact container name"
  fi
  CONTAINER="$MATCHES"
fi

# --- state resolution: START only for confirmed-absent/stopped --------------
STATE="absent"
if [ -n "$CONTAINER" ]; then
  STATE=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null) || STATE="inspect-failed"
  [ -z "$STATE" ] && STATE="inspect-failed"
fi
case "$STATE" in
  absent|exited|created|dead)
    verdict START 0 "container state: $STATE (fresh evidence: docker inspect $(date -u +%H:%M:%SZ))";;
  running) ;;
  *)  # paused / restarting / removing / inspect-failed — fail closed
    verdict INDETERMINATE 5 "container state: $STATE — neither cleanly stopped nor running; no action authorized (re-inspect: docker inspect $CONTAINER)";;
esac
[ "$WANT" = "start" ] && verdict NO_GROUNDS 4 "already running (state=running); start request is moot"

# --- collect logs ONCE, success-checked (log failure = fail closed) ----------
if ! ERRLOG=$(docker logs --since "$ERR_WINDOW" "$CONTAINER" 2>&1); then
  verdict INDETERMINATE 5 "docker logs ($ERR_WINDOW window) failed — cannot assess error/exhaustion state; no action authorized"
fi
if ! BUSYLOG=$(docker logs --since "$BUSY_WINDOW" "$CONTAINER" 2>&1); then
  verdict INDETERMINATE 5 "docker logs ($BUSY_WINDOW window) failed — cannot assess traffic; no action authorized"
fi

# --- running: gather restart grounds -------------------------------
EVIDENCE=(); GROUNDS=0

HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER")
RESTARTS=$(docker inspect -f '{{.RestartCount}}' "$CONTAINER")
ERRN=$(printf '%s\n' "$ERRLOG" | grep -cE 'Traceback|ERROR|FATAL|CRITICAL' || true)
# lifetime RestartCount is informational only — a restart years ago is not a
# current crash loop (a lifetime count would make RESTART_OK permanent).
if [ "$HEALTH" = "unhealthy" ] || [ "$ERRN" -ge "$ERR_THRESHOLD" ]; then
  GROUNDS=1; EVIDENCE+=("crash/error loop: health=$HEALTH err_lines(${ERR_WINDOW})=$ERRN (threshold $ERR_THRESHOLD); lifetime_restarts=$RESTARTS (informational)")
fi

STARTED=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER")
STARTED_EPOCH=$(date -d "$STARTED" +%s)
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
CHANGED=$(find "$ROOT" -maxdepth 3 \( -name 'pyproject.toml' -o -name 'uv.lock' -o -name 'package.json' -o -name 'bun.lock*' -o -name 'Dockerfile*' -o -name 'docker-compose*.yml' -o -name 'compose*.yml' \) -newermt "@$STARTED_EPOCH" 2>/dev/null | head -5)
if [ -n "$CHANGED" ]; then
  GROUNDS=1; EVIDENCE+=("env changed since container start ($STARTED): $(echo "$CHANGED" | tr '\n' ' ')")
fi

OOM=$(docker inspect -f '{{.State.OOMKilled}}' "$CONTAINER")
EXH=$(printf '%s\n' "$ERRLOG" | grep -cE 'OutOfMemory|OOMKilled|Cannot allocate|pool.*(exhausted|timeout)|Too many open files' || true)
if [ "$OOM" = "true" ] || [ "$EXH" -gt 0 ]; then
  GROUNDS=1; EVIDENCE+=("resource exhaustion: oom_killed=$OOM exhaustion_lines(${ERR_WINDOW})=$EXH")
fi

if [ "$GROUNDS" -eq 0 ]; then
  verdict NO_GROUNDS 4 "health=$HEALTH restarts=$RESTARTS err_lines=$ERRN env_changed=no exhaustion=no — no restart ground holds"
fi

# --- busy check: is someone else's work on it? (every probe fail-closed) --
# HTTP write traffic in access logs — access-log shape only (METHOD + " /"),
# so internal log prose like "cleanup: DELETE 0" can't false-positive.
TRAFFIC=$(printf '%s\n' "$BUSYLOG" | grep -E '(POST|PUT|DELETE|PATCH) /' | grep -cv '/health' || true)
# Work-counter probe. Port discovery is success-checked and covers EVERY
# host binding (0.0.0.0 / [::] / 127.0.0.1) — discovery failure or a
# wrong-port pick must not silently skip counters. Outcomes:
#   ok | ok-no-recognized-counters | endpoint-absent | no-published-port |
#   failed | port-discovery-failed
if ! PORTMAP=$(docker port "$CONTAINER" 2>&1); then
  verdict INDETERMINATE 5 "${EVIDENCE[@]}" "port discovery failed (docker port): ${PORTMAP:-no output} — cannot locate the health probe; no action authorized"
fi
# Parse EVERY mapping line (address-specific bindings must not read
# as portless). Line shape: "<cport>/<proto> -> <hostaddr>:<hostport>"
MAPPINGS=$(printf '%s\n' "$PORTMAP" | awk -F' -> ' 'NF==2 {print $2}' | sort -u)
HPORTS=$(printf '%s\n' "$MAPPINGS" | grep -oE '[0-9]+$' | sort -u || true)
CPORTS=$(printf '%s\n' "$PORTMAP" | awk -F'/' 'NF>1 {print $1}' | sort -u)
probe_addr() { # map a bind address to something curl can reach
  case "$1" in 0.0.0.0|'[::]'|::) echo "127.0.0.1" ;; \[*\]) printf '%s' "$1" ;; *) printf '%s' "$1" ;; esac
}
HPROBE="no-published-port"; HBUSY=""; HPORT=""
if [ -n "$MAPPINGS" ]; then
  HPROBE="endpoint-absent"; SAW_FAIL=0
  for m in $MAPPINGS; do
    p="${m##*:}"; a=$(probe_addr "${m%:*}")
    HTMP=$(mktemp); HTTP=$(curl -s -m 3 -o "$HTMP" -w '%{http_code}' "http://$a:$p/health" 2>/dev/null || true)
    HTTP="${HTTP:-000}"
    if [ "$HTTP" = "200" ]; then
      HPORT="$p"
      if HBUSY=$(jq -r --arg re "$COUNTER_KEY_RE" '[paths(type=="number") as $p | {k: ($p|join(".")), v: getpath($p)} | select((.k|test($re;"i")) and .v > 0) | "\(.k)=\(.v)"] | join(" ")' "$HTMP" 2>/dev/null); then
        HPROBE="ok"
        if ! jq -e --arg re "$COUNTER_KEY_RE" '[paths(type=="number") as $p | ($p|join("."))] | map(select(test($re;"i"))) | length > 0' "$HTMP" >/dev/null 2>&1; then
          HPROBE="ok-no-recognized-counters"
        fi
      else
        HPROBE="unparseable"; HBUSY=""
      fi
      rm -f "$HTMP"; break
    elif [ "$HTTP" != "404" ]; then SAW_FAIL=1
    fi
    rm -f "$HTMP"
  done
  [ "$HPROBE" = "endpoint-absent" ] && [ "$SAW_FAIL" -eq 1 ] && HPROBE="failed(no port answered; at least one connection failure)"
fi
# Policy: services that require the work-counter probe (identity match on requested alias OR
# resolved container) demand HPROBE=ok. Others: failed/unparseable blocks;
# a conclusive no-published-port / all-404 means no HTTP contract exists —
# proceed on the success-checked log + queue signals, stated in the evidence.
if [ -n "$COUNTER_REQUIRED_RE" ] && printf '%s %s' "$SVC" "$CONTAINER" | grep -qE "$COUNTER_REQUIRED_RE"; then
  if [ "$HPROBE" != "ok" ]; then
    verdict INDETERMINATE 5 "${EVIDENCE[@]}" "work-counter probe: '$SVC' ($CONTAINER) requires a successful work-counter probe, got $HPROBE (ports: ${HPORTS:-none}) — cannot verify idle; no action authorized"
  fi
else
  case "$HPROBE" in
    failed*|unparseable)
      verdict INDETERMINATE 5 "${EVIDENCE[@]}" "health probe $HPROBE (ports: ${HPORTS:-none}) — cannot verify the service is idle; no action authorized";;
  esac
fi
# Established-connection probe INSIDE the container's network namespace —
# a live TCP connection is a POSITIVE in-flight-work signal that catches long
# requests whose access-log line only appears at completion. Host-side ss cannot see
# kernel-NAT'd (non-proxied) connections, so this reads the namespace's own kernel
# table /proc/net/tcp{,6}: every path in ends there.
# ESTAB state = 01; local port matched against the container-side ports.
ESTAB=0
if [ -n "$CPORTS" ]; then
  if ! TCPRAW=$(docker exec "$CONTAINER" cat /proc/net/tcp /proc/net/tcp6 2>/dev/null); then
    verdict INDETERMINATE 5 "${EVIDENCE[@]}" "in-namespace connection probe failed (docker exec cat /proc/net/tcp) — cannot verify in-flight work; no action authorized"
  fi
  CPORTS_HEX=$(for cp in $CPORTS; do printf '%04X ' "$cp"; done)
  ESTAB=$(printf '%s\n' "$TCPRAW" | awk -v ports="$CPORTS_HEX" \
    'BEGIN{n=split(ports,P," "); for(i=1;i<=n;i++) want[P[i]]=1}
     $4=="01" {split($2,a,":"); if (a[2] in want) c++} END{print c+0}')
fi
# Explicit Redis queues (opt-in via ENV_DOCTOR_QUEUES) — configured means
# load-bearing: any probe failure is INDETERMINATE, never silently "empty".
QBUSY=""
if [ -n "${ENV_DOCTOR_QUEUES:-}" ]; then
  command -v redis-cli >/dev/null || verdict INDETERMINATE 5 "${EVIDENCE[@]}" "queues configured but redis-cli unavailable — cannot verify; no action authorized"
  for q in $ENV_DOCTOR_QUEUES; do
    n=$(redis-cli --no-auth-warning LLEN "$q" 2>/dev/null) || n=""
    case "$n" in ''|*[!0-9]*)
      verdict INDETERMINATE 5 "${EVIDENCE[@]}" "queue probe failed for '$q' (got: '${n:-no response}') — cannot verify; no action authorized";;
    esac
    [ "$n" -gt 0 ] && QBUSY="$QBUSY $q=$n"
  done
fi
if [ "$TRAFFIC" -gt 0 ] || [ "$ESTAB" -gt 0 ] || [ -n "$HBUSY" ] || [ -n "$QBUSY" ]; then
  verdict BLOCKED_BUSY 3 "${EVIDENCE[@]}" "busy: write_requests(${BUSY_WINDOW})=$TRAFFIC established_connections=$ESTAB health_work_counters:[${HBUSY:-none}] redis_queues:[${QBUSY:-none}] — another session's work may be in flight"
fi

verdict RESTART_OK 0 "${EVIDENCE[@]}" "clear: write_requests(${BUSY_WINDOW})=0 established_connections=0 counter_probe=$HPROBE(port=${HPORT:-n/a}, all=0) redis_queues:${QBUSY:-none-configured-or-empty}"
