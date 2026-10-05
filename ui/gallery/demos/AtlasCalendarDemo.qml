import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every static state of AtlasCalendar. The dates are fixed so the pictures do
// not change with the day. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: layout.implicitWidth + Kirigami.Units.gridUnit * 2
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.gridUnit * 2

        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing
            Caption { text: "Selected day, today ringed (week starts Sunday)" }
            AtlasCalendar {
                locale: Qt.locale("en_US")
                today: new Date(2026, 2, 12)
                selectedDate: new Date(2026, 2, 15)
            }
        }
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing
            Caption { text: "Range 10 to 20 March, keyboard focus (Monday)" }
            AtlasCalendar {
                locale: Qt.locale("de_DE")
                today: new Date(2026, 2, 12)
                selectedDate: new Date(2026, 2, 18)
                minimumDate: new Date(2026, 2, 10)
                maximumDate: new Date(2026, 2, 20)
                Component.onCompleted: forceActiveFocus(Qt.TabFocusReason)
            }
        }
    }
}
