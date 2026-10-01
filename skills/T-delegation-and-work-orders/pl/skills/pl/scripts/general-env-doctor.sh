#!/usr/bin/env bash
# general-env-doctor.sh — non-Docker environment checks and optional repairs.
# Docker start/restart lives in docker-env-doctor.sh; GPU checks in gpu-watch.sh.
#
# Usage:
#   general-env-doctor.sh [class ...] [--fix]
#     Classes: secrets, creds, connectivity, deps, workspace, drift (default: all).
#   general-env-doctor.sh secret <NAME>     env, then configured wrapper
#   general-env-doctor.sh host [<name>]    look up the configured roster
#   general-env-doctor.sh vm [<name>]      probe configured VM rows with ping + SSH
#
# Settings (all optional):
#   SNO_SECRETS_CMD: one executable path; invoked as "$SNO_SECRETS_CMD" command args.
#     It injects secrets and executes the command, preserving its exit status.
#     Put provider-specific options in that executable, not in this setting.
#   OPENAI_BASE_URL: OpenAI-compatible base URL; probes its /models resource.
#   SNO_ROSTER_FILE: TSV with name, address, kind, purpose, check columns.
#     kind=vm enables VM probes; address=UNKNOWN reports an unregistered address.
#     check=tcp:[host:]port, ping, or none. No roster is shipped with the skill.
# Unset settings, and tools or registries the project does not use (docker, rg, gh,
# npm, cargo), report a WARN "not applicable" and continue without a failure.
# Without --fix nothing is changed; the checks only read.
# --fix makes these changes, and only these:
#   creds:     reads GITHUB_TOKEN, NPM_TOKEN and CARGO_REGISTRY_TOKEN from the configured
#              secrets wrapper (SNO_SECRETS_CMD) and, for a dead or missing credential,
#              runs `gh auth login --with-token`, rewrites the _authToken line of
#              ~/.npmrc, or runs `cargo login`.
#   deps:      runs `uv sync` or `bun install` where a lock file is newer than its
#              .venv or node_modules.
#   workspace: removes a stale .git/index.lock (no live git process, older than 5 min).
# Exit: 0 = no FAIL (PASS/FIXED/WARN only), 3 = FAILs present, 2 = usage.
set -uo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

