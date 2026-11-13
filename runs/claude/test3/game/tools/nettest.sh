#!/bin/bash
# Two headless processes on this machine: a host and a client. Usage: tools/nettest.sh [godot binary]
G=${1:-${GODOT:-godot}}
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/tmp/nettest}
mkdir -p "$OUT"
timeout 300 "$G" --headless --path "$HERE" -- --nettest-host --net-warmup=8 > "$OUT/host.log" 2>&1 &
HP=$!
sleep 3
timeout 300 "$G" --headless --path "$HERE" -- --nettest-client > "$OUT/client.log" 2>&1 &
CP=$!
wait $HP; HR=$?
wait $CP; CR=$?
echo "=== host (exit $HR) ==="; grep -E "PASS|FAIL|NETTEST|SCRIPT ERROR|MATCH_OVER" "$OUT/host.log"
echo "=== client (exit $CR) ==="; grep -E "PASS|FAIL|NETTEST|SCRIPT ERROR|MATCH_OVER" "$OUT/client.log"
[ $HR -eq 0 ] && [ $CR -eq 0 ]
