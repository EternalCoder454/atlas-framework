import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonPlaceholder. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: layout.implicitWidth + Kirigami.Units.gridUnit * 2
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        textFormat: Text.PlainText
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.largeSpacing

        Caption { text: "One line" }
        TelamonPlaceholder { animated: root.animate; Layout.preferredWidth: 280 }
        Caption { text: "Three lines" }
        TelamonPlaceholder { animated: root.animate; lines: 3; Layout.preferredWidth: 280 }
        Caption { text: "Avatar plus text" }
        RowLayout {
            spacing: Kirigami.Units.largeSpacing
            TelamonPlaceholder { animated: root.animate; lineHeight: 48; Layout.preferredWidth: 48; Layout.preferredHeight: 48 }
            TelamonPlaceholder { animated: root.animate; lines: 2; Layout.preferredWidth: 200; Layout.alignment: Qt.AlignVCenter }
        }
    }
}