SECRETS_CMD="${SNO_SECRETS_CMD:-}"
ROSTER_FILE="${SNO_ROSTER_FILE:-}"
FIX=0; CLASSES=(); FAILS=0
say()   { printf '%s\n' "$*"; }
pass()  { say "[PASS] $*"; }
fixed() { say "[FIXED] $*"; }
warn()  { say "[WARN] $*"; }
fail()  { say "[FAIL] $*"; FAILS=$((FAILS+1)); }
tcp()   { timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

# ---------- secret lookup --------------------------------------------------

secret_value() {
  [ -n "$SECRETS_CMD" ] || return 1
  timeout 20 "$SECRETS_CMD" printenv -- "$1" 2>/dev/null
}

cmd_secret() {
  local q="${1:-}"
  [ -n "$q" ] || { say "usage: general-env-doctor.sh secret <NAME>"; exit 2; }
  if [[ $q =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [ -n "${!q:-}" ]; then
    pass "secret '$q' is already exported in this shell (value not shown)"
    return
  fi
  if [ -n "$SECRETS_CMD" ]; then
    local value
    if value=$(secret_value "$q") && [ -n "$value" ]; then
      pass "secret '$q' is available through the configured wrapper (value not shown)"
      return
    fi
  else
    warn "secrets: no secrets wrapper configured"
  fi
  [ -n "$SECRETS_CMD" ] || return 0
  fail "secret '$q' not found in the environment or configured wrapper"
}

# ---------- classes ---------------------------------------------------------
c_secrets() {
  [ -n "$SECRETS_CMD" ] || { warn "secrets: no secrets wrapper configured"; return; }
  if timeout 20 "$SECRETS_CMD" true >/dev/null 2>&1; then
    pass "secrets: configured wrapper runs successfully"
  else
    fail "secrets: configured wrapper failed — check SNO_SECRETS_CMD and its credentials"
  fi
}

c_creds() {
  # GitHub: no gh, or no login at all, means the project does not use it here.
  local tok=""
  command -v gh >/dev/null && tok=$(gh auth token 2>/dev/null)
  if [ -n "$tok" ] && [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $tok" https://api.github.com/user)" = "200" ]; then
    pass "creds: GitHub token live"
  elif [ "$FIX" -eq 1 ] && command -v gh >/dev/null && secret_value GITHUB_TOKEN 2>/dev/null | gh auth login --with-token 2>/dev/null; then
    fixed "creds: GitHub token restored from the configured secrets wrapper"
  elif ! command -v gh >/dev/null; then
    warn "creds: gh is not installed; GitHub token check not applicable"
  elif [ -z "$tok" ]; then
    warn "creds: gh is not logged in; GitHub token check not applicable (run: gh auth login)"
  else
    fail "creds: GitHub token dead — rerun with --fix (restores from the configured secrets wrapper GITHUB_TOKEN)"
  fi
  # Publishing credentials are checked only when this home has that registry configured.
  if [ -f "$HOME/.npmrc" ] && ! command -v npm >/dev/null; then
    warn "creds: npm is not installed; publish token check not applicable"
  elif [ -f "$HOME/.npmrc" ]; then
    if npm whoami >/dev/null 2>&1; then pass "creds: npm token live ($(npm whoami 2>/dev/null))"
    elif [ "$FIX" -eq 1 ]; then
      local nt; nt=$(secret_value NPM_TOKEN 2>/dev/null)
      if [ -n "$nt" ]; then
        grep -v '_authToken' "$HOME/.npmrc" > "$HOME/.npmrc.new" || true
        printf '//registry.npmjs.org/:_authToken=%s\n' "$nt" >> "$HOME/.npmrc.new" && mv "$HOME/.npmrc.new" "$HOME/.npmrc"
        npm whoami >/dev/null 2>&1 && fixed "creds: npm token restored from the configured secrets wrapper" || fail "creds: npm token restored but is still unusable — renew it before publishing"
      else fail "creds: npm token missing from the configured secrets wrapper — run npm login"; fi
    else fail "creds: npm token dead — rerun with --fix"; fi
  else warn "creds: npm registry not configured; skipping publish token check"; fi
  if [ -f "$HOME/.cargo/credentials.toml" ]; then
    if grep -q 'token *= *"cio' "$HOME/.cargo/credentials.toml" 2>/dev/null; then
      pass "creds: crates.io token present (liveness unverifiable by design — crates has no whoami endpoint)"
    elif [ "$FIX" -eq 1 ] && secret_value CARGO_REGISTRY_TOKEN 2>/dev/null | cargo login 2>/dev/null; then
      fixed "creds: crates.io token restored from the configured secrets wrapper"
    else
      fail "creds: crates.io token missing — rerun with --fix"
    fi
  else warn "creds: crates.io registry not configured; skipping publish token check"; fi
}

c_connectivity() {
  local endpoint="${OPENAI_BASE_URL:-}"
  [ -n "$endpoint" ] || { warn "connectivity: using the harness's own endpoint"; return; }
  if curl -sf -m 5 "${endpoint%/}/models" >/dev/null 2>&1; then
    pass "connectivity: configured OpenAI-compatible endpoint reachable"
  else
    fail "connectivity: configured endpoint probe failed — check OPENAI_BASE_URL and endpoint authentication"
  fi
}

cmd_vm() {
  local only="${1:-}" hit=0
  [ -n "$ROSTER_FILE" ] || { warn "vm: no roster configured"; return; }
  [ -f "$ROSTER_FILE" ] && [ -r "$ROSTER_FILE" ] || { fail "vm: cannot read SNO_ROSTER_FILE — set it to a readable TSV"; return; }
  while IFS=$'\t' read -r name addr kind purpose check; do
    case "$name" in ''|\#*) continue;; esac
    [ "$kind" = "vm" ] || continue
    [ -n "$only" ] && [ "$name" != "$only" ] && continue
    hit=1
    if [ "$addr" = "UNKNOWN" ]; then
      fail "vm: $name ($purpose) has no registered address — ask whoever owns the host, then fill $ROSTER_FILE; do NOT dispatch VM-dependent work until this probe passes"
      continue
    fi
    if ping -c1 -W2 "$addr" >/dev/null 2>&1; then
      if timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 "$addr" true 2>/dev/null; then
        pass "vm: $name ($addr) ping+ssh OK"
      else
        fail "vm: $name ($addr) pings but ssh refused — key/agent problem; fix before dispatching"
      fi
    else
      fail "vm: $name ($addr) unreachable — check VM power and network access; do not dispatch onto it"
    fi
  done < "$ROSTER_FILE"
  if [ "$hit" -eq 0 ]; then
    if [ -n "$only" ]; then fail "vm: '$only' not in registry $ROSTER_FILE — register it first"
    else warn "vm: no VMs registered in SNO_ROSTER_FILE"; fi
  fi
}

cmd_host() { # registry lookup so PLs query the table instead of asking the owner
  local only="${1:-}" hit=0
  [ -n "$ROSTER_FILE" ] || { warn "host: no roster configured"; return; }
  [ -f "$ROSTER_FILE" ] && [ -r "$ROSTER_FILE" ] || { fail "host: cannot read SNO_ROSTER_FILE — set it to a readable TSV"; return; }
  while IFS=$'\t' read -r name addr kind purpose check; do
    case "$name" in ''|\#*) continue;; esac
    [ -n "$only" ] && [ "$name" != "$only" ] && continue
    hit=1
    if [ -z "$only" ]; then printf '%-22s %-16s %-9s %s\n' "$name" "$addr" "$kind" "$purpose"; continue; fi
    say "name: $name"; say "address: $addr"; say "kind: $kind"; say "purpose: $purpose"; say "check: $check"
    case "$check" in
      tcp:*) local hp="${check#tcp:}" h
             case "$hp" in *:*) h="${hp%:*}";; *) h="$addr";; esac
             tcp "$h" "${hp##*:}" && pass "host: $name check ($check via $h) OK" || fail "host: $name check ($check via $h) FAILED";;
      ping)  ping -c1 -W2 "$addr" >/dev/null 2>&1 && pass "host: $name pings" || fail "host: $name does not ping";;
      *) say "(no automated check for this row)";;
    esac
  done < "$ROSTER_FILE"
  [ "$hit" -eq 0 ] && fail "host: '$only' not in registry $ROSTER_FILE — if it should exist, register it"
}

