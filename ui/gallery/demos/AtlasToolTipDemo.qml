import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasToolTip. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: layout.implicitWidth + Kirigami.Units.gridUnit * 2
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.largeSpacing

        Caption { text: "Short tip" }
        Item {
            implicitWidth: 120; implicitHeight: 40
            Rectangle { anchors.fill: parent; radius: 8; color: Qt.alpha(Kirigami.Theme.textColor, 0.07) }
            AtlasToolTip { text: qsTr("Refresh"); visible: true; y: parent.height + Kirigami.Units.smallSpacing }
        }
        Item { Layout.preferredHeight: Kirigami.Units.gridUnit * 2 }
        Caption { text: "Long text (wraps)" }
        Item {
            implicitWidth: 120; implicitHeight: 40
            Rectangle { anchors.fill: parent; radius: 8; color: Qt.alpha(Kirigami.Theme.textColor, 0.07) }
            AtlasToolTip { text: "A longer hint that explains in a full sentence what this control does and why."; visible: true; y: parent.height + Kirigami.Units.smallSpacing }
        }
        Item { Layout.preferredHeight: Kirigami.Units.gridUnit * 4 }
    }
}
