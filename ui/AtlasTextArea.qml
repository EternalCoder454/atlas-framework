import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A rounded multi-line text field. `placeholderText` shows while it is empty.
// It wraps long lines; put it in a ScrollView or give it a height for long
// text. With `wrapMode: TextEdit.NoWrap` (a log or code view) it is as wide
// as its longest line, so a ScrollView around it scrolls sideways. Tab and Shift+Tab move focus on, as in a form (a plain TextArea
// would type a tab character).
//
//   AtlasTextArea {
//       placeholderText: qsTr("Notes")
//       implicitHeight: Kirigami.Units.gridUnit * 8
//   }
T.TextArea {
    id: control

    // Unwrapped, as wide as the longest line (a ScrollView takes this as its
    // content width); wrapped, a fixed width (contentWidth then follows the
    // width, so it can't feed back into it).
    implicitWidth: wrapMode === TextEdit.NoWrap
        ? Math.max(Kirigami.Units.gridUnit * 14, contentWidth + leftPadding + rightPadding)
        : Kirigami.Units.gridUnit * 14
    implicitHeight: Math.max(Kirigami.Units.gridUnit * 6, contentHeight + topPadding + bottomPadding)
    padding: AtlasStyle.spacingLarge
    wrapMode: TextEdit.Wrap
    placeholderTextColor: Qt.alpha(Kirigami.Theme.textColor, 0.5)
    color: Kirigami.Theme.textColor
    selectionColor: Kirigami.Theme.highlightColor
    selectedTextColor: Kirigami.Theme.highlightedTextColor
    font: Kirigami.Theme.defaultFont
    selectByMouse: true
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.EditableText
    //: Spoken name of a multi-line text field that has no placeholder or label of its own
    Accessible.name: placeholderText.length > 0 ? placeholderText : qsTr("Text area")

    Keys.onTabPressed: event => {
        const next = nextItemInFocusChain(true);
        if (next && next !== control) {
            next.forceActiveFocus(Qt.TabFocusReason);
        }
        event.accepted = true;
    }
    Keys.onBacktabPressed: event => {
        const prev = nextItemInFocusChain(false);
        if (prev && prev !== control) {
            prev.forceActiveFocus(Qt.BacktabFocusReason);
        }
        event.accepted = true;
    }

    background: Rectangle {
        radius: AtlasStyle.radiusLarge
        color: Qt.alpha(Kirigami.Theme.textColor, control.hovered && !control.activeFocus ? 0.09 : 0.06)
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Qt.alpha(Kirigami.Theme.highlightColor, 0.7) : Qt.alpha(Kirigami.Theme.textColor, 0.1)
        AtlasFocusRing {
            radius: parent.radius + gap
            shown: control.activeFocus && (control.focusReason === Qt.TabFocusReason || control.focusReason === Qt.BacktabFocusReason || control.focusReason === Qt.ShortcutFocusReason)
        }
    }

    // A template area keeps placeholderText but draws nothing for it.
    Text {
        x: control.leftPadding
        y: control.topPadding
        width: control.width - control.leftPadding - control.rightPadding
        visible: control.length === 0 && control.preeditText.length === 0
        text: control.placeholderText
        font: control.font
        color: control.placeholderTextColor
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        renderType: control.renderType
        Accessible.ignored: true
    }
}