c_deps() {
  local root; root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  local lock dir
  while IFS= read -r lock; do
    dir=$(dirname "$lock")
    if [ -d "$dir/.venv" ] && [ "$lock" -nt "$dir/.venv" ]; then
      if [ "$FIX" -eq 1 ] && (cd "$dir" && uv sync >/dev/null 2>&1 && touch .venv); then fixed "deps: uv sync ($dir)"
      else fail "deps: $lock newer than its .venv — run: (cd $dir && uv sync && touch .venv)"; fi
    fi
  done < <(find "$root" -maxdepth 3 -name uv.lock -not -path '*/.venv/*' 2>/dev/null)
  while IFS= read -r lock; do
    dir=$(dirname "$lock")
    if [ -d "$dir/node_modules" ] && [ "$lock" -nt "$dir/node_modules" ]; then
      if [ "$FIX" -eq 1 ] && (cd "$dir" && bun install >/dev/null 2>&1 && touch node_modules); then fixed "deps: bun install ($dir)"
      else fail "deps: $lock newer than node_modules — run: (cd $dir && bun install && touch node_modules)"; fi
    fi
  done < <(find "$root" -maxdepth 3 \( -name 'bun.lock' -o -name 'bun.lockb' \) -not -path '*/node_modules/*' 2>/dev/null)
  local missing=() optional=() t
  for t in jq flock curl; do command -v "$t" >/dev/null || missing+=("$t"); done
  for t in rg docker; do command -v "$t" >/dev/null || optional+=("$t"); done
  if [ "${#missing[@]}" -eq 0 ]; then pass "deps: required CLI tools present (jq, flock, curl)"
  else
    fail "deps: missing tools: ${missing[*]} — install them using this system's package manager"
  fi
  [ "${#optional[@]}" -eq 0 ] || warn "deps: optional tools not installed: ${optional[*]} — not applicable unless the project uses them"
}

