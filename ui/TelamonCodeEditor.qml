import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// An editable code editor: syntax highlighting by language or file name (the
// colours follow the Telamon theme, light, dark and high contrast), a
// line-number gutter, the monospace font, the caret's row tinted, and marks on
// lines an app changed (`markLines`). The text is plain: nothing in it is
// taken as HTML or Markdown. Lines are numbered from 1.
//
//   TelamonCodeEditor {
//       fileName: "main.rs"
//       text: source
//       onTextEdited: dirty = true
//   }
//
// `setTextPreserving(text)` replaces the text from outside (an assistant's
// edit that arrives while the user is reading) and keeps the caret, the
// selection and the scroll position. A text over `maximumSize` characters, or
// with a very long line, is shown read-only and plain in a viewer, under a
// note, so it never stalls the window. Tab and Shift+Tab indent and outdent;
// press Escape and then Tab to move the focus on instead. Screen readers get
// the text field, named "Code editor"; set Accessible.name on the editor to say
// which file it holds.
FocusScope {
    id: control

    // ---- The text ----
    // The whole text. Setting it loads a document: the undo history is
    // cleared and `modified` is false. Line breaks read back as "\n".
    property alias text: core.text
    // The text differs from what was loaded or last marked saved. Set it to
    // false when the app saves.
    property alias modified: core.modified
    property bool readOnly: false
    // A language name ("C++", "Rust", "python", "js") or an extension ("py");
    // when it names none, `fileName` is used.
    property alias language: core.language
    // A file name or path: its name and extension pick the language.
    property alias fileName: core.fileName
    // The name of the language in use ("" for plain text).
    readonly property string syntaxName: core.syntaxName

    // ---- The caret and the view ----
    // 1-based. Set them to move the caret.
    property int cursorLine: 1
    property int cursorColumn: 1
    readonly property int lineCount: core.lineCount
    readonly property int firstVisibleLine: _firstVisible
    readonly property int lastVisibleLine: _lastVisible
    readonly property bool canUndo: !core.tooLarge && edit.canUndo
    readonly property bool canRedo: !core.tooLarge && edit.canRedo

    // ---- Look and behaviour ----
    property bool showLineNumbers: true
    property bool highlightCurrentLine: true
    property bool wrap: false
    // The width of a tab, in characters.
    property int tabWidth: 4
    // Tab inserts spaces (true) or a tab character.
    property bool insertSpaces: true
    property bool framed: true
    // More text than this many characters is shown read-only and plain.
    property alias maximumSize: core.maximumSize
    // The text is shown read-only in the viewer, with a note.
    readonly property bool tooLarge: core.tooLarge
    // A big text is being put into the editor, a few lines at a time. It is
    // read-only until `loaded()`.
    readonly property bool loading: core.loading
    // How long `markLines` marks last by default: 0 keeps them until clearMarks().
    property int markFadeDuration: 0

    enum MarkKind {
        Added,
        Changed
    }

    // The user changed the text (typing, paste, drop, undo, indentation), not
    // the app.
    signal textEdited
    // The caret moved, by the user or the app.
    signal cursorMoved
    // A text that was loaded in slices is all in the editor.
    signal loaded

    // Replaces the text and keeps the caret, the selection and the scroll
    // position: only what differs is rewritten, the caret inside it goes to the
    // same line and column, and the view stays on the same first line. For
    // edits that arrive from outside while the text is shown. The undo history
    // is cleared, `modified` becomes true when the text differs and
    // `textEdited` is not emitted.
    function setTextPreserving(newText: string): void {
        if (core.tooLarge || !edit.visible) {
            control.text = newText;
            return;
        }
        const top = flick.contentY - edit.topPadding;
        const line = core.lineAtY(top);
        const inside = top - core.lineTopY(line);
        control._preserving = true;
        core.replacePreserving(newText);
        if (!core.tooLarge) {
            control._layoutNow();
            flick.contentY = control._clampY(core.lineTopY(Math.min(line, core.lineCount - 1)) + inside + edit.topPadding);
        }
        control._preserving = false;
        control._updateViewport();
    }

    // Marks lines with a gutter bar and a tinted band. `ranges` is a list of
    // line numbers (1-based), [first, last] pairs or {first, last} objects.
    // `kind` is TelamonCodeEditor.Added or .Changed. With `fadeMs` > 0 (default
    // `markFadeDuration`) the marks fade out after that long; under reduced
    // motion they stay as they are and then go.
    function markLines(ranges: var, kind: int, fadeMs: var): void {
        core.markLines(ranges, kind, fadeMs === undefined ? control.markFadeDuration : fadeMs);
    }
    function clearMarks(): void {
        core.clearMarks();
    }

    // Scrolls so that a line (1-based) is in view; a line already in view
    // does not move the text.
    function scrollToLine(n: int): void {
        const line = Math.max(1, Math.min(core.lineCount, Math.floor(n))) - 1;
        if (core.tooLarge) {
            view.ensureVisible(view.positionOfLine(line));
            return;
        }
        control._layoutNow();
        const top = core.lineTopY(line) + edit.topPadding;
        const height = core.lineHeight(line);
        const shown = flick.height - flick.bottomMargin;
        if (top >= flick.contentY && top + height <= flick.contentY + shown) {
            return;
        }
        flick.contentY = control._clampY(top - shown / 3);
    }

    function undo(): void {
        if (!core.tooLarge) {
            edit.undo();
        }
    }
    function redo(): void {
        if (!core.tooLarge) {
            edit.redo();
        }
    }
    function selectAll(): void {
        if (core.tooLarge) {
            view.selectAll();
        } else {
            edit.selectAll();
        }
    }
    function copy(): void {
        if (core.tooLarge) {
            view.copy();
        } else {
            edit.copy();
        }
    }

    // ---- Private ----
    readonly property QtObject _core: core
    readonly property Item _edit: edit
    property bool _byMouse: false
    property bool _preserving: false
    property bool _syncing: false
    property bool _tabEscapes: false
    property int _firstVisible: 1
    property int _lastVisible: 1
    readonly property bool _scrollsSideways: !control.wrap && flick.contentWidth > flick.width + 0.5
    readonly property real _barRoom: control._scrollsSideways ? hbar.implicitHeight : 0
    readonly property real _bodyTop: banner.height

    implicitWidth: Kirigami.Units.gridUnit * 30
    implicitHeight: Kirigami.Units.gridUnit * 16
    opacity: control.enabled ? 1 : 0.5
    activeFocusOnTab: false

    Accessible.ignored: true
    Accessible.name: qsTr("Code editor")

    // The text field lays its text out when asked where something is.
    function _layoutNow(): void {
        edit.positionToRectangle(edit.length);
    }

    // The text field moves its caret to the end when it becomes editable:
    // put it back.
    function _applyReadOnly(): void {
        const readOnly = control.readOnly || core.tooLarge || core.loading;
        if (edit.readOnly === readOnly) {
            return;
        }
        const anchor = edit.selectionStart === edit.selectionEnd || edit.cursorPosition === edit.selectionEnd ? edit.selectionStart : edit.selectionEnd;
        const cursor = edit.cursorPosition;
        edit.readOnly = readOnly;
        if (anchor === cursor) {
            edit.cursorPosition = cursor;
        } else {
            edit.select(anchor, cursor);
        }
    }
    onReadOnlyChanged: _applyReadOnly()

    function _clampY(y: real): real {
        return Math.max(0, Math.min(Math.max(0, flick.contentHeight + flick.bottomMargin - flick.height), y));
    }

    function _updateViewport(): void {
        if (core.tooLarge) {
            control._firstVisible = view.firstVisibleLine + 1;
            control._lastVisible = view.lastVisibleLine + 1;
            return;
        }
        const top = flick.contentY - edit.topPadding;
        core.setViewport(top, top + flick.height);
        control._firstVisible = core.lineAtY(top) + 1;
        control._lastVisible = core.lineAtY(top + flick.height - flick.bottomMargin) + 1;
    }

    // The editor's cursorLine and cursorColumn follow the caret; the other way
    // round they move it.
    function _readCursor(): void {
        control._syncing = true;
        if (core.tooLarge) {
            const p = view.cursorPosition;
            control.cursorLine = view.lineOf(p) + 1;
            control.cursorColumn = view.columnOf(p) + 1;
        } else {
            const p = edit.cursorPosition;
            control.cursorLine = core.lineOfPosition(p) + 1;
            control.cursorColumn = core.columnOfPosition(p) + 1;
        }
        control._syncing = false;
        control.cursorMoved();
    }
    function _applyCursor(): void {
        const line = Math.max(1, Math.min(core.lineCount, control.cursorLine)) - 1;
        const column = Math.max(1, control.cursorColumn) - 1;
        if (core.tooLarge) {
            view.cursorPosition = view.positionOfLine(line) + column;
            view.ensureVisible(view.cursorPosition);
        } else {
            edit.cursorPosition = core.positionOfLine(line, column);
        }
    }
    onCursorLineChanged: if (!_syncing) _applyCursor()
    onCursorColumnChanged: if (!_syncing) _applyCursor()

    // The colours of the syntax. A colour that is not legible on the code
    // surface moves toward the text colour until it is (WCAG AA); in high
    // contrast only the weight and the slant tell the kinds of text apart.
    function _legible(c: color): color {
        const bg = TelamonStyle.codeSurface;
        for (let t = 0; t <= 1.0001; t += 0.1) {
            const m = TelamonStyle.mix(c, TelamonStyle.text, t);
            if (TelamonStyle._contrast(m, bg) >= 4.5) {
                return m;
            }
        }
        return TelamonStyle.text;
    }
    readonly property var _syntaxPalette: {
        const text = TelamonStyle.text;
        if (TelamonStyle.highContrast) {
            const plain = {
                "color": text
            };
            return {
                "keyword": {
                    "color": text,
                    "bold": true
                },
                "comment": {
                    "color": text,
                    "italic": true
                },
                "error": {
                    "color": text,
                    "bold": true,
                    "underline": true
                },
                "warning": {
                    "color": text,
                    "underline": true
                },
                "string": plain
            };
        }
        const link = Kirigami.Theme.linkColor;
        return {
            "keyword": {
                "color": _legible(TelamonStyle.accentStrong)
            },
            "function": {
                "color": _legible(link)
            },
            "type": {
                "color": _legible(TelamonStyle.mix(link, TelamonStyle.success, 0.5))
            },
            "builtin": {
                "color": _legible(TelamonStyle.mix(TelamonStyle.accentStrong, link, 0.5))
            },
            "string": {
                "color": _legible(TelamonStyle.success)
            },
            "special": {
                "color": _legible(TelamonStyle.warning)
            },
            "number": {
                "color": _legible(TelamonStyle.warning)
            },
            "constant": {
                "color": _legible(TelamonStyle.mix(TelamonStyle.warning, TelamonStyle.accentStrong, 0.4))
            },
            "comment": {
                "color": _legible(TelamonStyle.mix(TelamonStyle.codeSurface, text, 0.62)),
                "italic": true
            },
            "preprocessor": {
                "color": _legible(TelamonStyle.mix(TelamonStyle.error, text, 0.2))
            },
            "attribute": {
                "color": _legible(TelamonStyle.mix(TelamonStyle.warning, TelamonStyle.success, 0.5))
            },
            "warning": {
                "color": _legible(TelamonStyle.warning)
            },
            "error": {
                "color": _legible(TelamonStyle.error)
            }
        };
    }

    TelamonCodeCorePrivate {
        id: core
        edit: edit
        syntaxPalette: control._syntaxPalette
        animateMarks: !TelamonStyle.reducedMotion
        markStepMs: TelamonStyle.softwareRendering ? 100 : 33
        onTextEdited: control.textEdited()
        onLoadingChanged: control._applyReadOnly()
        onLoaded: control.loaded()
        // A new document starts at the top left.
        onTextLoaded: {
            flick.contentY = 0;
            flick.contentX = 0;
        }
        onLayoutChanged: Qt.callLater(control._updateViewport)
        onTooLargeChanged: {
            control._applyReadOnly();
            Qt.callLater(control._updateViewport);
            Qt.callLater(control._readCursor);
        }
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: TelamonStyle.radius
        color: control.framed ? TelamonStyle.codeSurface : "transparent"
        border.width: control.framed ? 1 : 0
        border.color: TelamonStyle.separator
        TelamonFocusRing {
            radius: frame.radius + gap
            shown: (edit.activeFocus || view.activeFocus) && !control._byMouse
        }
    }

    // Why the text is read-only and plain.
    InfoBanner {
        id: banner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: control.framed ? 1 : 0
        shown: core.tooLarge
        type: "info"
        text: core.tooLargeReason === 2 ? qsTr("This text has a line longer than %1 characters, so it is shown read-only and as plain text.").arg(Number(core.maxEditableLine).toLocaleString(Qt.locale(), "f", 0)) : qsTr("This text is longer than %1 characters, so it is shown read-only and as plain text.").arg(Number(core.maximumSize).toLocaleString(Qt.locale(), "f", 0))
    }

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: control.framed ? 1 : 0
        anchors.topMargin: (control.framed ? 1 : 0) + control._bodyTop
        clip: true
        // Code reads left to right, with its numbers on the left, in any
        // language of the interface.
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        // Behind the text: the tint of the marked lines and of the caret's row.
        TelamonCodePaintPrivate {
            id: bands
            anchors.fill: parent
            mode: TelamonCodePaintPrivate.Bands
            core: core
            visible: !core.tooLarge
            contentY: flick.contentY
            topPadding: edit.topPadding
            cursorRect: edit.cursorRectangle
            showCurrentLine: control.highlightCurrentLine && edit.activeFocus
            currentLineColor: TelamonStyle.highContrast ? TelamonStyle.alpha(TelamonStyle.text, 0.12) : TelamonStyle.alpha(TelamonStyle.accent, 0.1)
            addedBand: TelamonStyle.alpha(TelamonStyle.highContrast ? TelamonStyle.text : Kirigami.Theme.positiveTextColor, 0.16)
            changedBand: TelamonStyle.alpha(TelamonStyle.highContrast ? TelamonStyle.text : Kirigami.Theme.neutralTextColor, 0.2)
        }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.leftMargin: gutter.visible ? gutter.width + 1 : 0
            visible: !core.tooLarge
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: edit.width
            contentHeight: edit.height
            // Scrolled to the end, the last line stops above the bar.
            bottomMargin: control._barRoom
            onContentYChanged: Qt.callLater(control._updateViewport)
            onHeightChanged: Qt.callLater(control._updateViewport)

            QQC2.ScrollBar.vertical: TelamonScrollBar {}
            QQC2.ScrollBar.horizontal: TelamonScrollBar {
                id: hbar
                policy: control._scrollsSideways ? QQC2.ScrollBar.AlwaysOn : QQC2.ScrollBar.AsNeeded
            }

            // Behind the text, as large as the view: a click in the empty part
            // of a line, or below the last line, puts the caret at the end of
            // the nearest line.
            Item {
                width: Math.max(flick.width, edit.width)
                height: Math.max(flick.height - flick.bottomMargin, edit.height)
                Accessible.ignored: true
                TapHandler {
                    onTapped: point => {
                        control._byMouse = true;
                        edit.forceActiveFocus(Qt.MouseFocusReason);
                        edit.cursorPosition = edit.positionAt(Math.max(0, edit.width - 1), Math.min(point.position.y, edit.height - 1));
                    }
                }
            }
            // Wrapped text is as wide as the view.
            Binding {
                when: control.wrap
                target: edit
                property: "width"
                value: flick.width
            }

            TextEdit {
                id: edit
                // Its size is the size of its text: setting a size of its own
                // lays the whole text out again at each change.
                focus: !core.tooLarge
                activeFocusOnTab: !core.tooLarge
                textFormat: TextEdit.PlainText
                wrapMode: control.wrap ? TextEdit.Wrap : TextEdit.NoWrap
                selectByMouse: true
                persistentSelection: true
                topPadding: TelamonStyle.spacing
                bottomPadding: TelamonStyle.spacing
                leftPadding: TelamonStyle.spacingLarge
                rightPadding: TelamonStyle.spacingLarge
                font.family: TelamonStyle.monoFamily
                font.pointSize: Kirigami.Theme.fixedWidthFont.pointSize
                // Where a script does not need shaping, lay the text out
                // without it: code is Latin, and the layout is much faster.
                font.preferShaping: false
                tabStopDistance: control.tabWidth * metrics.advanceWidth("0")
                color: Kirigami.Theme.textColor
                selectionColor: TelamonStyle.accent
                selectedTextColor: TelamonStyle.accentText
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhMultiLine

                Accessible.role: Accessible.EditableText
                Accessible.name: control.Accessible.name
                Accessible.readOnly: edit.readOnly

                FontMetrics {
                    id: metrics
                    font: edit.font
                }

                onActiveFocusChanged: {
                    if (!activeFocus) {
                        control._byMouse = false;
                        control._tabEscapes = false;
                    }
                }
                onCursorPositionChanged: control._readCursor()
                // Keyboard and caret moves keep the caret in view; the app's
                // own replacement of the text does not.
                onCursorRectangleChanged: {
                    if (!activeFocus || flick.width <= 0 || control._preserving) {
                        return;
                    }
                    const r = cursorRectangle;
                    const shown = flick.height - flick.bottomMargin;
                    if (r.y < flick.contentY) {
                        flick.contentY = control._clampY(r.y - topPadding);
                    } else if (r.y + r.height + bottomPadding > flick.contentY + shown) {
                        flick.contentY = control._clampY(r.y + r.height + bottomPadding - shown);
                    }
                    if (!control.wrap) {
                        if (r.x < flick.contentX) {
                            flick.contentX = Math.max(0, r.x - leftPadding);
                        } else if (r.x + 2 + rightPadding > flick.contentX + flick.width) {
                            flick.contentX = r.x + 2 + rightPadding - flick.width;
                        }
                    }
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        // The next Tab leaves the editor (it would indent).
                        control._tabEscapes = true;
                        return;
                    }
                    const modified = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
                    if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && !modified) {
                        const forward = event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier);
                        if (control.readOnly || control._tabEscapes) {
                            const next = edit.nextItemInFocusChain(forward);
                            if (next && next !== edit) {
                                next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
                            }
                        } else {
                            core.indent(!forward, control.tabWidth, control.insertSpaces);
                        }
                        control._tabEscapes = false;
                        event.accepted = true;
                        return;
                    }
                    control._tabEscapes = false;
                    if (event.key === Qt.Key_Home && !(event.modifiers & Qt.ControlModifier)) {
                        core.smartHome(!!(event.modifiers & Qt.ShiftModifier));
                        event.accepted = true;
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.AllButtons
                    onPressedChanged: {
                        if (pressed) {
                            control._byMouse = true;
                        }
                    }
                }
            }
        }

        // The line numbers, and the bars of the marked lines.
        TelamonCodePaintPrivate {
            id: gutter
            mode: TelamonCodePaintPrivate.Gutter
            core: core
            visible: control.showLineNumbers && !core.tooLarge
            x: 0
            y: 0
            width: visible ? gutterWidth : 0
            height: parent.height - control._barRoom
            contentY: flick.contentY
            topPadding: edit.topPadding
            font: edit.font
            lineCount: core.lineCount
            currentLine: control.cursorLine - 1
            numberColor: TelamonStyle.textMuted
            currentNumberColor: TelamonStyle.text
            addedColor: TelamonStyle.highContrast ? TelamonStyle.text : TelamonStyle.success
            changedColor: TelamonStyle.highContrast ? TelamonStyle.text : TelamonStyle.warning
        }
        Rectangle {
            visible: gutter.visible
            x: gutter.width
            width: 1
            height: parent.height
            color: TelamonStyle.separator
        }

        // Above the limit: a read-only viewer built for any size.
        TelamonTextView {
            id: view
            anchors.fill: parent
            visible: core.tooLarge
            focus: core.tooLarge
            activeFocusOnTab: core.tooLarge
            readOnly: true
            text: core.tooLarge ? core.text : ""
            wrap: control.wrap
            showLineNumbers: control.showLineNumbers
            highlightCurrentLine: control.highlightCurrentLine && view.activeFocus
            tabWidth: control.tabWidth
            font.family: TelamonStyle.monoFamily
            font.pointSize: Kirigami.Theme.fixedWidthFont.pointSize
            textColor: Kirigami.Theme.textColor
            lineNumberColor: TelamonStyle.textMuted
            selectionColor: TelamonStyle.selection
            onCursorPositionChanged: if (core.tooLarge) control._readCursor()
            onFirstVisibleLineChanged: if (core.tooLarge) control._updateViewport()
            Accessible.role: Accessible.EditableText
            Accessible.name: control.Accessible.name
            Accessible.readOnly: true
            TapHandler {
                acceptedButtons: Qt.AllButtons
                onPressedChanged: {
                    if (pressed) {
                        control._byMouse = true;
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        control._applyReadOnly();
        control._updateViewport();
        control._readCursor();
    }
}
