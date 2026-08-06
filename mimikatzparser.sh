#!/bin/bash

# I am too lazy to scroll through the Mimikatz output.
# Place the output in mimikatz.log, then run: ./mimikatzparser.sh

LOGFILE="mimikatz.log"

USERS_FILE="usernames.txt"
NTLM_FILE="ntlm_hashes.txt"
PASS_FILE="passwords.txt"

USER_NTLM_FILE="creds_user_ntlm.txt"
USER_PASS_FILE="creds_user_pass.txt"

if [[ ! -f "$LOGFILE" ]]; then
    echo "[!] File not found: $LOGFILE" >&2
    exit 1
fi

# Restrict generated credential files to the current user.
umask 077

# Temporary files
TMP_USERS=$(mktemp)
TMP_NTLM=$(mktemp)
TMP_PASS=$(mktemp)
TMP_USER_NTLM=$(mktemp)
TMP_USER_PASS=$(mktemp)

cleanup() {
    rm -f "$TMP_USERS" "$TMP_NTLM" "$TMP_PASS" \
        "$TMP_USER_NTLM" "$TMP_USER_PASS"
}
trap cleanup EXIT INT TERM

current_user=""

while IFS= read -r line; do

    # Reset current user at the start of a new logon block
    if [[ "$line" =~ Authentication[[:space:]]+Id ]]; then
        current_user=""
        continue
    fi

    # Capture username (User OR Username, optional leading '*', any spaces)
    if [[ "$line" =~ ^[[:space:]]*\*?[[:space:]]*(User|Username)[[:space:]]*:[[:space:]]*(.+) ]]; then
        current_user="${BASH_REMATCH[2]}"
        current_user="$(echo "$current_user" | tr -d ' \t\r')"

        if [[ -n "$current_user" && "$current_user" != "(null)" ]]; then
            echo "$current_user" >> "$TMP_USERS"
        fi
        continue
    fi

    # Capture NTLM hash (NTLM OR Hash NTLM, optional leading '*', any spaces)
    if [[ "$line" =~ ^[[:space:]]*\*?[[:space:]]*(Hash[[:space:]]+)?NTLM[[:space:]]*:[[:space:]]*([a-fA-F0-9]{32}) ]]; then
        ntlm="${BASH_REMATCH[2]}"
        echo "$ntlm" >> "$TMP_NTLM"

        if [[ -n "$current_user" ]]; then
            echo "$current_user:$ntlm" >> "$TMP_USER_NTLM"
        fi
        continue
    fi

    # Capture cleartext password (ignore nulls)
    if [[ "$line" =~ Password[[:space:]]*:[[:space:]]*(.+) ]]; then
        pass="${BASH_REMATCH[1]}"
        pass="$(echo "$pass" | tr -d ' \t\r')"

        if [[ -n "$pass" && "$pass" != "(null)" && "$pass" != "null" ]]; then
            echo "$pass" >> "$TMP_PASS"

            if [[ -n "$current_user" ]]; then
                echo "$current_user:$pass" >> "$TMP_USER_PASS"
            fi
        fi
        continue
    fi

done < "$LOGFILE"

# Deduplicate and save
sort -u "$TMP_USERS" > "$USERS_FILE"
sort -u "$TMP_NTLM" > "$NTLM_FILE"
sort -u "$TMP_PASS" > "$PASS_FILE"
sort -u "$TMP_USER_NTLM" > "$USER_NTLM_FILE"
sort -u "$TMP_USER_PASS" > "$USER_PASS_FILE"

echo "[+] Unique usernames saved to $USERS_FILE"
echo "[+] Unique NTLM hashes saved to $NTLM_FILE"
echo "[+] Unique passwords saved to $PASS_FILE"
echo "[+] Username:NTLM pairs saved to $USER_NTLM_FILE"
echo "[+] Username:Password pairs saved to $USER_PASS_FILE"
