#!/usr/bin/env bash
# Runs on the host: follows output/.events written by the watcher and shows
# progress in a single, continuously updated desktop notification.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
EVENTS="$DIR/output/.events"
# A finished file is shown together with the next one if it starts within this many seconds
MERGE_WINDOW=10
# Longer file names are shortened to start…end
NAME_MAX=30

ID=""
LAST_DONE=""
DONE_AT=0

human_size() {
  awk -v b="$1" 'BEGIN {
    split("B kB MB GB TB", u, " "); i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf(i == 1 ? "%d %s" : "%.1f %s", b, u[i])
  }'
}

human_time() {
  if (( $1 >= 60 )); then
    printf '%dm %02ds' $(( $1 / 60 )) $(( $1 % 60 ))
  else
    printf '%ds' "$1"
  fi
}

# Shorten and escape for notification markup
short_name() {
  local n=$1 head tail
  if (( ${#n} > NAME_MAX )); then
    # The end of the name (date, extension) is more informative than the start
    head=$(( NAME_MAX / 3 )); tail=$(( NAME_MAX - 1 - head ))
    n="${n:0:head}…${n: -tail}"
  fi
  n=${n//&/"&amp;"}; n=${n//</"&lt;"}; n=${n//>/"&gt;"}
  printf '%s' "$n"
}

queue_text() {
  (( ${1:-0} > 0 )) && printf ' · %s queued' "$1"
}

# Block = bold title line + indented italic details line
block() {
  printf '%s <b>%s</b>\n   <i>%s</i>' "$1" "$2" "$3"
}

# Reusing the same ID updates the notification instead of creating a new one
notify() {
  local out
  out=$(notify-send -a Whisper -i audio-x-generic -u "$1" -p ${ID:+-r "$ID"} "$2" "$3") && ID=$out
}

tail -n0 -F "$EVENTS" 2>/dev/null | while IFS='|' read -r type name size a b c; do
  name=$(short_name "$name")
  case $type in
    START)  # a = queued
      body=$(block "▶" "Transcribing: $name" "$(human_size "$size")$(queue_text "$a")")
      if [[ -n $LAST_DONE ]] && (( SECONDS - DONE_AT <= MERGE_WINDOW )); then
        body="$LAST_DONE"$'\n'"$body"
      fi
      notify normal "Whisper · transcribing" "$body"
      ;;
    DONE)   # a = seconds, b = transcript size, c = queued
      details="$(human_size "$size") audio · $(human_size "$b") text · $(human_time "$a")"
      LAST_DONE=$(block "✔" "Done: $name" "$details")
      DONE_AT=$SECONDS
      notify normal "Whisper · done" "$(block "✔" "Done: $name" "$details$(queue_text "$c")")"
      ;;
    ERROR)  # a = queued
      details="file left in input/"
      LAST_DONE=$(block "✖" "Failed: $name" "$details")
      DONE_AT=$SECONDS
      notify critical "Whisper · failed" "$(block "✖" "Failed: $name" "$details$(queue_text "$a")")"
      ;;
  esac
done
