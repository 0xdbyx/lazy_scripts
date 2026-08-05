#!/usr/bin/env bash

# Usage:
#   ./nmapparse.sh nmap.txt
#   ./nmapparse.sh nmap.txt summary.md

set -euo pipefail

INPUT_FILE="${1:-}"
OUTPUT_FILE="${2:-nmap_summary.md}"

if [[ -z "$INPUT_FILE" ]]; then
    echo "Usage: $0 <nmap-output.txt> [output.md]"
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "[!] File not found: $INPUT_FILE"
    exit 1
fi

awk '
BEGIN {
    print "| IP | Open Ports |"
    print "|---|---|"
}

/^Nmap scan report for / {
    if (ip != "") {
        if (ports == "") ports = "None"
        print "| " ip " | " ports " |"
    }

    ip = $NF
    gsub(/[()]/, "", ip)
    ports = ""
    next
}

/^[0-9]+\/(tcp|udp)[[:space:]]+open[[:space:]]/ {
    split($1, p, "/")

    if (ports == "")
        ports = p[1]
    else
        ports = ports ", " p[1]
}

END {
    if (ip != "") {
        if (ports == "") ports = "None"
        print "| " ip " | " ports " |"
    }
}
' "$INPUT_FILE" > "$OUTPUT_FILE"

echo "[+] Markdown summary written to: $OUTPUT_FILE"
cat "$OUTPUT_FILE"
