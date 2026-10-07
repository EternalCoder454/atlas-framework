# AtlasTextView: design (1.5.0 item 38)

> Written before the 2.0.0 rename and left as it was: Atlas.Ui is now Telamon.Ui,
> every `Atlas<Name>` type is `Telamon<Name>`, `atlas-ui` is `telamon-ui` and
> the `atlas-framework-*` crates are `telamon-framework-*` (see CHANGELOG.md).

How the virtualized text view is built, from the requirements in
[textview-1.5.md](textview-1.5.md). This page is the proposal Notepad reviews
before any code exists. The API sketch below is a draft. Once the type ships,
its reference page in docs/reference/atlas-ui is the only API description, and
the sketch is deleted from here.

## Name and place

- `AtlasTextView`, a C++ `QQuickItem` in Atlas.Ui, next to RepaintArea and
  LiveChart.
- The C++ sources are in `ui/text/`: the buffer, the layout cache, the
  highlighter and the item.
- New dependency: KF6SyntaxHighlighting (`kf6-syntax-highlighting`), tier 1,
  already on every Plasma system. Containerfile.dev, the spec and CI gain it.
- No app has a `AtlasTextView.qml` (checked against the five apps on
  2026-10-05).

## Shape

```
 Rust (app)                 C++ (Atlas.Ui)                         Qt Quick
 ----------                 --------------                         --------
 read file, decode  ──UTF-8 chunks──▶  TextBuffer (piece tree)
 search, save       ◀──snapshot───────  │  line index in the tree
                                        │
                     background thread  ├─▶ Indexer (newlines, UTF-16 counts)
                     background thread  ├─▶ Highlighter (state per line)
                                        │
                     GUI thread         └─▶ LayoutCache (QTextLayout per
                                             visible line) ─▶ one QSGTextNode
                                             per visible line
```

## The buffer

- **Storage is UTF-8.** It holds two buffers: the original text (one
  `QByteArray` per loaded chunk, never copied after load) and an append-only
  add buffer for typed text. Rust hands over valid UTF-8 only; the item checks
  it and replaces invalid sequences with U+FFFD, setting `hadInvalidText`.
- **Pieces live in a balanced tree.** It is a B-tree with about 64 pieces per
  node, and every node keeps aggregates: bytes, UTF-16 units and line breaks.
  - Position to line, line to position, and UTF-16 offset to byte offset are
    all O(log n).
  - Within a piece, a lookup scans at most one 64 KB chunk; the original
    buffer is split into pieces of at most 64 KB at load.
  - No per-line array is kept, so a 1 GB file with 20 million lines costs
    tree nodes, not 20 million entries.
- **The tree is persistent.** Nodes are immutable, shared and reference-counted,
  so an edit copies only the path from the root to the leaf. A snapshot is one
  pointer copy. It is O(1) and thread-safe, and the indexer, the highlighter,
  save and search all work on snapshots while the user keeps typing.
- **Positions and lines in the API**
  - Positions are in UTF-16 units, like TextEdit and every QML string.
  - Lines and columns start at 0. Columns are in UTF-16 units too.
  - The caret never stops inside a surrogate pair, a grapheme cluster or a CRLF.
- **Line endings stay as they are in the file.**
  - LF, CRLF and lone CR all count as one break. CRLF is two UTF-16 positions,
    so positions match the file.
  - `lineEnding` reports LF, CRLF, CR or Mixed. Enter inserts the most common
    one, or LF in an empty file.
  - `convertLineEndings(kind)` rewrites them as a single compound edit, so one
    Undo restores them.
- **Undo**
  - Each record holds a position, the removed pieces (references into the
    tree, not copies), the inserted pieces, and the caret and selection before
    and after.
  - Undoing a 50 MB delete costs nothing extra.
  - Typing merges while it continues: same kind of edit, adjacent, the same
    word class, and under 1 s apart.
  - `beginEdit()` and `endEdit()` group changes into one record and nest.
  - The default `undoLimit` is 1000 records.

## Loading

- `beginLoad()`, `appendData(utf8)` as often as wanted, then `endLoad()`.
  - Rust streams the file in chunks of any size; the item cuts them into 64 KB
    pieces.
  - The first `appendData` that reaches a screenful is laid out and painted at
    once, which meets the 250 ms first-text target whatever the file size.
