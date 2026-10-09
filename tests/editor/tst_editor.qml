import QtQuick
import QtTest
import Telamon.Ui

// TelamonCodeEditor: the text and its edits, setTextPreserving, marks,
// read-only, the size and line-length caps, lazy highlighting, plain text and
// the keys. The editor's C++ side is reached through `_core` (private).
Item {
    id: root
    width: 520
    height: 320

    Component {
        id: editorComp
        TelamonCodeEditor {
            width: root.width
            height: root.height
        }
    }

    SignalSpy {
        id: editedSpy
        signalName: "textEdited"
    }
    SignalSpy {
        id: movedSpy
        signalName: "cursorMoved"
    }
    Component {
        id: spyComp
        SignalSpy {}
    }

    TestCase {
        name: "TelamonCodeEditor"
        when: windowShown

        property var editor: null

        function init() {
            editor = createTemporaryObject(editorComp, root);
            verify(editor);
            editedSpy.target = editor;
            editedSpy.clear();
            movedSpy.target = editor;
            movedSpy.clear();
        }

        function numbered(n, what) {
            const out = [];
            for (let i = 1; i <= n; ++i) {
                out.push((what ?? "line") + " " + i);
            }
            return out.join("\n");
        }

        function focusEditor() {
            editor.forceActiveFocus();
            tryVerify(() => editor._edit.activeFocus);
        }

        function runs(line) {
            editor._core.highlightNow();
            return editor._core.formatRuns(line);
        }

        // ---- The text ----

        function test_plain_text_stays_literal() {
            const s = "<b>bold</b> <img src=x onerror=alert(1)> [link](http://example.com) **x** &amp; <script>1</script>";
            editor.text = s;
            compare(editor.text, s);
            compare(editor._edit.textFormat, TextEdit.PlainText);
            compare(editor._edit.length, s.length);
            compare(editor.modified, false);
            compare(editor.lineCount, 1);
        }

        function test_characters_survive_and_line_breaks_are_lf() {
            editor.text = "a b\r\nc\rd e";
            compare(editor.text, "a b\nc\nd\ne", "a no-break space stays; CRLF, CR and U+2029 read back as LF");
            editor.text = "x﷐y";
            compare(editor.text, "x�y", "a frame marker of the document is replaced");
            editor.text = "";
            compare(editor.text, "");
            compare(editor.lineCount, 1);
        }

        function test_modified_and_text_edited() {
            editor.text = "hello";
            compare(editor.modified, false);
            compare(editedSpy.count, 0, "the app's own text is not an edit");
            focusEditor();
            keyClick("x");
            compare(editor.text, "xhello");
            compare(editor.modified, true);
            verify(editedSpy.count >= 1);
            editor.modified = false;
            compare(editor.modified, false);
            editor.text = "reloaded";
            compare(editor.modified, false);
            compare(editor.canUndo, false, "loading a text clears the undo history");
        }

        function test_undo_redo() {
            editor.text = "";
            focusEditor();
            keyClick("a");
            keyClick("b");
            compare(editor.text, "ab");
            verify(editor.canUndo);
            keyClick(Qt.Key_Z, Qt.ControlModifier);
            compare(editor.text, "");
            verify(editor.canRedo);
            keyClick(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier);
            compare(editor.text, "ab");
            editor.undo();
            compare(editor.text, "");
            editor.redo();
            compare(editor.text, "ab");
        }

        function test_read_only() {
            editor.text = "keep me";
            editor.readOnly = true;
            focusEditor();
            keyClick("x");
            keyClick(Qt.Key_Backspace);
            keyClick(Qt.Key_Delete);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Tab);
            compare(editor.text, "keep me");
            compare(editor.modified, false);
            compare(editedSpy.count, 0);
            compare(editor._edit.Accessible.readOnly, true);
            // It can still be selected and moved through.
            keyClick(Qt.Key_A, Qt.ControlModifier);
            compare(editor._edit.selectedText, "keep me");
            editor.readOnly = false;
            keyClick(Qt.Key_End);
            keyClick("!");
            compare(editor.text, "keep me!");
        }

        // ---- The caret and the view ----

        function test_cursor_api() {
            editor.text = numbered(10);
            compare(editor.cursorLine, 1);
            compare(editor.cursorColumn, 1);
            editor.cursorLine = 4;
            editor.cursorColumn = 3;
            compare(editor._edit.cursorPosition, editor._core.positionOfLine(3, 2));
            compare(editor.cursorLine, 4);
            compare(editor.cursorColumn, 3);
            movedSpy.clear();
            editor._edit.cursorPosition = 0;
            compare(editor.cursorLine, 1);
            compare(editor.cursorColumn, 1);
            verify(movedSpy.count >= 1);
            editor.cursorLine = 999;
            compare(editor.cursorLine, 10, "a line past the end is the last line");
        }

        function test_scroll_to_line() {
            editor.text = numbered(800);
            editor.scrollToLine(600);
            tryVerify(() => editor.firstVisibleLine <= 600 && 600 <= editor.lastVisibleLine);
            verify(editor.firstVisibleLine > 1);
            editor.scrollToLine(1);
            tryVerify(() => editor.firstVisibleLine === 1);
            const first = editor.firstVisibleLine;
            editor.scrollToLine(2);
            compare(editor.firstVisibleLine, first, "a line in view does not move the text");
        }

        // ---- setTextPreserving ----

        function test_set_text_preserving_keeps_caret_and_scroll() {
            const before = numbered(2000);
            editor.text = before;
            focusEditor();
            editor.cursorLine = 50;
            editor.cursorColumn = 3;
            editor.scrollToLine(900);
            tryVerify(() => editor.firstVisibleLine > 800);
            const first = editor.firstVisibleLine;
            const lines = before.split("\n");
            lines[999] = "line 1000 was changed by the assistant";
            lines.splice(1500, 1);
            const after = lines.join("\n");
            editedSpy.clear();
            editor.setTextPreserving(after);
            compare(editor.text, after);
            compare(editor.cursorLine, 50);
            compare(editor.cursorColumn, 3);
            compare(editor.firstVisibleLine, first, "the same first line is in view");
            compare(editor.canUndo, false);
            compare(editor.modified, true);
            compare(editedSpy.count, 0, "an outside edit is not textEdited");
        }

        function test_set_text_preserving_with_lines_added_above_the_view() {
            editor.text = numbered(600);
            focusEditor();
            editor.cursorLine = 10;
            editor.cursorColumn = 4;
            editor.scrollToLine(400);
            tryVerify(() => editor.firstVisibleLine > 300);
            const first = editor.firstVisibleLine;
            editor.setTextPreserving("new 1\nnew 2\nnew 3\n" + numbered(600));
            compare(editor.cursorLine, 10);
            compare(editor.cursorColumn, 4);
            compare(editor.firstVisibleLine, first);
            compare(editor.lineCount, 603);
        }

        function test_set_text_preserving_clamps_and_keeps_the_selection() {
            editor.text = "alpha\nbeta\ngamma\ndelta";
            focusEditor();
            editor._edit.select(6, 16);
            editor.setTextPreserving("alpha\nbeta\ngamma\ndelta\nepsilon");
            compare(editor._edit.selectionStart, 6);
            compare(editor._edit.selectionEnd, 16);
            editor.cursorLine = 5;
            editor.cursorColumn = 4;
            editor.setTextPreserving("a\nb");
            compare(editor.cursorLine, 2, "the caret goes to the last line");
            compare(editor.cursorColumn, 2, "and to the end of it");
            compare(editor.text, "a\nb");
            editor.setTextPreserving("a\nb");
            compare(editor.text, "a\nb", "the same text again changes nothing");
        }

        function test_set_text_preserving_does_not_cut_a_surrogate_pair() {
            editor.text = "x😀y";
            editor.setTextPreserving("x😁y");
            compare(editor.text, "x😁y");
        }

        function test_set_text_preserving_streaming() {
            // Text grows a few lines at a time, as an assistant writes it.
            editor.text = "";
            focusEditor();
            let s = "";
            for (let i = 1; i <= 200; ++i) {
                s += "line " + i + "\n";
                if (i % 5 === 0) {
                    editor.setTextPreserving(s);
                }
            }
            compare(editor.text, s);
            compare(editor.lineCount, 201);
            compare(editor.cursorLine, 1);
        }

        // ---- Marks ----

        function test_marks() {
            editor.text = numbered(30);
            editor.markLines([3, [5, 6], {
                    "first": 8,
                    "last": 9
                }], TelamonCodeEditor.Added);
            compare(editor._core.markCount(), 3);
            const spans = editor._core.markSpans();
            compare(spans[0].first, 3);
            compare(spans[1].last, 6);
            compare(spans[2].first, 8);
            compare(spans[0].kind, TelamonCodeEditor.Added);
            editor.markLines([[12, 14]], TelamonCodeEditor.Changed);
            compare(editor._core.markCount(), 4);
            compare(editor._core.markSpans()[3].kind, TelamonCodeEditor.Changed);
            editor.clearMarks();
            compare(editor._core.markCount(), 0);
        }

        function test_marks_ignore_nonsense() {
            editor.text = numbered(10);
            editor.markLines([0, -3, "x", null, [], [1e12], [20, 30], 1e300, {}, {
                        "first": "a"
                    }], TelamonCodeEditor.Added);
            compare(editor._core.markCount(), 0);
            editor.markLines([[9, 2], [8, 99]], TelamonCodeEditor.Added);
            compare(editor._core.markCount(), 2);
            compare(editor._core.markSpans()[0].first, 2, "a reversed range is read the other way round");
            compare(editor._core.markSpans()[1].last, 10, "a range past the end stops at the last line");
            editor.markLines([1], 99);
            compare(editor._core.markSpans()[2].kind, TelamonCodeEditor.Changed, "an unknown kind is clamped");
            editor.clearMarks();
            const many = [];
            for (let i = 0; i < 30000; ++i) {
                many.push(1);
            }
            editor.markLines(many, TelamonCodeEditor.Added);
            verify(editor._core.markCount() <= 10000, "the number of marks is bounded");
        }

        function test_marks_follow_edits_and_go_with_a_new_text() {
            editor.text = numbered(20);
            focusEditor();
            editor.markLines([[5, 6]], TelamonCodeEditor.Added);
            editor.cursorLine = 1;
            editor.cursorColumn = 1;
            keyClick(Qt.Key_Return);
            compare(editor._core.markSpans()[0].first, 6);
            compare(editor._core.markSpans()[0].last, 7);
            editor.text = numbered(20);
            compare(editor._core.markCount(), 0, "loading a text clears the marks");
        }

        function test_marks_fade_out() {
            editor.text = numbered(10);
            editor.markLines([2], TelamonCodeEditor.Added, 200);
            compare(editor._core.markCount(), 1);
            tryVerify(() => editor._core.markCount() === 0, 3000);
            editor.markFadeDuration = 150;
            editor.markLines([3], TelamonCodeEditor.Changed);
            compare(editor._core.markCount(), 1);
            tryVerify(() => editor._core.markCount() === 0, 3000);
            // Reduced motion: no fading, the mark stays as it is and then goes.
            editor._core.animateMarks = false;
            editor.markLines([3], TelamonCodeEditor.Changed, 250);
            wait(100);
            compare(editor._core.markCount(), 1);
            tryVerify(() => editor._core.markCount() === 0, 3000);
            editor.markLines([4], TelamonCodeEditor.Changed, 0);
            wait(300);
            compare(editor._core.markCount(), 1, "without a fade the mark stays");
        }

        function test_marks_are_drawn() {
            editor.text = numbered(12);
            editor.highlightCurrentLine = false;
            editor.markLines([3], TelamonCodeEditor.Added);
            editor.markLines([6], TelamonCodeEditor.Changed);
            wait(100);
            const img = grabImage(editor);
            const body = editor._edit;
            function pixelAt(line) {
                const y = Math.round(editor._core.lineTopY(line - 1) + body.topPadding + editor._core.lineHeight(line - 1) / 2);
                return img.pixel(editor.width - 30, y + 1);
            }
            const plain = pixelAt(1);
            verify(pixelAt(3) !== plain, "a marked line has a band");
            verify(pixelAt(6) !== plain);
            verify(pixelAt(3) !== pixelAt(6), "the two kinds differ");
            compare(pixelAt(2), plain);
        }

        // ---- Caps ----

        function test_size_cap() {
            compare(editor.maximumSize, 1024 * 1024);
            editor.maximumSize = 2048;
            const big = numbered(400);
            verify(big.length > 2048);
            editor.text = big;
            compare(editor.tooLarge, true);
            compare(editor._core.tooLargeReason, 1);
            compare(editor.text, big, "the text is kept as it came");
            compare(editor._edit.length, 0, "the text field never holds it");
            compare(editor.modified, false);
            compare(editor.lineCount, 400);
            editor.forceActiveFocus();
            tryVerify(() => editor.activeFocus);
            keyClick("x");
            compare(editor.text, big, "a text over the limit is read-only");
            editor.cursorLine = 100;
            tryCompare(editor, "cursorLine", 100);
            editor.scrollToLine(390);
            editor.markLines([3], TelamonCodeEditor.Added);
            compare(editor._core.markCount(), 0);
            // A text of the right size is editable again.
            editor.text = "small";
            compare(editor.tooLarge, false);
            compare(editor._edit.cursorPosition, 0, "the caret starts at the top of a new text");
            focusEditor();
            compare(editor._edit.cursorPosition, 0, "and the focus does not move it");
            keyClick("x");
            compare(editor.text, "xsmall");
            // The limit is judged again when it changes.
            const bigger = numbered(900);
            verify(bigger.length > 4096);
            editor.maximumSize = 4096;
            editor.text = bigger;
            compare(editor.tooLarge, true);
            editor.maximumSize = 1024 * 1024;
            compare(editor.tooLarge, false);
            compare(editor.text, bigger);
        }

        function test_set_text_preserving_with_the_size_cap() {
            editor.maximumSize = 2048;
            editor.text = "a\nb";
            const big = numbered(400);
            editor.setTextPreserving(big);
            compare(editor.tooLarge, true);
            compare(editor.text, big);
            editor.setTextPreserving("c");
            compare(editor.tooLarge, false);
            compare(editor.text, "c");
        }

        function test_a_very_long_line_is_not_edited() {
            const line = "x".repeat(250000);
            editor.text = "head\n" + line + "\ntail";
            compare(editor.tooLarge, true);
            compare(editor._core.tooLargeReason, 2);
            compare(editor.text.length, 5 + 250000 + 5);
            editor.text = "head\n" + "x".repeat(100000) + "\ntail";
            compare(editor.tooLarge, false);
        }

        function test_a_big_text_over_the_limit_does_not_stall_the_window() {
            const chunk = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcde\n";
            const big = chunk.repeat(Math.ceil(12 * 1024 * 1024 / chunk.length));
            const t0 = Date.now();
            editor.text = big;
            const took = Date.now() - t0;
            console.warn("a", Math.round(big.length / 1048576), "MiB text over the limit set in", took, "ms");
            compare(editor.tooLarge, true);
            verify(took < 3000, "setting it took " + took + " ms");
            compare(editor.text.length, big.length);
        }

        function test_a_big_text_is_loaded_in_slices() {
            const chunk = "    int value = compute(123, \"text\") + other(a, b, c); // comment\n";
            const text = chunk.repeat(Math.ceil(900 * 1024 / chunk.length));
            editor.fileName = "a.cpp";
            const loadedSpy = createTemporaryObject(spyComp, root, {
                "target": editor,
                "signalName": "loaded"
            });
            const t0 = Date.now();
            editor.text = text;
            const returned = Date.now() - t0;
            compare(editor.loading, true);
            compare(editor.text, text, "the text is the caller's from the start");
            compare(editor.lineCount, text.split("\n").length);
            compare(editor.modified, false);
            focusEditor();
            keyClick("x");
            compare(editor.text, text, "read-only while it loads");
            tryVerify(() => !editor.loading, 60000);
            const total = Date.now() - t0;
            console.warn("900 KiB C++ text: set returned in", returned, "ms, all in the editor after", total, "ms");
            verify(returned < 250, "setting it took " + returned + " ms");
            compare(loadedSpy.count, 1);
            compare(editor.text, text);
            compare(editor.modified, false);
            compare(editor.canUndo, false);
            keyClick("x");
            compare(editor.text, "x" + text, "editable when it is loaded");
            compare(editor.modified, true);
        }

        function test_loading_is_replaced_by_the_next_text() {
            const chunk = "    int value = compute(123, \"text\") + other(a, b, c); // comment\n";
            editor.text = chunk.repeat(8000);
            compare(editor.loading, true);
            editor.text = "short";
            compare(editor.loading, false);
            compare(editor.text, "short");
            editor.text = chunk.repeat(8000);
            compare(editor.loading, true);
            const next = chunk.repeat(9000);
            editor.setTextPreserving(next);
            compare(editor.text, next);
            tryVerify(() => !editor.loading, 30000);
            compare(editor.text, next);
            compare(editor.lineCount, 9001);
            editor.text = chunk.repeat(8000);
            editor.markLines([1], TelamonCodeEditor.Added);
            compare(editor._core.markCount(), 0, "marks wait for the text");
            editor.text = "";
            compare(editor.loading, false);
        }

        // ---- Highlighting ----

        function test_language_and_file_name() {
            editor.text = "int main() { return 0; } // done";
            compare(editor.syntaxName, "");
            compare(runs(0).length, 0, "no language, no colours");
            editor.fileName = "src/main.cpp";
            compare(editor.syntaxName, "C++");
            const cpp = runs(0);
            verify(cpp.length > 1);
            const colours = new Set(cpp.map(r => r.color));
            verify(colours.size >= 2, "keywords and comments differ");
            editor.language = "Rust";
            compare(editor.syntaxName, "Rust", "the language wins over the file name");
            editor.language = "no such language";
            compare(editor.syntaxName, "C++", "an unknown language falls back to the file name");
            editor.language = "python";
            compare(editor.syntaxName, "Python", "any case");
            editor.language = "rs";
            compare(editor.syntaxName, "Rust", "an extension");
            editor.language = "";
            editor.fileName = "";
            compare(editor.syntaxName, "");
            compare(runs(0).length, 0);
            editor.fileName = "Cargo.toml";
            compare(editor.syntaxName, "TOML");
            editor.fileName = "../../etc/Makefile";
            compare(editor.syntaxName, "Makefile");
        }

        function test_colours_come_from_the_theme() {
            editor.fileName = "a.py";
            editor.text = "def f():\n    return 1  # note\n";
            const first = runs(0);
            verify(first.length > 0);
            const palette = editor._syntaxPalette;
            const keyword = first.find(r => r.start === 0);
            verify(keyword, "def is coloured");
            compare(keyword.color, Qt.color(palette.keyword.color).toString().replace(/^#ff/, "#"), "the colour of a keyword");
            const second = runs(1);
            const comment = second[second.length - 1];
            compare(comment.italic, true, "a comment is italic");
            compare(comment.color, Qt.color(palette.comment.color).toString().replace(/^#ff/, "#"));
        }

        function test_a_long_line_is_not_highlighted() {
            editor.fileName = "a.cpp";
            const pad = n => " ".repeat(n);
            editor.text = "int a = 1;" + pad(3900) + "\nint b = 2;" + pad(4100) + "\nint c = 3;\n";
            verify(runs(0).length > 0, "a line of 3,910 characters is highlighted");
            compare(runs(1).length, 0, "a line of 4,111 characters is left plain");
            verify(runs(2).length > 0, "the line after it is highlighted, in the state it started in");
        }

        function test_highlighting_state_crosses_lines_and_follows_edits() {
            editor.fileName = "a.cpp";
            editor.text = "int a;\n/* comment\nstill comment */\nint b;\n";
            const commentLine = runs(2);
            verify(commentLine.length > 0, "a block comment carries over its lines");
            const inside = commentLine[0];
            focusEditor();
            editor.cursorLine = 2;
            editor.cursorColumn = 1;
            // Delete the comment's opening: the next line is code again.
            keyClick(Qt.Key_Delete);
            keyClick(Qt.Key_Delete);
            editor._core.highlightNow();
            const after = editor._core.formatRuns(2);
            verify(after.length === 0 || after[0].color !== inside.color || after[0].italic !== inside.italic, "the line after the edit is read again");
        }

        function test_highlighting_is_lazy() {
            editor.fileName = "a.cpp";
            const chunk = "int value_1 = compute(1, \"text\") + other(a, b); // comment\nif (x) { return value; }\n";
            const text = chunk.repeat(11000);
            editor.maximumSize = 4 * 1024 * 1024;
            const t0 = Date.now();
            editor.text = text;
            console.warn("22,000 lines of C++ set (returned) in", Date.now() - t0, "ms");
            tryVerify(() => !editor.loading, 60000);
            console.warn("22,000 lines of C++ all in the editor after", Date.now() - t0, "ms");
            // The first lines are coloured soon.
            tryVerify(() => editor._core.formatRuns(3).length > 0, 5000);
            // Far lines are not read until the view gets there.
            compare(editor._core.formatRuns(20000).length, 0, "a line far below the view is not coloured yet");
            editor.scrollToLine(20000);
            tryVerify(() => editor._core.formatRuns(19999).length > 0, 60000);
        }

        function test_loading_and_highlighting_do_not_hold_the_window() {
            editor.fileName = "a.cpp";
            const chunk = "int value_1 = compute(1, \"text\") + other(a, b); // comment\nif (x) { return value; }\n";
            const text = chunk.repeat(11000);
            editor.maximumSize = 4 * 1024 * 1024;
            ticker.reset();
            ticker.running = true;
            editor.text = text;
            tryVerify(() => !editor.loading, 60000);
            editor.scrollToLine(21500);
            tryVerify(() => editor._core.formatRuns(21499).length > 0, 60000);
            ticker.running = false;
            console.warn("longest gap between 10 ms ticks while 22,000 lines were loaded and read:", ticker.longest, "ms in", ticker.ticks, "ticks");
            verify(ticker.ticks > 10, "the event loop kept running");
            verify(ticker.longest < 400, "the longest gap was " + ticker.longest + " ms");
        }

        Timer {
            id: ticker
            interval: 10
            repeat: true
            property real last: 0
            property real longest: 0
            property int ticks: 0
            function reset() {
                last = 0;
                longest = 0;
                ticks = 0;
            }
            onRunningChanged: if (running) last = Date.now()
            onTriggered: {
                const now = Date.now();
                longest = Math.max(longest, now - last);
                last = now;
                ++ticks;
            }
        }


        // ---- Keys ----

        function test_tab_indents_and_shift_tab_outdents() {
            editor.text = "a\nb\nc";
            focusEditor();
            editor.cursorLine = 1;
            editor.cursorColumn = 1;
            keyClick(Qt.Key_Tab);
            compare(editor.text, "    a\nb\nc");
            compare(editor.cursorColumn, 5);
            keyClick(Qt.Key_A, Qt.ControlModifier);
            keyClick(Qt.Key_Tab);
            compare(editor.text, "        a\n    b\n    c", "every selected line is indented");
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(editor.text, "    a\nb\nc", "and outdented");
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(editor.text, "a\nb\nc");
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(editor.text, "a\nb\nc", "nothing to remove");
            // One undo takes the whole indentation back.
            keyClick(Qt.Key_A, Qt.ControlModifier);
            keyClick(Qt.Key_Tab);
            keyClick(Qt.Key_Z, Qt.ControlModifier);
            compare(editor.text, "a\nb\nc");
        }

        function test_tab_aligns_to_the_tab_stop_and_can_insert_tabs() {
            editor.text = "ab";
            focusEditor();
            editor.cursorLine = 1;
            editor.cursorColumn = 3;
            keyClick(Qt.Key_Tab);
            compare(editor.text, "ab  ", "to the next multiple of the width");
            editor.tabWidth = 2;
            editor.text = "x";
            focusEditor();
            editor.cursorColumn = 2;
            keyClick(Qt.Key_Tab);
            compare(editor.text, "x ");
            editor.insertSpaces = false;
            editor.text = "x";
            focusEditor();
            editor.cursorColumn = 2;
            keyClick(Qt.Key_Tab);
            compare(editor.text, "x\t");
            editor.text = "a\n\nb";
            focusEditor();
            keyClick(Qt.Key_A, Qt.ControlModifier);
            keyClick(Qt.Key_Tab);
            compare(editor.text, "\ta\n\n\tb", "an empty line gets no indentation");
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(editor.text, "a\n\nb");
        }

        function test_escape_then_tab_leaves_the_editor() {
            editor.text = "a";
            focusEditor();
            keyClick(Qt.Key_Escape);
            keyClick(Qt.Key_Tab);
            compare(editor.text, "a", "the tab after Escape moves the focus, it does not indent");
            focusEditor();
            keyClick(Qt.Key_Tab);
            compare(editor.text, "    a");
        }

        function test_home_goes_to_the_first_character_then_the_start() {
            editor.text = "    foo(bar)\n\t\n  x";
            focusEditor();
            editor.cursorLine = 1;
            editor.cursorColumn = 12;
            keyClick(Qt.Key_Home);
            compare(editor.cursorColumn, 5);
            keyClick(Qt.Key_Home);
            compare(editor.cursorColumn, 1);
            keyClick(Qt.Key_Home);
            compare(editor.cursorColumn, 5);
            keyClick(Qt.Key_Home, Qt.ShiftModifier);
            compare(editor.cursorColumn, 1);
            compare(editor._edit.selectedText, "    ");
            editor.cursorLine = 2;
            editor.cursorColumn = 2;
            keyClick(Qt.Key_Home);
            compare(editor.cursorColumn, 1, "on a blank line");
            editor.cursorLine = 3;
            keyClick(Qt.Key_End);
            keyClick(Qt.Key_Home);
            compare(editor.cursorColumn, 3);
        }

        function test_select_all_and_copy() {
            editor.text = "one\ntwo";
            focusEditor();
            keyClick(Qt.Key_A, Qt.ControlModifier);
            compare(editor._edit.selectedText, "one\ntwo");
            editor.selectAll();
        }

        // ---- The look ----

        function test_accessible() {
            compare(editor._edit.Accessible.role, Accessible.EditableText);
            compare(editor._edit.Accessible.name, "Code editor");
            compare(editor.Accessible.ignored, true);
            editor.Accessible.name = "main.rs";
            compare(editor._edit.Accessible.name, "main.rs");
        }

        function test_wrap_and_line_numbers() {
            editor.text = "a short line\n" + "word ".repeat(300) + "\nlast";
            editor.wrap = true;
            wait(50);
            verify(editor._edit.contentHeight > 4 * editor._core.lineHeight(0));
            verify(editor._edit.width <= editor.width, "wrapped text is as wide as the view");
            editor.showLineNumbers = false;
            editor.wrap = false;
            compare(editor.lineCount, 3);
        }
    }
}
