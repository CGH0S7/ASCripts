#!/usr/bin/env bash
set -euo pipefail

############################################
# agent-port.sh
# Backup / restore .claude and .codex config
# directories across servers.
############################################

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

backup() {
    local outdir="${1:-.}"
    local filter_user="${2:-}"
    local label="${filter_user:+$filter_user-}"
    local tarball
    tarball="$(realpath "$outdir")/agent-configs-${label}$(date +%Y%m%d-%H%M%S).tar.gz"
    local tmpdir
    tmpdir=$(mktemp -d /tmp/agent-port-bkp-XXXXXX)

    if [[ -n $filter_user ]]; then
        echo "==> Collecting .claude and .codex directories for user '$filter_user'..."
    else
        echo "==> Collecting .claude and .codex directories from all users..."
    fi

    local count=0
    while IFS=: read -r user _ uid _ _ homedir _; do
        # Filter by specific user if requested
        [[ -z $filter_user || $user == "$filter_user" ]] || continue
        # Only regular users (UID >= 1000), skip system/nobody
        [[ $uid -ge 1000 && $uid -lt 65534 ]] || continue
        [[ -d $homedir ]] || continue

        local userdir="$tmpdir/$user"
        local found=0

        if [[ -d "$homedir/.claude" ]]; then
            mkdir -p "$userdir"
            cp -a "$homedir/.claude" "$userdir/.claude"
            echo "    $user: .claude"
            found=1
        fi

        if [[ -d "$homedir/.codex" ]]; then
            mkdir -p "$userdir"
            cp -a "$homedir/.codex" "$userdir/.codex"
            echo "    $user: .codex"
            found=1
        fi

        if [[ $found -eq 1 ]]; then
            count=$((count + 1))
        fi
    done < <(getent passwd)

    if [[ $count -eq 0 ]]; then
        echo "==> No .claude or .codex directories found. Nothing to back up."
        rm -rf "$tmpdir"
        exit 0
    fi

    echo "==> Creating tarball: $tarball"
    tar -czf "$tarball" -C "$tmpdir" .

    rm -rf "$tmpdir"
    echo "==> Backup complete: $tarball ($count user(s))"
}

restore() {
    local tarball="$1"
    local target_user="${2:-}"

    tarball=$(realpath "$tarball")

    if [[ ! -f $tarball ]]; then
        echo "ERROR: Tarball not found: $tarball"
        exit 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d /tmp/agent-port-rst-XXXXXX)

    # ── Cross-user restore (-t) ─────────────────

    if [[ -n $target_user ]]; then
        # Verify single-user backup
        local tarball_users
        tarball_users=$(tar -tzf "$tarball" | cut -d/ -f2 | sort -u | grep -v '^\.$' | grep -v '^$')
        local user_count
        user_count=$(echo "$tarball_users" | wc -l)

        if [[ $user_count -ne 1 ]]; then
            echo "ERROR: -t requires a single-user backup, but tarball contains $user_count users."
            rm -rf "$tmpdir"
            exit 1
        fi

        if ! id "$target_user" &>/dev/null; then
            echo "ERROR: target user '$target_user' does not exist on this system."
            rm -rf "$tmpdir"
            exit 1
        fi

        local target_home
        target_home=$(eval echo "~$target_user")

        if [[ ! -d $target_home ]]; then
            echo "ERROR: home directory for '$target_user' not found ($target_home)"
            rm -rf "$tmpdir"
            exit 1
        fi

        echo "==> Extracting $tarball..."
        tar -xzf "$tarball" -C "$tmpdir"

        local src_user="$tarball_users"
        local src_userdir="$tmpdir/$src_user"

        echo "==> Restoring single-user backup ($src_user) to target user '$target_user'..."
        for cfg in .claude .codex; do
            if [[ -d "$src_userdir/$cfg" ]]; then
                rm -rf "$target_home/$cfg"
                cp -a "$src_userdir/$cfg" "$target_home/$cfg"
                chown -R "$target_user:$(id -gn "$target_user")" "$target_home/$cfg"
                echo "    $target_user: $cfg restored (from $src_user)"
            fi
        done

        rm -rf "$tmpdir"
        echo "==> Restore complete: 1 user(s) restored, 0 skipped"
        return
    fi

    # ── Normal restore (match source usernames) ──

    echo "==> Extracting $tarball..."
    tar -xzf "$tarball" -C "$tmpdir"

    local ok=0 skip=0
    for userdir in "$tmpdir"/*/; do
        local user
        user=$(basename "$userdir")

        if ! id "$user" &>/dev/null; then
            echo "    SKIP: user '$user' does not exist on this system"
            skip=$((skip + 1))
            continue
        fi

        local homedir
        homedir=$(eval echo "~$user")

        if [[ ! -d $homedir ]]; then
            echo "    SKIP: home directory for '$user' not found ($homedir)"
            skip=$((skip + 1))
            continue
        fi

        for cfg in .claude .codex; do
            if [[ -d "$userdir/$cfg" ]]; then
                rm -rf "$homedir/$cfg"
                cp -a "$userdir/$cfg" "$homedir/$cfg"
                chown -R "$user:$(id -gn "$user")" "$homedir/$cfg"
                echo "    $user: $cfg restored"
            fi
        done
        ok=$((ok + 1))
    done

    rm -rf "$tmpdir"
    echo "==> Restore complete: $ok user(s) restored, $skip user(s) skipped"
}

# ── Main ──────────────────────────────────────

usage() {
    echo "Usage:"
    echo "  Backup all users:   $0"
    echo "  Backup one user:    $0 -u <username>"
    echo "  Restore:            $0 <tarball>"
    echo "  Restore to another: $0 -t <target_user> <tarball>"
}

backup_user=""
restore_target=""

while getopts "u:t:" opt; do
    case $opt in
        u) backup_user="$OPTARG" ;;
        t) restore_target="$OPTARG" ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [[ -n $backup_user && -n $restore_target ]]; then
    echo "ERROR: -u and -t cannot be used together."
    exit 1
fi

if [[ $# -eq 0 ]]; then
    if [[ -n $restore_target ]]; then
        echo "ERROR: -t requires a tarball argument."
        exit 1
    fi
    backup "." "$backup_user"
else
    if [[ -n $backup_user ]]; then
        echo "ERROR: -u is only valid in backup mode, not with a tarball argument."
        exit 1
    fi
    restore "$1" "$restore_target"
fi
