#!/usr/bin/env bash
# pspy_buddy.sh
#
# pspy may show only part of a command:
#   tar -zxf /tmp/backup.tar.gz *
#
# Logs may reveal the missing context:
#   cd /opt/admin && tar -zxf /tmp/backup.tar.gz *
#
# For a known log, a direct search may be enough:
#   grep -nF -- 'tar -zxf /tmp/backup.tar.gz *' /var/log/syslog
#
# Usage: ./pspy_buddy.sh "tar -zxf /tmp/backup.tar.gz *"

SEARCH="${1:-}"
if [[ -z "$SEARCH" ]]; then
    echo "Usage: $0 <search_term>" >&2
    echo "Example: sudo $0 'tar -zxf /tmp/backup.tar.gz'" >&2
    exit 1
fi

echo "[*] Searching for: $SEARCH"
echo "[*] Searching logs and common system locations. This may take some time."
echo "=================================================="

check() {
    local location
    local matches

    # Loop through all files expanded from wildcards.
    for location in "$@"; do
        [[ -e "$location" ]] || continue
        if [[ -f "$location" && "$location" == *.gz ]]; then
            # Compressed logs.
            matches=$(zgrep -HnF -- "$SEARCH" "$location" 2>/dev/null || true)

        elif [[ -d "$location" ]]; then
            # Directories, recursively.
            matches=$(grep -rInHIF -- "$SEARCH" "$location" 2>/dev/null || true)

        else
            # Normal files.
            matches=$(grep -HnIF -- "$SEARCH" "$location" 2>/dev/null || true)
        fi
        if [[ -n "$matches" ]]; then
            echo "[+] FOUND in $location"
            echo "$matches" | sed 's/^/    /'
            echo
        else
            echo "[-] Not found in $location"
        fi
    done
}

# System logs.
check /var/log/syslog*
check /var/log/auth.log*
check /var/log/daemon.log*
check /var/log/kern.log*
check /var/log/messages*
check /var/log/secure*

# Systemd journal.
if command -v journalctl >/dev/null 2>&1; then
    echo "[*] Checking journalctl"

    JOURNAL_MATCHES=$(
        journalctl --no-pager 2>/dev/null |
            grep -nF -- "$SEARCH" || true
    )

    if [[ -n "$JOURNAL_MATCHES" ]]; then
        echo "[+] FOUND in journalctl"
        echo "$JOURNAL_MATCHES" | sed 's/^/    /'
    else
        echo "[-] Not found in journalctl"
    fi

    echo
fi

# Cron jobs.
check /etc/crontab
check /etc/cron*
check /var/spool/cron*

# Systemd services and timers.
check /etc/systemd*
check /lib/systemd*
check /usr/lib/systemd*

# Common script locations.
check /usr/local/bin
check /usr/local/sbin
check /usr/bin
check /opt
check /root
check /home
check /tmp
check /var/backups

echo "=================================================="
echo "[*] Search complete"
