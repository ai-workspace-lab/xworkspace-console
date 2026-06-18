#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="$SCRIPT_DIR/../scripts/setup-ai-workspace-all-in-one.sh"

export AI_WORKSPACE_BOOTSTRAP_LIB_ONLY=true
# shellcheck source=/dev/null
source "$BOOTSTRAP"

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

test_root_does_not_require_sudo() (
    # shellcheck disable=SC2329
    id() {
        [ "${1:-}" = "-u" ] && printf '0\n'
    }
    # shellcheck disable=SC2329
    command() {
        if [ "${1:-}" = "-v" ] && [ "${2:-}" = "sudo" ]; then
            return 1
        fi
        builtin command "$@"
    }
    probe_file="$(mktemp)"
    # The positional parameter is intentionally expanded by the child shell.
    # shellcheck disable=SC2016
    run_as_root sh -c 'printf root > "$1"' sh "$probe_file"
    [ "$(cat "$probe_file")" = "root" ] || fail "root command was not executed directly"
    rm -f "$probe_file"
)

test_non_root_uses_sudo() (
    # shellcheck disable=SC2329
    id() {
        [ "${1:-}" = "-u" ] && printf '1000\n'
    }
    # shellcheck disable=SC2329
    sudo() {
        printf '%s\n' "$*" > "$sudo_log"
    }
    # shellcheck disable=SC2329
    command() {
        if [ "${1:-}" = "-v" ] && [ "${2:-}" = "sudo" ]; then
            return 0
        fi
        builtin command "$@"
    }
    sudo_log="$(mktemp)"
    run_as_root apt-get update -y
    [ "$(cat "$sudo_log")" = "apt-get update -y" ] || fail "non-root command did not use sudo"
    rm -f "$sudo_log"
)

test_non_root_without_sudo_fails_cleanly() (
    # shellcheck disable=SC2329
    id() {
        [ "${1:-}" = "-u" ] && printf '1000\n'
    }
    # shellcheck disable=SC2329
    command() {
        if [ "${1:-}" = "-v" ] && [ "${2:-}" = "sudo" ]; then
            return 1
        fi
        builtin command "$@"
    }
    run_as_root apt-get update -y
)

test_root_does_not_require_sudo
printf 'ok - root execution does not require sudo\n'
test_non_root_uses_sudo
printf 'ok - non-root execution uses sudo\n'
set +e
privilege_error="$(test_non_root_without_sudo_fails_cleanly 2>&1)"
privilege_status=$?
set -e
[ "$privilege_status" -ne 0 ] || fail "non-root execution without sudo unexpectedly succeeded"
printf '%s' "$privilege_error" | grep -q "Root privileges are required" || fail "missing sudo error was not actionable"
printf 'ok - missing sudo reports a privilege error\n'
