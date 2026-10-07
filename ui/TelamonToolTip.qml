import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A small rounded hint on a raised card. Declare it inside the item it
// describes and set `text`. Bind `shown` to the hover state, and to the
// keyboard focus so that keyboard users get the hint too: the tip opens
// after the hover delay, closes at once when `shown` ends, and goes by itself
// after a while. (Setting `visible` opens it at once.) With no text it draws
// nothing and never opens by `shown`. It sits above its item, or below when
// there is no room above.
//
//   TelamonButton {
//       text: qsTr("Refresh")
//       TelamonToolTip { text: qsTr("Check for updates"); shown: parent.hovered || parent.visualFocus }
//   }
T.ToolTip {
    id: control

    // Usually the hover state of the parent.
    property bool shown: false

    // True when the tip is put below its item (no room above).
    property bool _below: false

    onAboutToShow: {
        const win = control.parent ? control.parent.Window.window : null;
        if (win && control.parent) {
            const top = control.parent.mapToItem(null, 0, 0).y;
            const need = control.implicitHeight + TelamonStyle.spacingSmall;
            control._below = top - need < control.margins && top + control.parent.height + need + control.margins <= win.height;
        }
    }

    onShownChanged: {
        if (shown) {
            wait.restart();
        } else {
            wait.stop();
            close();
        }
    }

    Timer {
        id: wait
        interval: control.delay
        onTriggered: if (control.text.length > 0) control.open()
    }
    Component.onCompleted: if (control.shown) wait.restart()

    x: parent ? Math.round((parent.width - implicitWidth) / 2) : 0
    y: control._below && control.parent ? control.parent.height + TelamonStyle.spacingSmall : -implicitHeight - TelamonStyle.spacingSmall
    implicitWidth: Math.min(Kirigami.Units.gridUnit * 20, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: implicitContentHeight + topPadding + bottomPadding
    leftPadding: TelamonStyle.spacingLarge
    rightPadding: TelamonStyle.spacingLarge
    topPadding: TelamonStyle.spacingSmall + 2
    bottomPadding: TelamonStyle.spacingSmall + 2
    margins: TelamonStyle.spacingSmall
    delay: Kirigami.Units.toolTipDelay
    timeout: Kirigami.Units.toolTipDelay * 10
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent | T.Popup.CloseOnReleaseOutsideParent

    contentItem: Text {
        visible: control.text.length > 0
        text: control.text
        font.family: TelamonStyle.fontFamily
        font.pointSize: TelamonStyle.fontSizeCaption
        color: Kirigami.Theme.textColor
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        // A popup takes no Accessible of its own; the text carries it.
        Accessible.role: Accessible.ToolTip
        Accessible.name: control.text
    }

    background: Rectangle {
        visible: control.text.length > 0
        radius: TelamonStyle.radius
        color: TelamonStyle.floatingBackground
        border.width: 1
        border.color: TelamonStyle.separator
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: TelamonStyle.durationShort
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: TelamonStyle.durationShort
        }
    }
}