- Counting newlines and UTF-16 units runs on worker threads, about 1 GB/s per
  core with a plain memchr-style loop. The tree is built from the results.
- `loading` stays true until it is done, and `loadProgress` goes from 0 to 1.
- Until then the view is read-only, scrolls over the part already indexed,
  and the scroll bar grows.
  - At 100 MB, indexing takes about 0.1 to 0.2 s, well inside the 1.5 s
    editable target.
- `text` is also a property, for small uses such as AtlasCodeView or a dialog:
  - reading it builds a QString of the whole text;
  - setting it replaces everything as one load.
  - The reference page will say that large files use `appendData`.
- **Tail mode** (`follow: true`) is for logs:
  - `appendText()` and `appendData()` after `endLoad()` add to the end without
    an undo record;
  - when the view was at the bottom it stays there; otherwise it doesn't move.
  - `maximumLines`, which defaults to 0 (no limit), drops the oldest lines, as
    Monitor's log needs.

## Snapshot and save

- `snapshot()` returns an `AtlasTextSnapshot`, a small immutable QObject that
  holds a tree root. It has:
  - `length` and `lineCount`;
  - `text(start, end)`;
  - a chunk visitor (C++ only), which walks the pieces in order without
    copying. Each chunk comes with its starting byte offset and its starting
    UTF-16 offset, so a search over bytes maps its hits without rescanning.
  - `utf16AtByte(offset)` and `byteAtUtf16(position)`, both O(log n);
  - `revision`, which increments on every edit, so a search result can be
    checked for staleness.
- A snapshot is a cheap value, a shared pointer to the root. Holding one keeps
  that version's pieces alive and nothing else.

## The C++ API

Notepad drives the view from C++, with its Document, CodeEditor, LineTools and
SpellCheck classes, so the view needs a C++ API as well as QML properties. It
is header-only and versioned, the way Qt's plugin interfaces are. There are no
exported symbols to link against and no soname to manage.

- **The package.** `atlas-ui-devel` installs `atlas/textview.h` and
  `atlas/textsnapshot.h` under `/usr/include/atlas-ui/` with a pkg-config file.
  There is no library. The RPM spec, CMake's install and the
  `packaging/` checks gain it.
- **`AtlasTextViewInterface`**
  - It is a pure-virtual class, declared with
    `Q_DECLARE_INTERFACE(AtlasTextViewInterface,
    "net.eterneon.Atlas.TextView/1")`. The item implements it, and an app gets
    it with `qobject_cast<AtlasTextViewInterface *>(item)`.
  - It holds everything the QML API has, plus `snapshot()`, `replace()` and the
    edit grouping, called directly with no QMetaObject in between.
- **`AtlasTextSnapshot`**
  - It is a small handle: a header-only value class holding a ref-counted
    pointer to `AtlasTextSnapshotInterface`, an abstract class implemented in
    the plugin. Its inline methods only forward to that interface's virtuals.
    No tree walking, and none of the node layout, is compiled into an app, so
    the piece tree stays private and can change freely.
  - The visitor takes a callback (`std::function` or a template), so the app's
    C++ can hand the chunk pointers to its Rust.
- **Versioning.** A published interface never changes. A new release that
  needs more adds `AtlasTextViewInterface2` (IID `/2`), which derives from
  `/1`, and the item implements both. An app built against `/1` keeps working.
  This is the same rule as the rest of the contract (see "Compatibility" in
  DESIGN.md); `tools/check-api.sh` gains a check that a published header's
  interfaces are unchanged.
- **Highlighters (step 3).** `AtlasTextHighlighterInterface` lets an app plug
  in its own highlighter, like Notepad's MarkdownHighlighter. It takes the
  state at the start of a line and the line's text, and returns format runs
  and the end state. KSyntaxHighlighting stays the built-in one behind the
  same interface.

## Layout and painting

- **Lines are laid out only when visible.** Each line visible in the viewport,
  plus one screen above and below, gets a QTextLayout with the font, tab stops
  and format ranges. Layouts are cached by line identity and revision, at about
  4 screens' worth (LRU).
- **Height and scrolling**
  - Without wrap, every line is one row, so content height is lines × row
    height, exactly.
  - With wrap:
    - A Fenwick tree keeps the row count per line.
    - Unmeasured lines count as 1 row and are measured in the background, in
      16 ms slices.
    - The scroll position is anchored to a line, so the view doesn't jump as
      estimates are replaced.
