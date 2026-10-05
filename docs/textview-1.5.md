# A virtualized text view (1.5.0 item 38): requirements

What Atlas Notepad needs, from its session on 2026-10-05, plus what the
other apps read. This is the input for the design page that comes before the
code; the API, once it exists, is documented only in docs/reference.

Consumers: Notepad (plain and code files; its Markdown Formatted view stays
on TextEdit), AtlasCodeView, Monitor's and the Updater's logs, Notes' source
view.

## Shape

- A C++ QQuickItem in Atlas.Ui (like RepaintArea and LiveChart).
- The text in C++: a piece table with a line index. The original buffer may
  stay UTF-8 or memory-mapped; only the add buffer and the visible lines
  become QString.
- Only the visible lines are laid out (QTextLayout), cached per line by
  version. Word wrap is a mode, with a lazily built wrapped-line index.
- KSyntaxHighlighting through AbstractHighlighter, with the state kept per
  line and styling done in the background ahead of the viewport. A full
  re-highlight or theme switch is linear and restyles the visible lines in the
  first frame.
- The app (Rust in Notepad) does file I/O, encodings and search. The item
  takes pieces on load and gives a fast whole-text or range snapshot for save.

## Baseline (Notepad on Qt TextEdit)

Notepad 220dbb9: Release build, software backend, 1x scale, Xvfb, P-cores,
median of 3. Times in ms.

| File | First text | All text | RSS | Typing mean/p95 | Scroll |
|---|---|---|---|---|---|
| code 1 MB, 30k lines | 275 | 1,095 | 228 MB | 7.9 / 9.1 | 4.1 |
| code 5 MB, 152k lines | 222 | 2,562 | 649 MB | | |
| code 9.5 MB, 288k lines | 214 | 10,643 | 1,106 MB | | |
| log 9.5 MB, 79k lines | 204 | 1,942 | 722 MB | 18.7 / 22.6 | 6.3 |
| JSON 5 MB on one line (read-only) | 2,241 | 2,241 | 618 MB | | |

- Notepad refuses files over 10 MiB.
- Backspace and Enter cost the same as typing.
- Arrow keys take 1.7 to 4 ms.

Files and harness (read only, in the Notepad repository):
- `out/large/`: the test files, with the results in bench.log and bench2.log.
- `apps/atlas-notepad/cpp/bench.cpp`: the harness, run as `atlas-notepad --bench FILE` (`NP_BENCH_OPEN_ONLY=1` times the open only).
- `scripts/bench-s1.sh`: the headless, pinned setup.

## Acceptance

Measured on the same setup: software backend, 1x scale.

- **Keys.** Any key (typing, Backspace, Enter, the arrows, pasting a line) takes under 2 ms on average and under 4 ms at p95. That holds for any file up to 100 MB and any line up to 1 MB.
- **Opening.**
  - The first text shows within 250 ms, whatever the file size.
  - A 100 MB file is fully editable within 1.5 s.
  - After the first frame, no stall on the GUI thread is longer than 16 ms. Loading and indexing run off the GUI thread, or in slices.
- **Memory.**
  - At most 3 MB of RSS per MB of ASCII text, over the empty app. TextEdit takes 70 to 110 MB per MB.
  - A 100 MB file uses under about 500 MB in total.
- **Limits.**
  - A 1 GB file opens without being refused.
  - A 10 MB file on one line opens, scrolls sideways, and takes edits at the key targets above.

## Must have

- **Caret, selection and mouse.**
  - Click, double-click selects a word, triple-click selects a line.
  - Dragging selects, and scrolls the view at the edge.
  - A selection can be dragged and dropped.
  - Keys: move by word, smart Home to the indent, Page Up and Page Down, Ctrl+Home and Ctrl+End.
  - Middle click pastes the primary selection, and the clipboard works.
- **Text input.** An IME with a preedit underline, bidi and RTL, emoji and combining marks, tab stops, zoom and font changes.
- **Undo.** Undo and redo merge typing. A compound-edit API (beginEdit and endEdit) groups changes such as sort, comment, indent, case, trim, replace all, and the auto-indent newline.
- **Modes and display.** Read-only, word wrap on or off, both themes, the software backend, and accessibility through QAccessibleTextInterface.
- **Line endings** are kept per file (LF, CRLF, CR or mixed), with a property to convert them.
- **API:**
  - positionOfLine and lineColumn;
  - the line count and the text of a range;
  - the visible line range;
  - contentsChange(position, removed, added);
  - get and set the caret, the selection and the scroll position;
  - decoration ranges with a style (find matches, the current line, the matching bracket, squiggles);
  - a line-number margin or a margin hook;
  - the highlighting format at a position.
- **Highlighting.** Every KSyntaxHighlighting definition. The most used are C/C++, Rust, Python, JS/TS, JSON, YAML, TOML, shell, INI, XML and HTML, CSS, Markdown source, diff and logs.

## Nice to have (Notepad++ features)

- Column selection: Alt+drag, Alt+Shift+arrows, and typing in a column.
- Multiple carets: Ctrl+click, and Ctrl+D for the next occurrence.
- Showing whitespace and line-end markers, indent guides and folding.
- A minimap.
- Highlighting all matches, in the visible range only.
- Tail mode: text is appended without moving the view.