c_workspace() {
  local root; root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  if [ -f "$root/.git/index.lock" ]; then
    if ! pgrep -x git >/dev/null && [ -n "$(find "$root/.git/index.lock" -mmin +5 2>/dev/null)" ]; then
      if [ "$FIX" -eq 1 ]; then rm -f "$root/.git/index.lock" && fixed "workspace: removed stale git index.lock (no live git process, >5min old)"
      else fail "workspace: stale git index.lock (no live git process, >5min old) — run: rm $root/.git/index.lock"; fi
    else warn "workspace: git index.lock present but possibly live — re-check in a minute"; fi
  else pass "workspace: no stale git locks"; fi
  local scratch="${SNO_SCRATCH:-${TMPDIR:-/tmp}}"
  if [ -d "$scratch" ] && [ -w "$scratch" ]; then
    pass "workspace: scratch directory writable: $scratch"
    if mountpoint -q "$scratch" 2>/dev/null; then pass "workspace: scratch mount present: $scratch"; fi
  else fail "workspace: scratch directory is missing or not writable: $scratch — create it or set SNO_SCRATCH to a writable directory"; fi
  local du; du=$(df --output=pcent / "$scratch" 2>/dev/null | grep -o '[0-9]*' | sort -rn | head -1)
  [ "${du:-0}" -lt 90 ] && pass "workspace: disk usage ok (max ${du:-?}%)" || fail "workspace: a filesystem is at ${du}% — biggest offenders: $(du -xhs "$scratch" "$HOME/.cache" 2>/dev/null | tr '\n' ' ')"
}

c_drift() {
  local root; root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  if [ -f "$root/justfile" ]; then
    local jp published p
    jp=$(grep -oE 'localhost:[0-9]+' "$root/justfile" | grep -oE '[0-9]+' | sort -u)
    published=$(docker ps --format '{{.Ports}}' 2>/dev/null | grep -oE ':[0-9]+->' | grep -oE '[0-9]+' | sort -u)
    for p in $jp; do
      if printf '%s\n' "$published" | grep -qx "$p" || ss -Hltn "( sport = :$p )" 2>/dev/null | grep -q .; then
        pass "drift: justfile port $p has a live listener"
      else
        warn "drift: justfile references port $p but nothing publishes/listens on it — check docker port <container> before trusting the doc"
      fi
    done
  fi
}

# ---------- dispatch --------------------------------------------------------
case "${1:-}" in
  secret)  shift; cmd_secret "${1:-}";  exit $(( FAILS>0 ? 3 : 0 ));;
  vm)     shift; cmd_vm "${1:-}";     exit $(( FAILS>0 ? 3 : 0 ));;
  host)   shift; cmd_host "${1:-}";   exit $(( FAILS>0 ? 3 : 0 ));;
esac
for a in "$@"; do
  case "$a" in
    --fix) FIX=1;;
    secrets|creds|connectivity|deps|workspace|drift) CLASSES+=("$a");;
    *) echo "general-env-doctor: unknown argument '$a'" >&2; exit 2;;
  esac
done
[ "${#CLASSES[@]}" -eq 0 ] && CLASSES=(secrets creds connectivity deps workspace drift)
for c in "${CLASSES[@]}"; do "c_$c"; done
say "----"
if [ "$FAILS" -eq 0 ]; then say "environment OK (no FAIL)"; exit 0
else say "$FAILS FAIL item(s) — each line above carries its exact next command"; exit 3; fi
