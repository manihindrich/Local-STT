#!/bin/sh
# Watches /input for audio files, transcribes them via the whisper API and
# moves the audio plus its .txt transcript to /output.
set -u

INPUT_DIR="/input"
OUTPUT_DIR="/output"
EVENTS="$OUTPUT_DIR/.events"
BASE_URL="http://whisper:9000"
API_URL="$BASE_URL/v1/audio/transcriptions"
MODEL="${WHISPER_MODEL:-large-v3-turbo}"
LANGUAGE="${WHISPER_LANGUAGE:-cs}"
API_KEY="${WHISPER_API_KEY:-none}"
AUDIO_RE='\.(mp3|wav|m4a|mp4|flac|ogg)$'

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR"
: > "$EVENTS"

# Progress events consumed by notify.sh on the host: TYPE|file|...
event() {
  echo "$*" >> "$EVENTS"
}

queue_count() {
  ls -1 "$INPUT_DIR" 2>/dev/null | grep -ciE "$AUDIO_RE"
}

echo "Waiting for the whisper server to load the model..."
until curl -sf -H "Authorization: Bearer $API_KEY" "$BASE_URL/v1/models" >/dev/null; do
  sleep 2
done

process() {
  FILENAME="$1"
  FILEPATH="$INPUT_DIR/$FILENAME"

  echo "$FILENAME" | grep -qiE "$AUDIO_RE" || return 0
  [ -f "$FILEPATH" ] || return 0

  NAME=$(printf '%s' "$FILENAME" | tr '|' '_')
  SIZE=$(stat -c %s "$FILEPATH")
  TXT="$OUTPUT_DIR/${FILENAME%.*}.txt"
  PART="$OUTPUT_DIR/.${FILENAME%.*}.txt.part"

  echo "Processing: $FILENAME"
  event "START|$NAME|$SIZE|$(( $(queue_count) - 1 ))"
  START=$(date +%s)

  if curl -sSf -X POST "$API_URL" \
      -H "Authorization: Bearer $API_KEY" \
      -F "file=@$FILEPATH" \
      -F "model=$MODEL" \
      -F "language=$LANGUAGE" \
      -F 'response_format=text' \
      -o "$PART"; then
    mv "$PART" "$TXT"
    mv "$FILEPATH" "$OUTPUT_DIR/$FILENAME"
    ELAPSED=$(( $(date +%s) - START ))
    echo "Done in ${ELAPSED}s: $FILENAME"
    event "DONE|$NAME|$SIZE|$ELAPSED|$(stat -c %s "$TXT")|$(queue_count)"
  else
    rm -f "$PART"
    echo "Transcription failed, file left in /input: $FILENAME" >&2
    event "ERROR|$NAME|$SIZE|$(( $(queue_count) - 1 ))"
  fi
}

# Pick up files that arrived while the watcher was not running
for f in "$INPUT_DIR"/*; do
  [ -f "$f" ] && process "$(basename "$f")"
done

echo "Watching /input for new audio files..."

inotifywait -m -e close_write -e moved_to --format '%f' "$INPUT_DIR" | while IFS= read -r FILENAME; do
  process "$FILENAME"
done
