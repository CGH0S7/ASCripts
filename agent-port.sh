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
    local tarball
    tarball="$(realpath "$outdir")/agent-configs-$(date +%Y%m%d-%H%M%S).tar.gz"
    local tmpdir
    tmpdir=$(mktemp -d /tmp/agent-port-bkp-XXXXXX)

    echo "==> Collecting .claude and .codex directories from all users..."

    local count=0
    while IFS=: read -r user _ uid _ _ homedir _; do
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
    local tarball
    tarball=$(realpath "$1")

    if [[ ! -f $tarball ]]; then
        echo "ERROR: Tarball not found: $tarball"
        exit 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d /tmp/agent-port-rst-XXXXXX)

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

if [[ $# -eq 0 ]]; then
    echo "Usage:"
    echo "  Backup:  $0"
    echo "  Restore: $0 <tarball>"
    echo ""
    # Default: backup to current directory
    backup "."
else
    restore "$1"
fi
