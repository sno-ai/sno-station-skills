#!/usr/bin/env bash
# Sourced library: preserve the caller's shell options.
# Flat TOML: [models], bare role keys, single/double quoted values, inline comments.
sno_model() {
    local role="${1:-}" file="${XDG_CONFIG_HOME:-$HOME/.config}/sno/models.toml"
    [[ "$role" =~ ^[a-z][a-z0-9_-]*$ ]] || {
        printf 'sno_model: expected a role name\n' >&2
        return 2
    }
    [[ -f "$file" ]] || return 0
    awk -v role="$role" '
        /^[[:space:]]*\[/ {
            models = ($0 ~ /^[[:space:]]*\[models\][[:space:]]*(#.*)?$/)
            next
        }
        models && $0 ~ "^[[:space:]]*" role "[[:space:]]*=" {
            value = $0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            quote = substr(value, 1, 1)
            if (quote != "\"" && quote != sprintf("%c", 39)) exit 2
            value = substr(value, 2)
            end = index(value, quote)
            if (!end || substr(value, end + 1) !~ /^[[:space:]]*(#.*)?$/) exit 2
            value = substr(value, 1, end - 1)
            if (length(value)) print value
            exit
        }
    ' "$file" || {
        printf 'sno_model: cannot read role %s from %s; check its quoted value\n' "$role" "$file" >&2
        return 2
    }
}

# Display helper only; callers build argument arrays to preserve word boundaries.
sno_model_flag() {
    local model
    [[ $# -eq 2 && -n "$2" ]] || return 2
    model="$(sno_model "$1")" || return "$?"
    [[ -z "$model" ]] || printf '%s %s\n' "$2" "$model"
}
