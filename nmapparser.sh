#!/usr/bin/env bash
# Usage:
#   ./nmapparser.sh nmap.txt
#   ./nmapparser.sh nmap.txt summary.md

set -euo pipefail

INPUT_FILE="${1:-}"
OUTPUT_FILE="${2:-nmap_summary.md}"

if [[ -z "$INPUT_FILE" ]]; then
    echo "Usage: $0 <nmap-output.txt> [output.md]" >&2
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "[!] File not found: $INPUT_FILE" >&2
    exit 1
fi

awk '
function save_host() {
    if (host == "") {
        return
    }

    host_count++
    hosts[host_count] = host
    ports_only[host_count] = (current_ports_only == "" ? "None" : current_ports_only)
    ports_protocol[host_count] = (current_ports_protocol == "" ? "None" : current_ports_protocol)
}

/^Nmap scan report for / {
    save_host()

    host = $NF
    gsub(/[()]/, "", host)

    current_ports_only = ""
    current_ports_protocol = ""
    next
}

/^[0-9]+\/(tcp|udp)[[:space:]]+open[[:space:]]/ {
    split($1, port_parts, "/")
    port_number = port_parts[1]

    if (current_ports_only == "") {
        current_ports_only = port_number
        current_ports_protocol = $1
    } else {
        current_ports_only = current_ports_only ", " port_number
        current_ports_protocol = current_ports_protocol ", " $1
    }
}

END {
    save_host()

    print "## Open ports"
    print ""
    print "| Host | Open Ports |"
    print "|---|---|"

    for (i = 1; i <= host_count; i++) {
        print "| " hosts[i] " | " ports_only[i] " |"
    }

    print ""
    print "## Open ports with protocol"
    print ""
    print "| Host | Open Ports |"
    print "|---|---|"

    for (i = 1; i <= host_count; i++) {
        print "| " hosts[i] " | " ports_protocol[i] " |"
    }
}
' "$INPUT_FILE" > "$OUTPUT_FILE"

echo "[+] Markdown summary written to: $OUTPUT_FILE"
cat "$OUTPUT_FILE"
