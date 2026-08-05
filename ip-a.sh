#!/bin/bash

# Bsically `ip a` on linux when there is no `ip` command available

ip_to_int() {
    local IFS=.
    local a b c d
    read -r a b c d <<< "$1"
    echo $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

le_hex_to_int() {
    local h="$1"
    echo $(( 16#${h:6:2} << 24 |
             16#${h:4:2} << 16 |
             16#${h:2:2} << 8  |
             16#${h:0:2} ))
}

int_to_ip() {
    local n="$1"

    printf '%d.%d.%d.%d' \
        $(( (n >> 24) & 255 )) \
        $(( (n >> 16) & 255 )) \
        $(( (n >> 8)  & 255 )) \
        $(( n & 255 ))
}

mask_to_prefix() {
    local mask="$1"
    local prefix=0
    local bit

    for ((bit=31; bit>=0; bit--)); do
        if (( mask & (1 << bit) )); then
            ((prefix++))
        fi
    done

    echo "$prefix"
}

find_ipv4_interface() {
    local address="$1"
    local ip_int
    local best_iface=""
    local best_prefix=-1
    local best_broadcast=""
    local iface destination gateway flags refcnt use metric mask rest
    local destination_int mask_int prefix broadcast_int

    ip_int=$(ip_to_int "$address")

    while read -r iface destination gateway flags refcnt use metric mask rest; do
        [ "$iface" = "Iface" ] && continue
        [ -z "$iface" ] && continue

        destination_int=$(le_hex_to_int "$destination")
        mask_int=$(le_hex_to_int "$mask")
        prefix=$(mask_to_prefix "$mask_int")

        if (( (ip_int & mask_int) == destination_int )); then
            if (( prefix > best_prefix )); then
                best_prefix=$prefix
                best_iface=$iface

                broadcast_int=$(( (ip_int | (~mask_int & 0xffffffff)) & 0xffffffff ))
                best_broadcast=$(int_to_ip "$broadcast_int")
            fi
        fi
    done < /proc/net/route

    if [[ "$address" == 127.* ]]; then
        best_iface="lo"
        best_prefix=8
        best_broadcast=""
    fi

    echo "$best_iface|$best_prefix|$best_broadcast"
}

interface_flags() {
    local iface="$1"
    local raw
    local value
    local result=""

    raw=$(cat "/sys/class/net/$iface/flags" 2>/dev/null)
    value=$((raw))

    add_flag() {
        [ -n "$result" ] && result="${result},"
        result="${result}$1"
    }

    (( value & 0x1 ))     && add_flag "UP"
    (( value & 0x2 ))     && add_flag "BROADCAST"
    (( value & 0x8 ))     && add_flag "LOOPBACK"
    (( value & 0x10 ))    && add_flag "POINTOPOINT"
    (( value & 0x40 ))    && add_flag "RUNNING"
    (( value & 0x80 ))    && add_flag "NOARP"
    (( value & 0x100 ))   && add_flag "PROMISC"
    (( value & 0x1000 ))  && add_flag "MULTICAST"
    (( value & 0x10000 )) && add_flag "LOWER_UP"

    echo "$result"
}

ipv6_format() {
    local address="$1"
    local output=""
    local group
    local value
    local i

    for ((i=0; i<32; i+=4)); do
        group="${address:i:4}"
        value=$(printf '%x' "$((16#$group))")

        [ -n "$output" ] && output="${output}:"
        output="${output}${value}"
    done

    echo "$output"
}

ipv4_addresses=$(
    awk '
        /\/32 host LOCAL/ {
            print previous
        }
        {
            previous=$2
        }
    ' /proc/net/fib_trie 2>/dev/null |
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' |
    sort -u
)

for interface_path in /sys/class/net/*; do
    [ -e "$interface_path" ] || continue

    iface=${interface_path##*/}

    index=$(cat "$interface_path/ifindex" 2>/dev/null)
    mtu=$(cat "$interface_path/mtu" 2>/dev/null)
    state=$(cat "$interface_path/operstate" 2>/dev/null)
    qlen=$(cat "$interface_path/tx_queue_len" 2>/dev/null)
    mac=$(cat "$interface_path/address" 2>/dev/null)
    type=$(cat "$interface_path/type" 2>/dev/null)
    flags=$(interface_flags "$iface")

    printf '%s: %s: <%s> mtu %s state %s qlen %s\n' \
        "${index:-?}" \
        "$iface" \
        "$flags" \
        "${mtu:-unknown}" \
        "${state^^}" \
        "${qlen:-unknown}"

    case "$type" in
        772)
            printf '    link/loopback %s brd 00:00:00:00:00:00\n' \
                "${mac:-00:00:00:00:00:00}"
            ;;
        1)
            printf '    link/ether %s brd ff:ff:ff:ff:ff:ff\n' \
                "${mac:-unknown}"
            ;;
        *)
            echo '    link/none'
            ;;
    esac

    while read -r address; do
        [ -z "$address" ] && continue

        mapping=$(find_ipv4_interface "$address")
        mapped_iface=${mapping%%|*}
        remainder=${mapping#*|}
        prefix=${remainder%%|*}
        broadcast=${remainder#*|}

        [ "$mapped_iface" = "$iface" ] || continue

        if [ "$iface" = "lo" ]; then
            printf '    inet %s/%s scope host %s\n' \
                "$address" "$prefix" "$iface"
        elif [ -n "$broadcast" ]; then
            printf '    inet %s/%s brd %s scope global %s\n' \
                "$address" "$prefix" "$broadcast" "$iface"
        else
            printf '    inet %s/%s scope global %s\n' \
                "$address" "$prefix" "$iface"
        fi
    done <<< "$ipv4_addresses"

    if [ -r /proc/net/if_inet6 ]; then
        while read -r address ipv6_index prefix scope flags6 ipv6_iface; do
            [ "$ipv6_iface" = "$iface" ] || continue

            formatted=$(ipv6_format "$address")
            prefix_decimal=$((16#$prefix))

            case "$scope" in
                00) scope_name="global" ;;
                10) scope_name="host" ;;
                20) scope_name="link" ;;
                *)  scope_name="unknown" ;;
            esac

            printf '    inet6 %s/%s scope %s\n' \
                "$formatted" "$prefix_decimal" "$scope_name"
        done < /proc/net/if_inet6
    fi
done
EOF

chmod +x /tmp/ip-a.sh
