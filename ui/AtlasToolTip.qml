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
//   AtlasButton {
//       text: qsTr("Refresh")
//       AtlasToolTip { text: qsTr("Check for updates"); shown: parent.hovered || parent.visualFocus }
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
            const need = control.implicitHeight + AtlasStyle.spacingSmall;
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
    y: control._below && control.parent ? control.parent.height + AtlasStyle.spacingSmall : -implicitHeight - AtlasStyle.spacingSmall
    implicitWidth: Math.min(Kirigami.Units.gridUnit * 20, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: implicitContentHeight + topPadding + bottomPadding
    leftPadding: AtlasStyle.spacingLarge
    rightPadding: AtlasStyle.spacingLarge
    topPadding: AtlasStyle.spacingSmall + 2
    bottomPadding: AtlasStyle.spacingSmall + 2
    margins: AtlasStyle.spacingSmall
    delay: Kirigami.Units.toolTipDelay
    timeout: Kirigami.Units.toolTipDelay * 10
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent | T.Popup.CloseOnReleaseOutsideParent

    contentItem: Text {
        visible: control.text.length > 0
        text: control.text
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeCaption
        color: Kirigami.Theme.textColor
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        // A popup takes no Accessible of its own; the text carries it.
        Accessible.role: Accessible.ToolTip
        Accessible.name: control.text
    }

    background: Rectangle {
        visible: control.text.length > 0
        radius: AtlasStyle.radius
        color: AtlasStyle.floatingBackground
        border.width: 1
        border.color: AtlasStyle.separator
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: AtlasStyle.durationShort
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: AtlasStyle.durationShort
        }
    }
}
