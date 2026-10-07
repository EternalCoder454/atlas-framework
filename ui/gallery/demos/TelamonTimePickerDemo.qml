import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonTimePicker. Tests set `animate` to false.
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

        Caption { text: "24 hours" }
        TelamonTimePicker { locale: Qt.locale("en_US"); use24Hour: true; hours: 17; minutes: 5 }
        Caption { text: "12 hours, PM" }
        TelamonTimePicker { locale: Qt.locale("en_US"); use24Hour: false; hours: 17; minutes: 5 }
        Caption { text: "12 hours, midnight, step 15" }
        TelamonTimePicker { locale: Qt.locale("en_US"); use24Hour: false; hours: 0; minuteStep: 15; minutes: 40 }
        Caption { text: "With a day" }
        TelamonTimePicker { locale: Qt.locale("en_US"); use24Hour: true; showDay: true; day: Qt.Wednesday; hours: 8; minutes: 30 }
        Caption { text: "Disabled" }
        TelamonTimePicker { locale: Qt.locale("en_US"); use24Hour: true; hours: 9; minutes: 0; enabled: false }
    }
}
