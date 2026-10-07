import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Every static state of TelamonShortcutField: with a value, empty, in conflict
// with another action, and disabled. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: layout.implicitWidth + Kirigami.Units.gridUnit * 2
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    // Registered with TelamonShortcuts, so a field with this shortcut conflicts.
    TelamonAction {
        id: saveAction
        text: qsTr("&Save")
        shortcut: "Ctrl+S"
        enabled: false
    }

    component Caption: QQC2.Label {
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.largeSpacing

        Caption { text: "With a value" }
        TelamonShortcutField { sequence: "Ctrl+Shift+K" }
        Caption { text: "Empty" }
        TelamonShortcutField { }
        Caption { text: "Conflict" }
        TelamonShortcutField { sequence: "Ctrl+S" }
        Caption { text: "The action being edited is no conflict" }
        TelamonShortcutField { sequence: "Ctrl+S"; ignoreAction: saveAction }
        Caption { text: "Disabled" }
        TelamonShortcutField { sequence: "Alt+F4"; enabled: false }
    }
}
