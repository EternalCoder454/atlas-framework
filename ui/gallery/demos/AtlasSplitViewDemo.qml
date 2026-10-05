import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasSplitView: fixed sizes, no timers.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 160
    width: implicitWidth
    height: implicitHeight

    AtlasSplitView {
        anchors.fill: parent
        anchors.margins: 8

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
}
