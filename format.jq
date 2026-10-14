# Formats a whisper verbose_json response as readable text:
# one block per speaker turn (separated by a blank line), headed by
# "[hh:mm:ss] <label> N:", with a line break wherever the pause is >= $gap s
# or the paragraph exceeds ~500 characters.
# Without diarization, blocks are split by pauses and headed by the time only.
#
# Usage: jq -r -f format.jq --arg label Speaker --argjson gap 3 file.json

def pad2: tostring | if length < 2 then "0" + . else . end;
def clock: floor | "\(. / 3600 | floor | pad2):\(. % 3600 / 60 | floor | pad2):\(. % 60 | pad2)";
def last_index(a): (a | length) - 1;

[ .segments[]
  | .text |= gsub("^\\s+|\\s+$"; "")
  | select(.text != "") ] as $segs

# Speakers numbered in order of first appearance: SPEAKER_03 may become "1"
| ($segs | map(.speaker // empty)
         | reduce .[] as $s ([]; if any(.[]; . == $s) then . else . + [$s] end)
         | to_entries | map({(.value): (.key + 1)}) | add // {}) as $num

| reduce $segs[] as $s ({blocks: [], prev: null};
    # Segments the diarizer left unassigned continue the previous speaker
    ($s.speaker // .prev.speaker) as $spk
    | (if .prev == null then true else ($s.start - .prev.end) >= $gap end) as $pause
    | if .prev == null or $spk != .prev.speaker or ($spk == null and $pause) then
        .blocks += [{speaker: $spk, start: $s.start, paras: [[$s.text]]}]
      # Also break long monologues into paragraphs of roughly 500 characters
      elif $pause or (.blocks[last_index(.blocks)].paras | last | join(" ") | length) >= 500 then
        .blocks[last_index(.blocks)].paras += [[$s.text]]
      else
        .blocks[last_index(.blocks)].paras |= (.[last_index(.)] += [$s.text])
      end
    | .prev = ($s | .speaker = $spk))

| .blocks
| map("[\(.start | clock)]"
      + (if .speaker == null then "" else " \($label) \($num[.speaker]):" end)
      + "\n" + (.paras | map(join(" ")) | join("\n")))
| join("\n\n")
