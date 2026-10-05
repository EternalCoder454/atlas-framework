import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasSplitView: fixed sizes, no timers. The second
// view is collapsible and narrower than its collapseWidth, on its second pane.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 340
    width: implicitWidth
    height: implicitHeight

    AtlasSplitView {
        x: 8
        y: 8
        width: parent.width - 16
        height: 144

        Rectangle {
            QQC2.SplitView.preferredWidth: 160
            QQC2.SplitView.minimumWidth: 80
            color: Kirigami.Theme.alternateBackgroundColor
            QQC2.Label {
                anchors.centerIn: parent
                text: "Sidebar"
            }
        }
        Rectangle {
            QQC2.SplitView.fillWidth: true
            color: Kirigami.Theme.backgroundColor
            QQC2.Label {
                anchors.centerIn: parent
                text: "Content"
            }
        }
    }

    AtlasSplitView {
        y: 176
        x: 8
        width: 260
        height: 160
        collapsible: true
        collapseWidth: 300
        currentPane: 1

        Rectangle {
            QQC2.SplitView.preferredWidth: 100
            color: Kirigami.Theme.alternateBackgroundColor
            QQC2.Label {
                anchors.centerIn: parent
                text: "List"
            }
        }
        Rectangle {
            QQC2.SplitView.fillWidth: true
            color: Kirigami.Theme.backgroundColor
            QQC2.Label {
                anchors.centerIn: parent
                text: "Details"
            }
        }
    }
}
