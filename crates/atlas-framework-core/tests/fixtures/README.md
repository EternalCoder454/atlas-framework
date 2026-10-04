# Fixtures: never edit

Each file is a sample of an on-disk form Atlas has written, kept byte for
byte. The tests read all of them and assert the parsed values. A new format
adds new files; **no file here is ever edited or deleted**, because the
framework reads every old form forever (docs/DESIGN.md, "Compatibility").

- `atlas-legacy-rc`: a settings file from before `[Atlas] Format=`.
- `atlas-v1-rc`: `[Atlas] Format=1`.
- `atlas-future-rc`: a higher format with keys and groups this code does not know.
