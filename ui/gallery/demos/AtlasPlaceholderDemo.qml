import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasPlaceholder. Tests set `animate` to false.
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

        Caption { text: "One line" }
        AtlasPlaceholder { animated: root.animate; Layout.preferredWidth: 280 }
        Caption { text: "Three lines" }
        AtlasPlaceholder { animated: root.animate; lines: 3; Layout.preferredWidth: 280 }
        Caption { text: "Avatar plus text" }
        RowLayout {
            spacing: Kirigami.Units.largeSpacing
            AtlasPlaceholder { animated: root.animate; lineHeight: 48; Layout.preferredWidth: 48; Layout.preferredHeight: 48 }
            AtlasPlaceholder { animated: root.animate; lines: 2; Layout.preferredWidth: 200; Layout.alignment: Qt.AlignVCenter }
        }
    }
}
