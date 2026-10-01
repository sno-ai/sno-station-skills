#!/usr/bin/env bash
# Exercise optional site settings through the public command only.
set -Eeuo pipefail

scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(mktemp -d)"
trap 'rm -r -- "$root"' EXIT
mkdir -p "$root/home" "$root/bin"
export HOME="$root/home"
unset SNO_SECRETS_CMD OPENAI_BASE_URL OPENAI_API_KEY SNO_ROSTER_FILE

bash "$scripts_dir/general-env-doctor.sh" secrets connectivity >"$root/out" 2>"$root/err"
grep -Fxq '[WARN] secrets: no secrets wrapper configured' "$root/out"
grep -Fxq "[WARN] connectivity: using the harness's own endpoint" "$root/out"
grep -Fxq 'environment OK (no FAIL)' "$root/out"
[[ ! -s "$root/err" ]]
printf 'ok 1 - unset site settings do not probe private services or fail\n'

for feature in host vm; do
    bash "$scripts_dir/general-env-doctor.sh" "$feature" >"$root/out" 2>"$root/err"
    grep -Fxq "[WARN] $feature: no roster configured" "$root/out"
    [[ ! -s "$root/err" ]]
done
printf 'ok 2 - roster features explain missing configuration\n'

bash "$scripts_dir/general-env-doctor.sh" secret EXAMPLE_TOKEN >"$root/out" 2>"$root/err"
grep -Fxq '[WARN] secrets: no secrets wrapper configured' "$root/out"
[[ ! -s "$root/err" ]]

cat >"$root/example-secrets wrapper" <<'SH'
#!/usr/bin/env bash
export EXAMPLE_TOKEN=fixture-secret-value GITHUB_TOKEN=fixture-github
export NPM_TOKEN=fixture-npm CARGO_REGISTRY_TOKEN=fixture-cargo
exec "$@"
SH
chmod +x "$root/example-secrets wrapper"
export SNO_SECRETS_CMD="$root/example-secrets wrapper"
bash "$scripts_dir/general-env-doctor.sh" secrets >"$root/out"
grep -Fxq '[PASS] secrets: configured wrapper runs successfully' "$root/out"
bash "$scripts_dir/general-env-doctor.sh" secret EXAMPLE_TOKEN >"$root/out"
grep -Fxq "[PASS] secret 'EXAMPLE_TOKEN' is available through the configured wrapper (value not shown)" "$root/out"
! grep -Fq 'fixture-secret-value' "$root/out"
rc=0
bash "$scripts_dir/general-env-doctor.sh" secret ABSENT_TOKEN >"$root/out" || rc=$?
[[ "$rc" == 3 ]]
grep -Fxq "[FAIL] secret 'ABSENT_TOKEN' not found in the environment or configured wrapper" "$root/out"
rc=0
bash "$scripts_dir/general-env-doctor.sh" secret OPENAI_API_KEY >"$root/out" || rc=$?
[[ "$rc" == 3 ]]
grep -Fxq "[FAIL] secret 'OPENAI_API_KEY' not found in the environment or configured wrapper" "$root/out"
printf 'ok 3 - a wrapper path with spaces provides secrets without printing values\n'

export SNO_SECRETS_CMD="$root/missing-wrapper"
rc=0
bash "$scripts_dir/general-env-doctor.sh" secrets >"$root/out" 2>"$root/err" || rc=$?
[[ "$rc" == 3 ]]
grep -Fxq '[FAIL] secrets: configured wrapper failed — check SNO_SECRETS_CMD and its credentials' "$root/out"
printf 'ok 4 - broken explicit configuration fails\n'

