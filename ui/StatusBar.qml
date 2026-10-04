import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A slim bar along the bottom of a window: Ln/Col, encoding, zoom. Put
// StatusBarItem children inside; a spacer is an Item with Layout.fillWidth,
// which pushes the cells after it to the far end. A thin separator is drawn
// between neighbouring visible cells, none next to a spacer.
Item {
    id: control

    default property alias content: row.data

    implicitWidth: row.implicitWidth
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.6)
    Accessible.role: Accessible.StatusBar

    // Sets `leadingSeparator` on every visible cell that follows another one.
    function refresh() {
        let previous = false;
        for (const item of row.children) {
            if (!item.visible) {
                continue;
            }
            if (item.Layout.fillWidth) {
                previous = false;
                continue;
            }
            if ("leadingSeparator" in item) {
                item.leadingSeparator = previous;
            }
            previous = true;
        }
    }

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: 0
        onChildrenChanged: control.refresh()
    }

    Component.onCompleted: refresh()
}