- **Long lines**
  - A line over 4,096 UTF-16 units is laid out in segments that break at
    grapheme and word boundaries. Only the segments in view are laid out.
  - Segment widths are measured when first needed. Before that they are
    estimated from the font's average advance; with a monospace font the
    estimate is exact.
  - The 10 MB single-line case therefore lays out only a few kB.
  - Bidi across a segment boundary is approximate. This only affects lines
    over 4 kB, and is written down as a limit.
  - Any font works, proportional ones included. When a measured width
    replaces an estimate, the horizontal scroll stays anchored to the caret's
    segment (or the first visible segment), so the view never jumps.
- **Control characters and binary files.** NUL and the other C0 and C1
  controls are drawn as visible glyphs (the Control Pictures block, U+2400 on,
  in the muted colour), as QTextLayout does today. They are ordinary
  characters in the buffer, and only LF and CR break lines, so the line index
  is unaffected.
- **Painting**
  - One `QSGTextNode` per visible line, made with `QQuickWindow::createTextNode()`
    (public since Qt 6.7).
  - The nodes are reused as lines scroll in and out, and only changed lines are
    rebuilt.
  - Selection, current-line and decoration rectangles are rectangle nodes, so
    they work on the software backend too.
- **The caret**
  - It is a rectangle node, and its blink changes only its opacity.
  - Blinking stops when the view is unfocused or hidden, after 10 s idle, and
    under `AccessibilityState.reducedMotion`. When it stops, the caret stays
    shown.
  - Idle CPU is zero.
- **Margin**
  - `showLineNumbers` draws a line-number gutter with the same per-line nodes.
  - For anything else, the item exposes `firstVisibleLine`, `lastVisibleLine`
    and `lineY(line)`. An app positions its own margin items, for example a
    Repeater over the visible range, with no per-line QML for lines out of view.

## Highlighting

- **The highlighter** subclasses `KSyntaxHighlighting::AbstractHighlighter`.
- **State per line.** The state after each line is kept in a chunked array
  that follows the line index. A `State` is one shared pointer, 8 bytes a
  line, so 2 million lines cost about 16 MB, and only after they are
  highlighted.
- **Format runs are not stored.** They are recomputed from the line's start
  state when a line is laid out, which takes microseconds a line.
- **After an edit**
  - Highlighting restarts at the edited line and continues until a line's end
    state matches the stored one.
  - A typical keystroke re-highlights one line, synchronously, inside the 2 ms
    budget.
  - An edit that opens a block comment restyles the visible lines at once; the
    rest follows in the background.
- **The background pass**
  - It runs ahead of the viewport on a worker thread, over a snapshot.
  - The worker has its own `KSyntaxHighlighting::Repository`, because a
    Repository is not thread-safe.
  - Results come back tagged with the snapshot's revision. Lines edited since
    then are recomputed, not trusted.
  - When the view jumps far ahead of the known states (Ctrl+End in a 100 MB
    file), the visible lines show plain text first and are restyled when the
    pass arrives.
  - A file over `highlightLimit` (default 50 MB) is not highlighted at all.
- **Theme.** An Atlas theme is built from AtlasStyle's tokens, a light and a
  dark variant, so code matches the rest of the app. Changing the theme
  restyles the visible lines in the next frame and the rest lazily.
- **The `syntax` property** takes a definition name ("Rust", "Python"). An
  empty name means plain text. `syntaxForFile(name, firstLine)` asks the
  repository for a guess.

## Input

- **Keys.** Every key arrives through `keyPressEvent`, so an event filter an
  app installs on the item sees it first and can take it. Notepad's
  auto-indent on Enter, Tab and Backtab indent, and bracket handling keep
  working that way. The keys come from QKeySequence::StandardKey, plus smart
  Home.
  Word moves use QTextBoundaryFinder on the line, and visual movement in bidi
  text uses `QTextLayout::leftCursorPosition` and `rightCursorPosition`.
- **The input method**
  - `inputMethodQuery` answers `ImSurroundingText` for the current line only,
    capped at 1,000 characters each side, so an input method never asks for
    10 MB.
  - Preedit text is drawn underlined, as a decoration.
- **The mouse**
  - Click count comes from the platform's double-click interval.
  - A drag selects, and an edge auto-scrolls on a timer that runs only while
    dragging.
  - A selection can be dragged and dropped with QDrag. It moves within the
    view, and copies with Ctrl or when it goes to another app.
  - A middle click pastes `QClipboard::Selection`.
