# Work acceptance reminders

Layer 1 is in Reach: `sno reach reply --state completed` and `failed` refuse a work item until
its report chain contains `accepted`. Send `reply --state accepted` first, do the work, then close
the original card with exactly one `completed` or `failed`.

Layer 2 supplies context before a turn. It reminds; it never denies a tool. The launcher supplies
the seat as `SNO_REACH_ADDR` and the store as `SNO_REACH_ROOT`; do not infer a seat from a process
name or a project. `sno reach remind` prints one line per seen, unaccepted work item and nothing
otherwise, under one 5-second deadline. It marks nothing and accepts nothing for the agent.

```sh
sno reach remind --as "$SNO_REACH_ADDR"
```

Reach installs this hook itself where its harness supports it; the entries below are the manual
form. Enabling a hook is a separate action from deploying this skill.

## Claude Code

Merge into `.claude/settings.json` (or the user's settings). JSON is produced only when a reminder exists.

```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "text=$(sno reach remind --as \"$SNO_REACH_ADDR\" 2>/dev/null) || exit 0; [ -n \"$text\" ] || exit 0; jq -nc --arg text \"$text\" '{hookSpecificOutput:{hookEventName:\"UserPromptSubmit\",additionalContext:$text}}' || true",
        "timeout": 10
      }]
    }]
  }
}
```

## Codex

The same entry goes into `.codex/hooks.json` (or `~/.codex/hooks.json`) for a runtime with the
hooks layer enabled. Preserve existing hooks and their trust settings.

## Hermes (the Hermes Agent CLI)

Its shell-hook bridge splits the command into arguments, so `bash -c` is explicit:

```yaml
hooks:
  pre_llm_call:
    - command: >-
        bash -c 'text=$(sno reach remind --as "$SNO_REACH_ADDR" 2>/dev/null) || exit 0; [ -n "$text" ] || exit 0; jq -nc --arg text "$text" "{context:\$text}" || true'
      timeout: 10
```

Other harnesses with a Claude- or Codex-style hooks file use the matching entry above; a harness
without a hooks layer stays under Layer 1 only.

A synthetic hook call proves the adapter, not that a live agent acted on a work order. Live
adoption is proved only when the receiver reports accepted on its first turn with no acceptance
instruction in the order body, and a failing reminder must leave each live turn able to complete.
