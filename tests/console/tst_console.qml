import QtQuick
import QtTest
import Telamon.Ui

// TelamonConsoleView: append and clear, the bound on the lines (also for 100,000
// at once), partial lines and \r, colours reaching the layout, plain text only,
// follow-tail, selection and copy, the keys, the disabled state.
Item {
    id: root
    width: 640
    height: 320

    Component {
        id: viewComp
        TelamonConsoleView {
            width: 600
            height: 300
        }
    }

    TestCase {
        id: tc
        name: "TelamonConsoleView"
        when: windowShown

        property var view: null

        function init() {
            view = createTemporaryObject(viewComp, root);
            verify(view);
        }

        function sink() {
            return view._sink;
        }
        function esc(s) {
            return s.replace(/\^/g, "\u001b");
        }
        // The visible lines of a long run: "line 0\n" ... "line n-1\n".
        function lines(n, prefix) {
            let s = "";
            for (let i = 0; i < n; ++i) {
                s += (prefix || "line ") + i + "\n";
            }
            return s;
        }
        function atEnd() {
            const f = view._flick;
            return f.contentY >= Math.max(0, f.contentHeight + f.bottomMargin - f.height) - 1.5;
        }
        function waitEnd() {
            tryVerify(() => atEnd());
        }
        // The wheel starts a flick: wait until the view stands still.
        function settle() {
            let last = -1;
            for (let i = 0; i < 60; ++i) {
                wait(40);
                const y = view._flick.contentY;
                if (Math.abs(y - last) < 0.01) {
                    return;
                }
                last = y;
            }
        }
        function wheel(dy) {
            mouseWheel(view, 100, 100, 0, dy);
            settle();
        }

        // ---- text

        function test_append_and_clear() {
            compare(view.lineCount, 0);
            compare(view.plainText(), "");
            view.append("hello\nworld");
            compare(view.plainText(), "hello\nworld");
            compare(view.lineCount, 2);
            view.append("!\n");
            compare(view.plainText(), "hello\nworld!\n");
            // the empty line after the final newline is not a line
            compare(view.lineCount, 2);
            view.append("x");
            compare(view.lineCount, 3);
            view.clear();
            compare(view.plainText(), "");
            compare(view.lineCount, 0);
            view.append("again");
            compare(view.plainText(), "again");
            compare(view.lineCount, 1);
        }

        function test_lineCount_signal() {
            const spy = createTemporaryObject(spyComp, root, {target: view, signalName: "lineCountChanged"});
            view.append("a\n");
            compare(spy.count, 1);
            view.append("b");
            compare(spy.count, 2);
            view.append("c");
            compare(spy.count, 2);
            view.clear();
            compare(spy.count, 3);
        }

        Component {
            id: spyComp
            SignalSpy {}
        }

        function test_partial_last_line_extends() {
            view.append("par");
            view.append("tial ");
            view.append("line\nnext");
            compare(view.plainText(), "partial line\nnext");
            compare(sink().lineText(0), "partial line");
            compare(view.lineCount, 2);
        }

        function test_partial_line_keeps_and_extends_colours() {
            view.append("^[31mab".replace("^", "\u001b"));
            view.append("cd");
            view.append("^[0mef\u001b[32mgh\n".replace("^", "\u001b"));
            compare(view.plainText(), "abcdefgh\n");
            const runs = sink().runsAt(0);
            compare(runs.length, 2);
            compare(runs[0].start, 0);
            compare(runs[0].length, 4);
            compare(runs[0].fg, 1);
            compare(runs[1].start, 6);
            compare(runs[1].length, 2);
            compare(runs[1].fg, 2);
            // and the layout holds them for the right block
            const f = sink().formatsAt(0);
            compare(f.length, 2);
            compare(f[0].start, 0);
            compare(f[0].length, 4);
            compare(f[1].start, 6);
        }

        function test_formats_follow_their_block() {
            // many lines in many appends: each block keeps its own colours, none leak to the next
            for (let i = 0; i < 40; ++i) {
                view.append(i % 2 === 0 ? "\u001b[31mred " + i : "plain " + i);
                view.append(i % 3 === 0 ? "\u001b[0m tail\n" : "\n");
            }
            for (let b = 0; b < 40; ++b) {
                const r = sink().runsAt(b);
                const f = sink().formatsAt(b);
                compare(f.length, r.length, "block " + b);
            }
            compare(sink().formatsAt(1).length > 0, sink().runsAt(1).length > 0);
        }

        function test_cr_rewrites_the_last_line() {
            view.append("one\ntwo\r");
            view.append("three");
            compare(view.plainText(), "one\nthree");
            view.append("\r\nfour\rfive\r\r\nsix\n");
            compare(view.plainText(), "one\nthree\nfive\nsix\n");
            view.clear();
            for (let i = 0; i <= 100; i += 10) {
                view.append("progress " + i + "%\r");
            }
            view.append("done\n");
            compare(view.plainText(), "done\n");
        }

        function test_cr_clears_the_colours_of_the_line() {
            view.append("\u001b[31mred\r\u001b[32mgreen");
            compare(view.plainText(), "green");
            const runs = sink().runsAt(0);
            compare(runs.length, 1);
            compare(runs[0].fg, 2);
            compare(runs[0].length, 5);
            compare(sink().formatsAt(0).length, 1);
        }

        function test_long_lines_split_at_4096() {
            view.append("a".repeat(5000));
            compare(view.lineCount, 2);
            compare(sink().lineText(0).length, 4096);
            compare(sink().lineText(1).length, 904);
            view.append("b".repeat(4000));
            compare(view.lineCount, 3);
            compare(view.plainText().replace(/\n/g, "").length, 9000);
        }

        // ---- the bound

        function test_maximumLines_bound() {
            view.maximumLines = 100;
            for (let i = 0; i < 250; ++i) {
                view.append("line " + i + "\n");
                verify(view.lineCount <= 100, "after line " + i);
            }
            compare(view.lineCount, 100);
            const t = view.plainText().split("\n");
            compare(t[0], "line 150");
            compare(t[99], "line 249");
            compare(t.length, 101);
            // sink and document agree
            compare(sink().blockCount(), 101);
        }

        function test_maximumLines_with_a_partial_last_line() {
            view.maximumLines = 2;
            view.append("a\nb\nc");
            compare(view.plainText(), "b\nc");
            view.append("d\ne");
            compare(view.plainText(), "cd\ne");
            compare(view.lineCount, 2);
            view.append("\n");
            compare(view.plainText(), "cd\ne\n");
            view.append("f\n");
            compare(view.plainText(), "e\nf\n");
            compare(view.lineCount, 2);
        }

        function test_maximumLines_one_and_bad_values() {
            view.maximumLines = 1;
            view.append("a\nb\nc\n");
            compare(view.plainText(), "c\n");
            compare(view.lineCount, 1);
            view.maximumLines = 0;
            view.append("d\ne\n");
            compare(view.lineCount, 1);
            compare(view.plainText(), "e\n");
            view.maximumLines = -7;
            view.append("f\n");
            compare(view.plainText(), "f\n");
        }

        function test_maximumLines_change_trims_at_once() {
            view.append(lines(50));
            compare(view.lineCount, 50);
            view.maximumLines = 10;
            compare(view.lineCount, 10);
            compare(view.plainText().split("\n")[0], "line 40");
            view.maximumLines = 1000;
            compare(view.lineCount, 10);
        }

        function test_colours_survive_trimming() {
            view.maximumLines = 5;
            for (let i = 0; i < 30; ++i) {
                view.append("\u001b[3" + (1 + i % 6) + "mc" + i + "\u001b[0m\n");
            }
            compare(view.lineCount, 5);
            for (let b = 0; b < 5; ++b) {
                const n = 25 + b;
                compare(sink().lineText(b), "c" + n);
                const r = sink().runsAt(b);
                compare(r.length, 1);
                compare(r[0].fg, 1 + n % 6);
                compare(sink().formatsAt(b).length, 1);
            }
        }

        function bigText(coloured) {
            let s = "";
            for (let i = 0; i < 100000; ++i) {
                s += (coloured ? "\u001b[32mline " + i + "\u001b[0m some output text\n" : "line " + i + " some output text\n");
            }
            return s;
        }

        function test_100k_lines_in_one_append() {
            const big = bigText(true);
            const t0 = Date.now();
            view.append(big);
            const ms = Date.now() - t0;
            console.info("100,000 lines, one append(): " + ms + " ms");
            compare(view.lineCount, 10000);
            verify(ms < 4000, "took " + ms + " ms");
            compare(sink().lineText(0), "line 90000 some output text");
            compare(sink().lineText(9999), "line 99999 some output text");
            compare(sink().runsAt(5).length, 1);
            compare(sink().blockCount(), 10001);
        }

        function test_100k_lines_in_4k_chunks() {
            const big = bigText(true);
            const t0 = Date.now();
            for (let p = 0; p < big.length; p += 4096) {
                view.append(big.substr(p, 4096));
                if (view.lineCount > 10000) {
                    fail("over the bound at " + p);
                }
            }
            const ms = Date.now() - t0;
            console.info("100,000 lines, " + Math.ceil(big.length / 4096) + " appends of 4 KiB: " + ms + " ms");
            compare(view.lineCount, 10000);
            verify(ms < 8000, "took " + ms + " ms");
            // the chunks cut escape sequences, lines and the colours: the result is the same
            compare(sink().lineText(0), "line 90000 some output text");
            compare(sink().lineText(9999), "line 99999 some output text");
            let coloured = 0;
            for (let b = 0; b < 10000; b += 997) {
                coloured += sink().runsAt(b).length;
            }
            compare(coloured, 11);
        }

        function test_100k_lines_the_same_either_way() {
            const big = bigText(false).substr(0, 600000);
            view.append(big);
            const whole = view.plainText();
            view.clear();
            for (let p = 0; p < big.length; p += 777) {
                view.append(big.substr(p, 777));
            }
            compare(view.plainText(), whole);
        }

        // ---- colours

        function test_ansi_colours_reach_the_layout_data() {
            const rows = [];
            for (let i = 0; i < 8; ++i) {
                rows.push({tag: "fg " + (30 + i), seq: "\u001b[" + (30 + i) + "m", fg: i, bg: -1});
                rows.push({tag: "fg bright " + (90 + i), seq: "\u001b[" + (90 + i) + "m", fg: 8 + i, bg: -1});
                rows.push({tag: "bg " + (40 + i), seq: "\u001b[" + (40 + i) + "m", fg: -1, bg: i});
                rows.push({tag: "bg bright " + (100 + i), seq: "\u001b[" + (100 + i) + "m", fg: -1, bg: 8 + i});
            }
            rows.push({tag: "256 bright red", seq: "\u001b[38;5;196m", fg: 9, bg: -1});
            rows.push({tag: "256 green", seq: "\u001b[38;5;34m", fg: 2, bg: -1});
            rows.push({tag: "256 grey", seq: "\u001b[38;5;244m", fg: 20, bg: -1});
            rows.push({tag: "256 bg blue", seq: "\u001b[48;5;19m", fg: -1, bg: 4});
            rows.push({tag: "truecolour green", seq: "\u001b[38;2;0;200;0m", fg: 2, bg: -1});
            rows.push({tag: "truecolour pale yellow", seq: "\u001b[38;2;255;240;120m", fg: 11, bg: -1});
            rows.push({tag: "truecolour grey", seq: "\u001b[38;2;128;128;128m", fg: 20, bg: -1});
            rows.push({tag: "truecolour bg magenta", seq: "\u001b[48;2;180;0;180m", fg: -1, bg: 5});
            return rows;
        }
        function test_ansi_colours_reach_the_layout(data) {
            view.append(data.seq + "X\u001b[0m\n");
            const r = sink().runsAt(0);
            compare(r.length, 1);
            compare(r[0].fg, data.fg);
            compare(r[0].bg, data.bg);
            const f = sink().formatsAt(0);
            compare(f.length, 1);
            compare(f[0].start, 0);
            compare(f[0].length, 1);
            const surface = TelamonStyle.codeSurface;
            if (data.fg >= 0) {
                verify(Qt.colorEqual(f[0].foreground, sink().slotColor(data.fg)), "the slot's colour is the one drawn");
                verify(sink().contrast(f[0].foreground, surface) >= 4.5, "legible");
            }
            if (data.bg >= 0) {
                verify(f[0].background.a > 0, "has a background");
                verify(!Qt.colorEqual(f[0].background, surface), "tinted");
                const fg = f[0].foreground.valid ? f[0].foreground : TelamonStyle.text;
                verify(sink().contrast(fg, f[0].background) >= 4.5, "legible on the tint");
            }
        }

        function test_text_styles_reach_the_layout() {
            view.append("\u001b[1mb\u001b[0m\u001b[3mi\u001b[0m\u001b[4mu\u001b[0m\u001b[9ms\u001b[0m\u001b[2md\u001b[0m\u001b[7mr\u001b[0m\n");
            const f = sink().formatsAt(0);
            compare(f.length, 6);
            verify(f[0].bold);
            verify(f[1].italic);
            verify(f[2].underline);
            verify(f[3].strike);
            verify(f[4].foreground.valid, "dim has a colour");
            verify(f[5].background.valid && f[5].foreground.valid, "inverse swaps");
        }

        function test_palette_slots_are_legible() {
            for (let i = 0; i < 24; ++i) {
                verify(sink().contrast(sink().slotColor(i), TelamonStyle.codeSurface) >= 4.5, "slot " + i);
                compare(sink().slotColor(i).a, 1);
            }
        }

        function test_theme_change_redraws_every_line() {
            for (let i = 0; i < 20; ++i) {
                view.append("\u001b[31mred " + i + "\n");
            }
            const before = sink().formatsAt(7)[0].foreground;
            const pal = [];
            for (let i = 0; i < 16; ++i) {
                pal.push(Qt.rgba(0.1, 0.4, 0.1 + i / 40, 1));
            }
            sink().palette = pal;
            sink().surfaceColor = "#ffffff";
            sink().textColor = "#000000";
            sink().applyTheme();
            for (let b = 0; b < 20; ++b) {
                const f = sink().formatsAt(b);
                compare(f.length, 1);
                verify(!Qt.colorEqual(f[0].foreground, before), "line " + b);
            }
            compare(sink().runsAt(7)[0].fg, 1);
        }

        function test_high_contrast_has_no_colour() {
            view.append("\u001b[1;31;42mbold\u001b[0m \u001b[7minv\u001b[0m \u001b[4;3munder\u001b[0m\n");
            sink().highContrast = true;
            sink().applyTheme();
            const f = sink().formatsAt(0);
            compare(f.length, 3);
            for (const r of f) {
                verify(!r.foreground.valid && !r.background.valid, "no colour");
            }
            verify(f[0].bold);
            verify(f[1].bold && f[1].underline, "inverse is bold and underlined");
            verify(f[2].underline && f[2].italic);
            // the text itself is unchanged
            compare(view.plainText(), "bold inv under\n");
            sink().highContrast = false;
            sink().applyTheme();
            verify(sink().formatsAt(0)[0].foreground.valid);
        }

        // ---- what is stripped

        function noControls(s) {
            return !/[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069\u200b-\u200f\u061c\ufeff]/.test(s);
        }

        function test_no_escape_remains() {
            view.append("a\u001b[31mred\u001b[0m b\u001b]0;title\u0007c\u001b]8;;https://example.com\u001b\\link\u001b]8;;\u001b\\ d\u001b[2J\u001b[Hee\u009b32mf\u009d0;x\u0007g\n");
            compare(view.plainText(), "ared bclink deefg\n");
            verify(noControls(view.plainText()));
            verify(noControls(view.selectedText));
            view.selectAll();
            verify(noControls(view.selectedText));
        }

        function test_hostile_sequences_leave_plain_text_and_a_usable_view_data() {
            return [
                {tag: "osc 8 link", input: "\u001b]8;;file:///etc/passwd\u0007click\u001b]8;;\u0007"},
                {tag: "osc 52", input: "\u001b]52;c;ZWNobyBoaQ==\u0007"},
                {tag: "title", input: "\u001b]0;pwned\u001b\\"},
                {tag: "unterminated osc", input: "\u001b]0;" + "x".repeat(6000)},
                {tag: "dcs with esc", input: "\u001bP1$q\u001b[31m\u001b\\"},
                {tag: "cursor and erase", input: "\u001b[2J\u001b[H\u001b[1000A\u001b[?1049h\u001b[?25l\u001b[6n"},
                {tag: "many params", input: "\u001b[" + "1;".repeat(10000) + "m"},
                {tag: "huge number", input: "\u001b[99999999999999999999m"},
                {tag: "bel storm", input: "\u0007".repeat(5000)},
                {tag: "backspace and nul", input: "ab\b\b\b\u0000cd"},
                {tag: "bidi", input: "\u202eevil\u202c \u2066x\u2069 \u200e\u200f"},
                {tag: "lone surrogates", input: "\ud800 \udc00 \ud83d"},
                {tag: "esc at the end", input: "\u001b"},
                {tag: "csi at the end", input: "\u001b[3"},
                {tag: "c1", input: "\u009b31m\u009d0;t\u009c\u0090q\u009c\u0085"}
            ];
        }
        function test_hostile_sequences_leave_plain_text_and_a_usable_view(data) {
            view.append("before\n");
            view.append(data.input);
            view.append("\u001b\\\u0007");
            view.append("\nafter\n");
            const t = view.plainText();
            verify(noControls(t), "controls in " + JSON.stringify(t.substr(0, 80)));
            verify(t.startsWith("before\n"));
            verify(t.endsWith("\nafter\n"));
            verify(view.lineCount >= 2);
            // still usable
            view.append("ok\n");
            verify(view.plainText().endsWith("after\nok\n"));
        }

        function test_html_and_markdown_stay_literal() {
            const s = "<b>x</b> <a href=\"https://example.com\">l</a> &amp; **md** [l](https://example.com) # h\n<img src=x>\n";
            view.append(s);
            compare(view.plainText(), s);
            compare(view._edit.textFormat, TextEdit.PlainText);
            // selected, it is the text as typed
            view.selectAll();
            compare(view.selectedText, s.replace(/\n$/, "\n"));
        }

        // ---- follow

        function test_follows_the_end() {
            verify(view.follow);
            verify(view.following);
            view.append(lines(300));
            waitEnd();
            verify(view.following);
            verify(view._flick.contentY > 0);
            view.append(lines(100, "more "));
            waitEnd();
            verify(view.following);
        }

        function test_scrolling_up_stops_and_the_end_resumes() {
            view.append(lines(300));
            waitEnd();
            const end = view._flick.contentY;
            wheel(240);
            verify(view._flick.contentY < end, "the wheel moved the view");
            verify(!view.following);
            const y = view._flick.contentY;
            view.append(lines(50, "more "));
            wait(30);
            compare(view._flick.contentY, y, "not followed while scrolled up");
            verify(!view.following);
            // back to the end by the wheel
            for (let i = 0; i < 60 && !atEnd(); ++i) {
                wheel(-1200);
            }
            verify(atEnd());
            verify(view.following);
            view.append(lines(50, "last "));
            waitEnd();
            verify(view.following);
        }

        function test_scrollToEnd_resumes() {
            view.append(lines(300));
            waitEnd();
            wheel(600);
            verify(!view.following);
            view.scrollToEnd();
            verify(view.following);
            waitEnd();
            view.append(lines(20));
            waitEnd();
        }

        function test_follow_false_never_moves() {
            view.follow = false;
            view.append(lines(300));
            wait(30);
            compare(view._flick.contentY, 0);
            verify(!view.following);
            view.scrollToEnd();
            waitEnd();
            verify(!view.following, "follow is off");
            view.append(lines(30));
            wait(30);
            verify(!atEnd());
            view.follow = true;
            waitEnd();
            verify(view.following);
        }

        function test_clear_follows_again() {
            view.append(lines(300));
            waitEnd();
            wheel(600);
            verify(!view.following);
            view.clear();
            verify(view.following);
            compare(view._flick.contentY, 0);
            view.append(lines(300));
            waitEnd();
        }

        function test_trimming_keeps_what_the_view_shows_when_not_following() {
            view.maximumLines = 200;
            view.append(lines(200));
            waitEnd();
            wheel(1200);
            verify(!view.following);
            const f = view._flick;
            const e = view._edit;
            const shown = e.getText(e.positionAt(5, f.contentY + 1), e.positionAt(5, f.contentY + 1) + 8);
            view.append(lines(10, "new "));
            wait(30);
            const after = e.getText(e.positionAt(5, f.contentY + 1), e.positionAt(5, f.contentY + 1) + 8);
            compare(after, shown);
        }

        function test_keys_scroll() {
            view.append(lines(300));
            waitEnd();
            view._edit.forceActiveFocus();
            verify(view._edit.activeFocus);
            const end = view._flick.contentY;
            keyClick(Qt.Key_PageUp);
            verify(view._flick.contentY < end);
            verify(!view.following);
            const pageUp = view._flick.contentY;
            keyClick(Qt.Key_Up);
            verify(view._flick.contentY < pageUp);
            keyClick(Qt.Key_Down);
            compare(view._flick.contentY, pageUp);
            keyClick(Qt.Key_PageDown);
            verify(view._flick.contentY > pageUp);
            keyClick(Qt.Key_Home, Qt.ControlModifier);
            compare(view._flick.contentY, 0);
            keyClick(Qt.Key_End, Qt.ControlModifier);
            waitEnd();
            verify(view.following);
        }

        function test_select_all_does_not_scroll_the_view() {
            view.follow = false;
            view.append(lines(300));
            view._edit.forceActiveFocus();
            keyClick(Qt.Key_Home, Qt.ControlModifier);
            compare(view._flick.contentY, 0);
            keyClick(Qt.Key_A, Qt.ControlModifier);
            verify(view.selectedText.length > 0);
            view.append(lines(20, "more "));
            wait(30);
            compare(view._flick.contentY, 0);
        }

        // ---- selection and copy

        function test_selectAll_and_copy() {
            view.append("alpha\n\u001b[31mbeta\u001b[0m\ngamma");
            compare(view.selectedText, "");
            view.selectAll();
            compare(view.selectedText, "alpha\nbeta\ngamma");
            clipHelper.clear();
            view.copy();
            compare(clipHelper.text(), "alpha\nbeta\ngamma");
            verify(!clipHelper.hasHtml(), "plain text only");
        }

        function test_copy_without_selection_leaves_the_clipboard() {
            TelamonClipboard.setText("keep");
            view.append("text");
            view.copy();
            compare(TelamonClipboard.text(), "keep");
        }

        function test_ctrl_a_and_ctrl_c() {
            view.append("one\ntwo\n");
            view._edit.forceActiveFocus();
            keyClick(Qt.Key_A, Qt.ControlModifier);
            compare(view.selectedText, "one\ntwo\n");
            clipHelper.clear();
            keyClick(Qt.Key_C, Qt.ControlModifier);
            compare(clipHelper.text(), "one\ntwo\n");
            verify(!clipHelper.hasHtml());
        }

        function test_selection_by_mouse() {
            view.append("select this text\nsecond line\n");
            mousePress(view, 15, 20, Qt.LeftButton);
            mouseMove(view, 90, 20);
            mouseRelease(view, 90, 20, Qt.LeftButton);
            verify(view.selectedText.length > 0);
            verify("select this text".indexOf(view.selectedText) >= 0);
        }

        // ---- states and accessibility

        function test_disabled() {
            view.append("text\n");
            view.enabled = false;
            fuzzyCompare(view.opacity, 0.5, 0.01);
            view._edit.forceActiveFocus();
            verify(!view._edit.activeFocus);
            view.append("more\n");
            compare(view.plainText(), "text\nmore\n");
            view.enabled = true;
            compare(view.opacity, 1);
        }

        function test_accessible() {
            verify(view.Accessible.ignored);
            compare(view.Accessible.name, "Console output");
            compare(view._edit.Accessible.role, Accessible.EditableText);
            verify(view._edit.Accessible.readOnly);
            compare(view._edit.Accessible.name, "Console output");
            verify(view._edit.activeFocusOnTab);
            view.Accessible.name = "Build output";
            compare(view._edit.Accessible.name, "Build output");
        }

        function test_wrap() {
            view.append("word ".repeat(200) + "\n");
            verify(view._edit.contentWidth > view._flick.width);
            view.wrap = true;
            verify(view._edit.width <= view._flick.width + 0.5);
            verify(view._edit.contentHeight > view._edit.font.pixelSize * 3);
            view.wrap = false;
            verify(view._edit.width > view._flick.width);
        }
    }
}