printf 'host-a\texample.invalid\tinfra\tfixture service\tnone\nhost-b\tUNKNOWN\tvm\tfixture guest\tnone\n' >"$root/roster.tsv"
export SNO_ROSTER_FILE="$root/roster.tsv"
bash "$scripts_dir/general-env-doctor.sh" host host-a >"$root/out"
grep -Fxq 'address: example.invalid' "$root/out"
grep -Fxq 'purpose: fixture service' "$root/out"
rc=0
bash "$scripts_dir/general-env-doctor.sh" vm host-b >"$root/out" || rc=$?
[[ "$rc" == 3 ]]
grep -Fq 'has no registered address' "$root/out"
for roster in "$root/missing.tsv" "$root"; do
    for feature in host vm; do
        rc=0
        SNO_ROSTER_FILE="$roster" bash "$scripts_dir/general-env-doctor.sh" "$feature" >"$root/out" 2>"$root/err" || rc=$?
        [[ "$rc" == 3 ]]
        grep -Fq 'cannot read SNO_ROSTER_FILE' "$root/out"
        [[ ! -s "$root/err" ]]
    done
done
printf 'ok 5 - roster lookup uses the supplied file and rejects unusable entries\n'

cat >"$root/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CURL_ARGS_FILE"
exit "${CURL_RESULT:-0}"
SH
chmod +x "$root/bin/curl"
export PATH="$root/bin:$PATH" CURL_ARGS_FILE="$root/curl.args"
export OPENAI_BASE_URL='http://localhost:0/'
bash "$scripts_dir/general-env-doctor.sh" connectivity >"$root/out"
grep -Fxq 'http://localhost:0/models' "$root/curl.args"
grep -Fxq '[PASS] connectivity: configured OpenAI-compatible endpoint reachable' "$root/out"
rc=0
CURL_RESULT=7 bash "$scripts_dir/general-env-doctor.sh" connectivity >"$root/out" || rc=$?
[[ "$rc" == 3 ]]
grep -Fxq '[FAIL] connectivity: configured endpoint probe failed — check OPENAI_BASE_URL and endpoint authentication' "$root/out"
printf 'ok 6 - the configured endpoint is probed and a failed probe is reported\n'

cat >"$root/bin/gh" <<'SH'
#!/usr/bin/env bash
[[ "$*" == 'auth login --with-token' ]] || exit 1
cat >"$HOME/github-token"
SH
cat >"$root/bin/npm" <<'SH'
#!/usr/bin/env bash
grep -Fxq '//registry.npmjs.org/:_authToken=fixture-npm' "$HOME/.npmrc" || exit 1
printf '%s\n' 'fixture-user'
SH
cat >"$root/bin/cargo" <<'SH'
#!/usr/bin/env bash
[[ "$1" == login ]] || exit 1
cat >"$HOME/cargo-token"
SH
chmod +x "$root/bin/gh" "$root/bin/npm" "$root/bin/cargo"
export SNO_SECRETS_CMD="$root/example-secrets wrapper"
bash "$scripts_dir/general-env-doctor.sh" creds >"$root/out"
grep -Fxq '[WARN] creds: gh is not logged in; GitHub token check not applicable (run: gh auth login)' "$root/out"
grep -Fxq 'environment OK (no FAIL)' "$root/out"
grep -Fxq '[WARN] creds: npm registry not configured; skipping publish token check' "$root/out"
grep -Fxq '[WARN] creds: crates.io registry not configured; skipping publish token check' "$root/out"
printf 'ok 7 - an unused GitHub login and unconfigured publishing registries are skipped without failing\n'
: > "$HOME/.npmrc"
mkdir -p "$HOME/.cargo"
: > "$HOME/.cargo/credentials.toml"
bash "$scripts_dir/general-env-doctor.sh" creds --fix >"$root/out" 2>"$root/err"
grep -Fxq 'fixture-github' "$HOME/github-token"
grep -Fxq '//registry.npmjs.org/:_authToken=fixture-npm' "$HOME/.npmrc"
grep -Fxq 'fixture-cargo' "$HOME/cargo-token"
grep -Fxq 'environment OK (no FAIL)' "$root/out"
! grep -Eq 'fixture-(github|npm|cargo)' "$root/out"
[[ ! -s "$root/err" ]]
printf 'ok 8 - configured credential repairs persist the supplied tokens\n1..8\n'
