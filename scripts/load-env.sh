# Sourced by release scripts: exports BASHCUT_* keys from the repository's .env (git-ignored) without executing it.
# Values already in the environment win over the file. Account details (team ID, Apple ID, passwords) live only
# there; see .env.example.
#     source scripts/load-env.sh
#     require_env BASHCUT_TEAM_ID BASHCUT_APPLE_ID
env_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env"
if [[ -f "$env_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(BASHCUT_[A-Z0-9_]+)=(.*)$ ]] || continue
        key="${BASH_REMATCH[2]}"
        value="${BASH_REMATCH[3]%$'\r'}"
        if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi
        [[ -n "${!key:-}" ]] || export "$key=$value"
    done <"$env_file"
fi

require_env() {
    local key missing=()
    for key in "$@"; do
        [[ -n "${!key:-}" ]] || missing+=("$key")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "error: set ${missing[*]} in $env_file (see .env.example)" >&2
        exit 1
    fi
}