- **Accessibility**
  - A `QAccessibleInterface` factory gives the item `QAccessibleTextInterface`
    and `QAccessibleEditableTextInterface`.
  - `text(start, end)` reads from the buffer, and `characterCount` is the real
    count.
  - Text changes go out as `QAccessibleTextUpdateEvent` with the changed range
    only.

## Decorations

- `setDecorations(layer, ranges, style)` replaces one named layer.
  - The ranges are an array of `[start, end]`.
  - The style is one of Match, CurrentMatch, Bracket, CurrentLine, Error,
    Warning, Info or Spelling. Spelling is a wavy underline in the error
    colour, drawn as geometry, so it shows on the software backend too.
  - Layers are kept in an interval tree, so only the ranges inside visible
    lines are looked at.
- Positions in a layer shift with edits, as markers do. A range whose text is
  deleted disappears.
- Notepad's find and highlight-all set a layer for the visible range only, and
  set it again on `visibleRangeChanged`.

## API sketch (draft)

Properties:
- `text`
- `readOnly`
- `wrap`
- `font` (AtlasStyle's monospace font by default)
- `tabWidth`
- `lineCount` and `length`
- `cursorPosition`, `selectionStart`, `selectionEnd` and `selectedText`
- `contentX`, `contentY`, `contentWidth` and `contentHeight`
- `firstVisibleLine` and `lastVisibleLine`
- `lineEnding`
- `modified`
- `canUndo`, `canRedo` and `undoLimit`
- `loading`, `loadProgress` and `hadInvalidText`
- `syntax` and `highlightLimit`
- `showLineNumbers` and `highlightCurrentLine`
- `follow` and `maximumLines`

Methods:
- `positionOfLine(line)` and `lineColumn(position)`, which returns `{line, column}`
- `textInRange(start, end)`
- `select(start, end)`, `insert`, `remove` and `replace`
- `beginEdit()` and `endEdit()`
- `undo()` and `redo()`
- `cut()`, `copy()`, `paste()` and `selectAll()`
- `ensureVisible(position)` and `lineY(line)`
- `formatAt(position)`, which returns `{name, style}`
- `setDecorations()` and `clearDecorations(layer)`
- `beginLoad()`, `appendData()`, `appendText()` and `endLoad()`
- `snapshot()`
- `convertLineEndings(kind)`
- `syntaxForFile(name, firstLine)`

Signals:
- `contentsChange(position, removed, added)`, which fires before the
  property-changed signals for the same edit
- `visibleRangeChanged()`
- `loaded()`
- `textEdited()`, for user edits only, as the edit rule in DESIGN.md asks

## How it lands (all in 1.5.0)

1. **The buffer and a read-only view**
   - The buffer, loading, wrap, highlighting, selection and copy, the mouse,
     accessibility, line numbers, decorations, follow mode, and the snapshot.
   - AtlasCodeView moves onto it, keeping its own API, and so does the
     Updater's report view.
   - The tests come with it:
     - a fuzz test of the piece tree against a QString model, with 10,000
       random edits per seed, the tree's invariants checked after each one,
       and surrogates, CRLF and empty pieces;
     - load and line-ending tests;
     - goldens for light, dark, wrap, a selection, highlighting, RTL and a long
       line;
     - an a11y test.
2. **Editing**
   - Keys, the input method, undo with merging and compound edits, drag and
     drop, the primary selection, and line-ending conversion.
   - Keyboard and IME tests, using QTest key events and `QInputMethodEvent`.
3. **The nice-to-haves from textview-1.5.md**
   - In Notepad's order: column selection and multiple carets, then shown
     whitespace and line ends with indent guides, then folding, then the
     minimap, then the highlighter interface.
   - Each lands only once 1 and 2 meet every acceptance number.

## Measuring

- **The harness.** Notepad's harness (`bench.cpp` and `bench-s1.sh`) is
  copied to `perf/textview/`. It runs against generated files: code, log,
  JSON on one line, and a 1 GB file, which is generated and never committed.
- **CI.** The perf job runs a smaller set (1 MB and 10 MB) against budgets in
  `perf/budget.json`. The 100 MB and 1 GB runs are manual (`perf/textview/run.sh
  --large`), and their results are written into textview-1.5.md's table.
- **Acceptance.** The numbers are textview-1.5.md's acceptance list, on the
  same setup: software backend, 1x, P-cores, and the median of 3 runs.

## Notepad's answers (2026-10-05)

1. Notepad's Rust is a plain C ABI, called from C++ glue (Document,
   CodeEditor, LineTools, SpellCheck). That is why the C++ API above exists. A
   C header for Rust isn't needed: Notepad's C++ hands chunk pointers to Rust
   itself.
