# Fixtures: never edit

Each file is a sample of an on-disk form Atlas has written, kept byte for
byte. The tests read all of them and assert the parsed values. A new format
adds new files; **no file here is ever edited or deleted**, because the
framework reads every old form forever (docs/DESIGN.md, "Compatibility").

- `atlas-legacy-rc`: a settings file from before `[Atlas] Format=`.
- `atlas-v1-rc`: `[Atlas] Format=1`.
- `atlas-future-rc`: a higher format with keys and groups this code does not know.

From 2.0.0 (the Telamon framework) the settings file is `telamon-<app>rc` with
`[Telamon]` where the `atlas-` files above have `[Atlas]`. The `telamon-` files
are the forms written since; the `atlas-` ones stay because `Settings::for_app`
copies such a file to the new name the first time (tests/legacy_adopt.rs).

- `telamon-legacy-rc`: a settings file with no `Format=` group at all.
- `telamon-v1-rc`: `[Telamon] Format=1`.
- `telamon-future-rc`: a higher format with keys and groups this code does not know.
