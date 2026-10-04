import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// One cell of a StatusBar: a short text such as "Ln 3, Col 14". With
// `clickable` it gets a hover background and emits clicked(); with a `menu`
// (a QQC2.Menu or ContextMenu) a click pops it up above the cell. The
// StatusBar sets `leadingSeparator` to draw the thin line before the cell.
T.AbstractButton {
    id: control

    property bool clickable: false
    property string toolTip
    // Opened above the item on a click; leave unset for none.
    property QtObject menu: null
    // Set by the StatusBar.
    property bool leadingSeparator: false

    implicitWidth: label.implicitWidth + leftPadding + rightPadding + (leadingSeparator ? 1 : 0)
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.5)
    leftPadding: Kirigami.Units.largeSpacing
    rightPadding: leftPadding
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    Accessible.role: clickable ? Accessible.Button : Accessible.StaticText
    Accessible.name: control.text
    Accessible.description: control.toolTip

    onClicked: {
        if (control.clickable && control.menu) {
            control.menu.popup(control, control.mirrored ? control.width - control.menu.implicitWidth : 0, -control.menu.implicitHeight - Kirigami.Units.smallSpacing);
        }
    }
    onVisibleChanged: {
        // The parent is the bar's row; the bar is above it.
        const bar = parent ? parent.parent : null;
        if (bar && typeof bar.refresh === "function") {
            bar.refresh();
        }
    }

    QQC2.ToolTip.visible: control.toolTip.length > 0 && control.hovered
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    QQC2.ToolTip.text: control.toolTip

    background: Item {
        // The leading edge is the left, or the right when mirrored.
        Rectangle {
            visible: control.leadingSeparator
            x: control.mirrored ? parent.width - width : 0
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: Math.round(parent.height * 0.6)
            color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
        }
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 1
            anchors.bottomMargin: 1
            anchors.leftMargin: control.leadingSeparator ? 2 : 0
            anchors.rightMargin: 0
            radius: 6
            color: Qt.alpha(Kirigami.Theme.textColor, !control.clickable ? 0 : control.down ? 0.14 : control.hovered ? 0.08 : 0)
        }
    }

    contentItem: Text {
        id: label
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        text: control.text
        font: Kirigami.Theme.smallFont
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Kirigami.Theme.textColor
        opacity: 0.8
    }
}