2. UTF-16 positions and 0-based lines suit it. The 1-based numbers are only in
   Notepad's UI.
3. `snapshot().text()` on demand is enough for the Formatted view. Markdown
   tabs stay on TextEdit at first; plain and code files move.
4. Rust will stream valid UTF-8. Save re-encodes from the chunks, so original
   bytes needn't be kept. Notepad normalizes line endings to LF itself and
   applies the file's ending on save, so the item must work with LF-only text
   and nothing else from its line-ending support. It does: `lineEnding` is
   then LF, and nothing is converted.
5. The nice-to-haves go in the order listed under step 3.

Notepad's gaps are covered above: the keys through `keyPressEvent`, the chunk
offsets and offset maps, the Spelling style, the highlighter interface,
proportional fonts, and visible control characters.

## Headers

The two headers are `crates/atlas-framework-ui/include/atlas/textsnapshot.h`
and `textview.h`, next to app.h (the package installs them under
`/usr/include/atlas-ui/atlas/`). They are not in CMake yet. Open decisions the
design left, for Notepad to confirm:

- **Snapshot is not a QObject.** "Snapshot and save" said QObject; "The C++
  API" said a value handle. The headers follow the second. Reference counting
  is virtual (`ref`/`deref`), so no layout is compiled into apps.
- **Chunks** are `AtlasTextChunk` (data, byteLength, byteOffset, utf16Offset,
  utf16Length), reached by `chunkAt(i)` or the `visitChunks(callback)`
  template (callback returns false to stop). Every snapshot also has
  `utf8(start, end)`, `lineStart/lineStartByte/lineAt/lineAtByte` and
  `chunkIndexAtByte`.
- **Version guard:** `abiVersion()` is the first virtual; a handle built over
  an older implementation is null, reads as empty, and never crashes.
- **Signals** cannot be on a non-QObject interface. They stay on the item,
  reached by `item()`, with signatures documented in textview.h (string-form
  `connect`).
- **Save** is `snapshot()` plus the app's writing, then `markSaved(revision)`
  (new), so edits made during a save keep `modified` true.
- **Highlighter** (`AtlasTextHighlighterInterface`): takes a start state and
  the line text, appends `FormatRun`s, returns the end state; runs on a worker
  thread; set with `setHighlighter(shared_ptr)`. Added to `textview.h` now so
  Notepad can review it, though it ships in step 3.
- **Added beyond the sketch:** `cursorRectangle()`, `interfaceVersion()`,
  `item()`. Enums (`LineEnding`, `DecorationStyle`) live in `namespace
  AtlasText` with fixed integer values.

Changes after Notepad's review of the headers (all in the headers now):

- `positionAt(QPointF)` and `rectangleAt(position)` map points and positions
  in item coordinates.
- `rehighlight(first, last)` and `rehighlight()` restyle lines without
  replacing the highlighter. The view only stores and compares int states, so
  an app can intern richer states as ints.
- Undo and redo restore the caret and selection from before and after the
  record, as QTextDocument does.
- `contentsChange` positions are in the text after the change. Inside
  `beginEdit()`/`endEdit()` it fires once per change, not once per group.
- The built-in highlighter follows the Atlas.Ui light/dark palette;
  `setSyntaxTheme(name)` overrides it, and an empty name follows the palette.
- `replaceDecorations(layer, region, ranges, style)` replaces only the ranges
  inside `region`. It ships in step 3; until then it does nothing.
- `~AtlasTextViewInterface()` is protected.
- QML `text`: `textChanged` does not build the string; the getter copies only
  when read.
- `lineEnding()` and `convertLineEndings()` are in the API and documented
  (CRLF is two positions; one undo restores a conversion).

Scope: Notepad's Markdown Formatted view stays on QTextDocument, because it
needs rich layout. AtlasTextView covers plain text, code and Markdown source.
