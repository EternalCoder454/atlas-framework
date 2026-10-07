import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonSpinner. Tests set `animate` to false.
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

        Caption { text: "Small, medium, large" }
        RowLayout {
            spacing: Kirigami.Units.gridUnit
            TelamonSpinner { animated: root.animate; implicitWidth: Kirigami.Units.iconSizes.small }
            TelamonSpinner { animated: root.animate }
            TelamonSpinner { animated: root.animate; implicitWidth: Kirigami.Units.iconSizes.large }
        }
        Caption { text: "Not running (hidden, takes no room)" }
        TelamonSpinner { animated: root.animate; running: false }
    }
}
