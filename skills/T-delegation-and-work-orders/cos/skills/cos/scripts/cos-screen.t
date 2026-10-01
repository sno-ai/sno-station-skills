#!/usr/bin/env bash
# Real tmux on a private server; `sno` (seat list) and `orca` (the desktop app's CLI)
# are the only fakes, because both are external programs a test cannot start.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
screen="${COS_SCREEN_UNDER_TEST:-$script_dir/cos-screen.sh}"
root="$(mktemp -d)"
trap 'env -u TMUX TMUX_TMPDIR="$root/tmux" tmux kill-server >/dev/null 2>&1 || true; rm -r -- "$root"' EXIT
mkdir -p "$root/bin" "$root/tmux"
export TMUX_TMPDIR="$root/tmux" SNO_PL_REGISTRY="$root/registry.tsv" PATH="$root/bin:$PATH"
unset TMUX

cat >"$root/bin/sno" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' \
  '{"address":"pl.tmuxrepo@h","channel":"tmux","handle":"tmux-abc123:cosscreen","state":"live"}' \
  '{"address":"pl.orcarepo@h","channel":"orca","handle":"term_fake","state":"live"}'
EOF
# Stream mode (no --screen) returns repaint fragments, as the real Orca does.
cat >"$root/bin/orca" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"--screen"* ]] || { echo '{"ok":true,"result":{"terminal":{"tail":["cclclecleaclear"]}}}'; exit 0; }
[[ "$*" == *"term_fake"* ]] || { echo '{"ok":false,"error":{"code":"terminal_handle_stale"}}'; exit 1; }
echo '{"ok":true,"result":{"terminal":{"tail":["PL is waiting on review","",""]}}}'
EOF
chmod +x "$root/bin/sno" "$root/bin/orca"

printf 'home_repo\tlane\treach_address\theartbeat_name\truntime\towning_cos\tstate\tnote\n' >"$SNO_PL_REGISTRY"
printf 'orcarepo\tall\tpl.orcarepo@h\tx\tcodex\tcos/x\tRUN\t-\n' >>"$SNO_PL_REGISTRY"

tmux new-session -d -s cosscreen "printf 'TMUX-SCREEN-MARKER\n'; sleep 60"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    tmux capture-pane -p -t =cosscreen: | grep -q TMUX-SCREEN-MARKER && break
    sleep 0.3
done

printf 'TAP version 13\n'

out="$(bash "$screen" pl.tmuxrepo@h)"
if grep -q 'TMUX-SCREEN-MARKER' <<<"$out"; then
    printf 'ok 1 - tmux seat prints the live pane\n'
else
    printf 'not ok 1 - tmux seat prints the live pane\n# %s\n' "$out"; exit 1
fi

out="$(bash "$screen" orcarepo)"
if grep -q 'PL is waiting on review' <<<"$out" && ! grep -q cclclecleaclear <<<"$out"; then
    printf 'ok 2 - repo name resolves to the Orca seat and reads the rendered screen\n'
else
    printf 'not ok 2 - Orca screen read\n# %s\n' "$out"; exit 1
fi

rc=0
out="$(bash "$screen" no-such-repo)" || rc=$?
if [[ "$rc" == 3 ]] && grep -q '^NO WINDOW' <<<"$out"; then
    printf 'ok 3 - no window is reported as NO WINDOW with exit 3\n'
else
    printf 'not ok 3 - no window (rc=%s)\n# %s\n' "$rc" "$out"; exit 1
fi
printf '1..3\n'
