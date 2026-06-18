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

test_forced_offline_mode_does_not_refresh_repositories() (
    # shellcheck disable=SC2329
    git() {
        fail "forced offline mode invoked git"
    }
    AI_WORKSPACE_OFFLINE_MODE=force refresh_offline_package_repositories /nonexistent
)

test_auto_offline_mode_refreshes_packaged_repositories() (
    package_root="$(mktemp -d)"
    mkdir -p "$package_root/repos/xworkspace-console/.git" "$package_root/repos/playbooks/.git"
    git_log="$(mktemp)"
    # shellcheck disable=SC2329
    curl() {
        return 0
    }
    # shellcheck disable=SC2329
    git() {
        printf '%s\n' "$*" >> "$git_log"
        if [ "${3:-}" = "symbolic-ref" ]; then
            printf 'main\n'
        fi
    }

    AI_WORKSPACE_OFFLINE_MODE=auto refresh_offline_package_repositories "$package_root"
    [ "$(grep -c 'fetch origin main' "$git_log")" -eq 2 ] || fail "packaged repositories were not fetched"
    [ "$(grep -c 'reset --hard origin/main' "$git_log")" -eq 2 ] || fail "packaged repositories were not updated"
    rm -rf "$package_root" "$git_log"
)

test_ubuntu_2604_offline_package_requires_npm() (
    package_root="$(mktemp -d)"
    mkdir -p "$package_root/packages/apt"
    if validate_offline_package_requirements "$package_root" "ubuntu 26.04 amd64" 2>/dev/null; then
        fail "Ubuntu 26.04 package without npm was accepted"
    fi
    touch "$package_root/packages/apt/npm_9.2.0_all.deb"
    validate_offline_package_requirements "$package_root" "ubuntu 26.04 amd64"
    validate_offline_package_requirements "$package_root" "debian 12 amd64"
    rm -rf "$package_root"
)

test_dynamic_parallel_limit_avoids_awk_reserved_names() (
    # shellcheck disable=SC2329
    online_cpu_count() { printf '4\n'; }
    # shellcheck disable=SC2329
    one_minute_load_average() { printf '1.2\n'; }
    [ "$(AI_WORKSPACE_MAX_PARALLEL_JOBS=auto dynamic_parallel_job_limit)" = "6" ] || fail "dynamic parallel limit was calculated incorrectly"
)

test_offline_installer_gets_scoped_git_config() (
    installer_root="$(mktemp -d)"
    mkdir -p "$installer_root/scripts"
    cat > "$installer_root/scripts/ai-workspace-offline-install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${GIT_CONFIG_COUNT:-}" = "1" ]
[ "${GIT_CONFIG_KEY_0:-}" = "safe.directory" ]
[ "${GIT_CONFIG_VALUE_0:-}" = "*" ]
EOF
    chmod +x "$installer_root/scripts/ai-workspace-offline-install.sh"
    # shellcheck disable=SC2329
    validate_offline_package_target() { :; }
    # shellcheck disable=SC2329
    id() {
        [ "${1:-}" = "-u" ] && printf '0\n'
    }
    run_offline_installer "$installer_root" "debian 13 amd64"
    rm -rf "$installer_root"
)

test_linux_root_defaults_to_ubuntu_home() (
    # shellcheck disable=SC2329
    id() {
        if [ "${1:-}" = "-u" ]; then
            printf '0\n'
        elif [ "${1:-}" = "-un" ]; then
            printf 'root\n'
        fi
    }
    # shellcheck disable=SC2329
    getent() {
        return 1
    }

    user="$(linux_default_console_user)"
    home="$(linux_default_console_home "$user")"
    [ "$user" = "ubuntu" ] || fail "root Linux default user was not ubuntu"
    [ "$home" = "/home/ubuntu" ] || fail "root Linux default home was not /home/ubuntu"
)

test_linux_non_root_uses_current_user_home() (
    # shellcheck disable=SC2329
    id() {
        if [ "${1:-}" = "-u" ]; then
            printf '501\n'
        elif [ "${1:-}" = "-un" ]; then
            printf 'shenlan\n'
        fi
    }
    # shellcheck disable=SC2329
    getent() {
        [ "${1:-}" = "passwd" ] && [ "${2:-}" = "shenlan" ] || return 1
        printf 'shenlan:x:501:20::/Users/shenlan:/bin/zsh\n'
    }

    user="$(linux_default_console_user)"
    home="$(linux_default_console_home "$user")"
    [ "$user" = "shenlan" ] || fail "non-root Linux default user was not current user"
    [ "$home" = "/Users/shenlan" ] || fail "non-root Linux default home did not come from passwd"
)

test_linux_identity_vars_can_be_overridden() (
    export XWORKSPACE_CONSOLE_USER=deploy
    export XWORKSPACE_CONSOLE_HOME=/srv/deploy
    user="$(linux_default_console_user)"
    home="$(linux_default_console_home "$user")"
    [ "$user" = "deploy" ] || fail "explicit console user was ignored"
    [ "$home" = "/srv/deploy" ] || fail "explicit console home was ignored"

    ANSIBLE_EXTRA_VARS=()
    append_linux_console_identity_vars "$user" "$home"
    printf '%s\n' "${ANSIBLE_EXTRA_VARS[@]}" | grep -q '^xworkspace_console_user=deploy$' || fail "console user extra var missing"
    printf '%s\n' "${ANSIBLE_EXTRA_VARS[@]}" | grep -q '^xworkspace_console_home=/srv/deploy$' || fail "console home extra var missing"
    printf '%s\n' "${ANSIBLE_EXTRA_VARS[@]}" | grep -q '^xworkspace_console_repo_dir=/srv/deploy/xworkspace-console$' || fail "console repo extra var missing"
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
test_forced_offline_mode_does_not_refresh_repositories
printf 'ok - forced offline mode does not refresh packaged repositories\n'
test_auto_offline_mode_refreshes_packaged_repositories
printf 'ok - auto offline mode refreshes packaged repositories\n'
test_ubuntu_2604_offline_package_requires_npm
printf 'ok - Ubuntu 26.04 offline package requires npm\n'
test_dynamic_parallel_limit_avoids_awk_reserved_names
printf 'ok - dynamic parallel limit is compatible with modern gawk\n'
test_offline_installer_gets_scoped_git_config
printf 'ok - offline installer receives scoped Git ownership compatibility\n'
test_linux_root_defaults_to_ubuntu_home
printf 'ok - Linux root deployment defaults to ubuntu home\n'
test_linux_non_root_uses_current_user_home
printf 'ok - Linux non-root deployment uses passwd home\n'
test_linux_identity_vars_can_be_overridden
printf 'ok - Linux deployment identity can be overridden\n'
