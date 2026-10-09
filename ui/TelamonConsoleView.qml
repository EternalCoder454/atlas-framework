import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// The output of a command, as it streams in: read-only monospace text with
// colours, selectable (mouse, Ctrl+A, Ctrl+C) and plain: nothing in it is taken
// as HTML, and an escape sequence is never run. append() adds text at the end,
// in chunks of any size; the colours and text styles of ANSI escape sequences
// (SGR) are drawn in the theme's colours, every other escape sequence is
// dropped. The view keeps the last `maximumLines` lines. While `follow` is on
// and the view is at the end it stays there as text comes in; scrolling up
// stops that, scrolling back down to the end (or scrollToEnd()) goes on.
//
//   TelamonConsoleView {
//       id: console
//       Layout.fillWidth: true
//       Layout.fillHeight: true
//   }
//   Process { onReadyReadStandardOutput: console.append(readAllStandardOutput()) }
//
// Screen readers get the text field, named "Console output"; set
// Accessible.name on the view to say whose output it is ("Build output").
// What is shown and what is dropped: docs/reference/telamon-ui/telamon-console-view.md.
Item {
    id: control

    // The most lines kept; the oldest go first. Less than 1 is 1.
    property int maximumLines: 10000
    // The lines of text. The empty line after a final newline is not counted.
    readonly property int lineCount: sink.lineCount
    // Keeps the view at the end while output comes in.
    property bool follow: true
    // True while the view is at the end and `follow` is on.
    readonly property bool following: control.follow && control._pinned
    property bool wrap: false
    property bool framed: true
    // See docs/reference/telamon-ui/telamon-code-view.md.
    property bool inset: false
    readonly property string selectedText: edit.selectedText

    // Adds text at the end of the output.
    function append(text: string): void {
        // Lines that go from the top move the text up: a view that is not following
        // moves with them (_trimmed), one that is goes to the end.
        const following = control.following;
        control._y0 = flick.contentY;
        control._frozen++;
        sink.append(text);
        control._frozen--;
        if (following) {
            control._pinned = true;
            control._sync();
        } else {
            control._pinned = control._atEnd();
        }
    }
    // Empties the view and forgets the colours and the unfinished escape sequence.
    function clear(): void {
        sink.clear();
        control._pinned = true;
        control._moveTo(0, 0);
    }
    // Everything the view holds, without the colours.
    function plainText(): string {
        return sink.plainText();
    }
    // Copies the selected text to the clipboard, as plain text.
    function copy(): void {
        if (edit.selectedText.length > 0) {
            TelamonClipboard.setText(edit.selectedText);
        }
    }
    function selectAll(): void {
        control._quiet = true;
        edit.selectAll();
        control._quiet = false;
    }
    // Scrolls to the end, and with `follow` on goes on following.
    function scrollToEnd(): void {
        control._pinned = true;
        control._moveTo(flick.contentX, control._end());
    }

    // True once the mouse pressed in the view: the focus ring is for the keyboard.
    property bool _byMouse: false
    // At the end, and so followed when `follow` is on.
    property bool _pinned: true
    // Above 0 while this item moves the view or changes the text, so that is not taken for the user's scroll.
    property int _frozen: 0
    property bool _quiet: false
    property bool _keyNav: false
    property bool _mouseDown: false
    property real _y0: 0
    readonly property QtObject _sink: sink
    readonly property var _flick: flick
    readonly property var _edit: edit
    readonly property real _pad: control.framed ? TelamonStyle.spacingLarge : 0
    readonly property real _padX: control.framed || control.inset ? TelamonStyle.spacingLarge : 0
    readonly property bool _scrollsSideways: !control.wrap && flick.contentWidth > flick.width + 0.5
    readonly property real _barRoom: control._scrollsSideways ? hbar.implicitHeight : 0

    // The 16 colours of the ANSI colours and their bright variants, from the theme.
    // The sink makes each legible on the code surface and keeps them out of high contrast.
    readonly property var _palette: {
        const text = TelamonStyle.text;
        const base = [
            TelamonStyle.textMuted,
            TelamonStyle.error,
            TelamonStyle.success,
            TelamonStyle.warning,
            Kirigami.Theme.linkColor,
            TelamonStyle.accentStrong,
            TelamonStyle.mix(Kirigami.Theme.linkColor, TelamonStyle.success, 0.5),
            text
        ];
        const out = base.slice();
        for (const c of base) {
            out.push(TelamonStyle.mix(c, text, 0.3));
        }
        return out;
    }

    function _end(): real {
        return Math.max(0, flick.contentHeight + flick.bottomMargin - flick.height);
    }
    function _atEnd(): bool {
        return flick.contentY >= control._end() - 1;
    }
    function _moveTo(x: real, y: real): void {
        control._frozen++;
        flick.contentX = x;
        flick.contentY = y;
        control._frozen--;
    }
    // Back to the end when the view is following.
    function _sync(): void {
        if (control.following && flick.contentY !== control._end()) {
            control._moveTo(flick.contentX, control._end());
        }
    }
    // Lines went from the top, `height` pixels of them: a view that is not following moves up with them.
    function _trimmed(height: real): void {
        if (!control.following) {
            control._moveTo(flick.contentX, Math.max(0, control._y0 - height));
        }
    }
    function _scrollBy(dx: real, dy: real): void {
        flick.contentX = Math.max(0, Math.min(Math.max(0, flick.contentWidth - flick.width), flick.contentX + dx));
        flick.contentY = Math.max(0, Math.min(control._end(), flick.contentY + dy));
    }
    function _key(event: var): void {
        if (event.matches(StandardKey.Copy)) {
            control.copy();
            event.accepted = true;
            return;
        }
        if (event.matches(StandardKey.SelectAll)) {
            control.selectAll();
            event.accepted = true;
            return;
        }
        if (event.modifiers & Qt.ShiftModifier) {
            // The caret moves and selects; the view follows it (see below).
            control._keyNav = true;
            Qt.callLater(() => control._keyNav = false);
            return;
        }
        const line = Math.max(1, metrics.height);
        const page = Math.max(line, flick.height - control._barRoom - line);
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        event.accepted = true;
        switch (event.key) {
        case Qt.Key_Up:
            control._scrollBy(0, -line);
            break;
        case Qt.Key_Down:
            control._scrollBy(0, line);
            break;
        case Qt.Key_PageUp:
            control._scrollBy(0, -page);
            break;
        case Qt.Key_PageDown:
            control._scrollBy(0, page);
            break;
        case Qt.Key_Left:
            control._scrollBy(-line * 2, 0);
            break;
        case Qt.Key_Right:
            control._scrollBy(line * 2, 0);
            break;
        case Qt.Key_Home:
            if (ctrl) {
                control._scrollBy(0, -flick.contentY);
            } else {
                control._scrollBy(-flick.contentX, 0);
            }
            break;
        case Qt.Key_End:
            if (ctrl) {
                control.scrollToEnd();
            } else {
                control._scrollBy(flick.contentWidth, 0);
            }
            break;
        default:
            event.accepted = false;
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 30
    implicitHeight: Kirigami.Units.gridUnit * 12
    opacity: control.enabled ? 1 : 0.5

    // The name is the view's to set; the text field below forwards it.
    Accessible.ignored: true
    Accessible.name: qsTr("Console output")

    // Wrapped, the text is as wide as the room; else it is as wide as its longest line.
    function _applyWrap(): void {
        if (control.wrap) {
            edit.width = Qt.binding(() => flick.width);
        } else {
            edit.width = undefined;
        }
    }
    onWrapChanged: control._applyWrap()
    Component.onCompleted: control._applyWrap()

    onFollowChanged: {
        if (control.follow) {
            control.scrollToEnd();
        }
    }

    TelamonConsoleSinkPrivate {
        id: sink
        textDocument: edit.textDocument
        maximumLines: control.maximumLines
        palette: control._palette
        textColor: TelamonStyle.text
        surfaceColor: TelamonStyle.codeSurface
        highContrast: TelamonStyle.highContrast
        onTrimmedAbove: height => control._trimmed(height)
    }

    FontMetrics {
        id: metrics
        font: edit.font
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
            shown: edit.activeFocus && !control._byMouse
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: control._pad
        anchors.bottomMargin: control._pad
        anchors.leftMargin: control._padX
        anchors.rightMargin: control._padX
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: edit.width
        contentHeight: edit.height
        // Scrolled to the end, the last line stops above the bar.
        bottomMargin: control._barRoom

        QQC2.ScrollBar.vertical: TelamonScrollBar {}
        QQC2.ScrollBar.horizontal: TelamonScrollBar {
            id: hbar
            // Steady while there is room reserved for it: it is the only sign
            // that a line goes on past the edge.
            policy: control._scrollsSideways ? QQC2.ScrollBar.AlwaysOn : QQC2.ScrollBar.AsNeeded
        }

        // A move this item did not make is the user's (wheel, drag, bar, keys):
        // the view follows only while it is at the end.
        onContentYChanged: {
            if (control._frozen === 0) {
                control._pinned = control._atEnd();
            }
        }
        onContentHeightChanged: control._sync()
        onHeightChanged: control._sync()
        onBottomMarginChanged: control._sync()

        TextEdit {
            id: edit
            // Its width is set only while wrapping (see _applyWrap): a width bound to
            // implicitWidth has the text laid out again in full at every change.
            readOnly: true
            selectByMouse: true
            persistentSelection: true
            activeFocusOnTab: true
            textFormat: TextEdit.PlainText
            wrapMode: control.wrap ? TextEdit.Wrap : TextEdit.NoWrap
            font.family: TelamonStyle.monoFamily
            font.pointSize: Kirigami.Theme.fixedWidthFont.pointSize
            tabStopDistance: metrics.averageCharacterWidth * 8
            color: Kirigami.Theme.textColor
            selectionColor: TelamonStyle.accent
            selectedTextColor: TelamonStyle.accentText

            Accessible.role: Accessible.EditableText
            Accessible.name: control.Accessible.name
            Accessible.readOnly: true

            Keys.onPressed: event => control._key(event)

            onActiveFocusChanged: {
                if (!activeFocus) {
                    control._byMouse = false;
                }
            }
            // Keyboard selection and mouse selection past the edge keep the caret in view;
            // the caret that output going in or Ctrl+A sets does not scroll the view.
            onCursorRectangleChanged: {
                if (!activeFocus || flick.width <= 0 || control._quiet || !(control._keyNav || control._mouseDown)) {
                    return;
                }
                const r = cursorRectangle;
                const shown = flick.height - control._barRoom;
                if (r.y < flick.contentY) {
                    flick.contentY = r.y;
                } else if (r.y + r.height > flick.contentY + shown) {
                    flick.contentY = r.y + r.height - shown;
                }
                if (r.x < flick.contentX) {
                    flick.contentX = r.x;
                } else if (r.x + 2 > flick.contentX + flick.width) {
                    flick.contentX = r.x + 2 - flick.width;
                }
            }
            TapHandler {
                acceptedButtons: Qt.AllButtons
                onPressedChanged: {
                    control._mouseDown = pressed;
                    if (pressed) {
                        control._byMouse = true;
                    }
                }
            }
        }
    }
}
