# Fixtures: never edit

Each file is a sample of an on-disk form Telamon has written, kept byte for
byte. The tests read all of them and assert the parsed values. A new format
adds new files; **no file here is ever edited or deleted**, because the
framework reads every old form forever (docs/DESIGN.md, "Compatibility").

- `history-*.jsonl`: `/var/lib/atlas-core/history.jsonl`. `legacy` has no
  `format` and lines missing `version`, `image` or `timestamp`, and a bad line;
  `v1` is `"format": 1`; `future` holds higher numbers and unknown fields.
- `events-*.jsonl`: `/var/lib/atlas-core/events.jsonl`, the same three forms.
- `secrets.txt`: fake secrets for the scrubber test (see its header).
