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
BEGIN {
    print "| Host | Open Ports |"
    print "|---|---|"
}
/^Nmap scan report for / {
    if (host != "") {
        if (ports == "") ports = "None"
        print "| " host " | " ports " |"
    }

    host = $NF
    gsub(/[()]/, "", host)
    ports = ""
    next
}

/^[0-9]+\/(tcp|udp)[[:space:]]+open[[:space:]]/ {
    if (ports == "")
        ports = $1
    else
        ports = ports ", " $1
}

END {
    if (host != "") {
        if (ports == "") ports = "None"
        print "| " host " | " ports " |"
    }
}
' "$INPUT_FILE" > "$OUTPUT_FILE"

echo "[+] Markdown summary written to: $OUTPUT_FILE"
cat "$OUTPUT_FILE"
