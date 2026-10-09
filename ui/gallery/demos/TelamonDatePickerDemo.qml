import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// The closed states of TelamonDatePicker. The dates are fixed so the pictures do
// not change with the day. Tests set `animate` to false.
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

        Caption { text: "With a date" }
        TelamonDatePicker {
            locale: Qt.locale("en_US")
            selectedDate: new Date(2026, 2, 15)
            Accessible.name: "Date"
        }
        Caption { text: "Empty" }
        TelamonDatePicker {
            locale: Qt.locale("en_US")
            selectedDate: new Date(NaN)
            Accessible.name: "Date"
        }
        Caption { text: "Clearable, long format" }
        TelamonDatePicker {
            locale: Qt.locale("en_US")
            format: Locale.LongFormat
            clearable: true
            selectedDate: new Date(2026, 2, 15)
            Accessible.name: "Date"
        }
        Caption { text: "Disabled" }
        TelamonDatePicker {
            locale: Qt.locale("en_US")
            enabled: false
            selectedDate: new Date(2026, 2, 15)
            Accessible.name: "Date"
        }
    }
}
