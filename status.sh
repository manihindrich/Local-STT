#!/usr/bin/env bash
# Runs on the host: prints the current transcription status as JSON.
# Consumed by the Plasma tray widget; safe to run by hand (`./status.sh | jq`).
set -u
export PATH="$PATH:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin"

DIR="$(cd "$(dirname "$0")" && pwd)"
EVENTS="$DIR/output/.events"
SERVER=whisper
WATCHER=whisper-watcher

state=idle file="" size=0 queued=0 elapsed=0 eta=-1 cpu="" mem="" last="" last_secs=0 errors=0

if [[ -s $EVENTS ]]; then
  errors=$(grep -c '^ERROR|' "$EVENTS")
  if done_line=$(grep '^DONE|' "$EVENTS" | tail -n1) && [[ -n $done_line ]]; then
    IFS='|' read -r _ last _ last_secs _ <<< "$done_line"
  fi

  IFS='|' read -r type name fsize fqueued _ <<< "$(tail -n1 "$EVENTS")"
  if [[ $type == START ]]; then
    state=busy file=$name size=$fsize queued=$fqueued
    # The last write to .events was this START, so its mtime is the start time
    elapsed=$(( $(date +%s) - $(stat -c %Y "$EVENTS") ))

    # ETA from the average throughput of finished files larger than 1 MB
    rate=$(awk -F'|' '$1 == "DONE" && $3 > 1048576 { b += $3; s += $4 }
                      END { printf "%d", (s > 0 ? b / s : 0) }' "$EVENTS")
    if (( rate > 0 )); then
      eta=$(( size / rate - elapsed ))
      (( eta < 0 )) && eta=0
    fi

    # Only flag an error when docker answered and the watcher is not running
    if watcher_state=$(docker ps -a --filter "name=^${WATCHER}\$" --format '{{.State}}' 2>/dev/null) \
        && [[ $watcher_state != running ]]; then
      state=error
    fi
    IFS='|' read -r cpu mem < <(docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}' "$SERVER" 2>/dev/null)
    mem=${mem%% /*}
  fi
fi

jq -n \
  --arg state "$state" --arg file "$file" --arg cpu "$cpu" --arg mem "$mem" --arg last "$last" \
  --argjson size "$size" --argjson queued "$queued" --argjson elapsed "$elapsed" \
  --argjson eta "$eta" --argjson last_secs "$last_secs" --argjson errors "$errors" \
  --argjson cores "$(nproc)" \
  '{state: $state, file: $file, size: $size, queued: $queued, elapsed: $elapsed, eta: $eta,
    cpu: $cpu, cores: $cores, mem: $mem, last: $last, last_secs: $last_secs, errors: $errors}'
