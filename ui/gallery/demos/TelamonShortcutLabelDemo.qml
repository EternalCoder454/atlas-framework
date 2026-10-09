import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonShortcutLabel with a short, a long and a two-step sequence, a standard
// key, and an empty one (no size). Tests set `animate` to false.
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

        Caption { text: "Single key" }
        TelamonShortcutLabel { sequence: "F5" }
        Caption { text: "Ctrl+S" }
        TelamonShortcutLabel { sequence: "Ctrl+S" }
        Caption { text: "Ctrl+Shift+Alt+K" }
        TelamonShortcutLabel { sequence: "Ctrl+Shift+Alt+K" }
        Caption { text: "Two steps" }
        TelamonShortcutLabel { sequence: "Ctrl+K, Ctrl+C" }
        Caption { text: "StandardKey.Copy" }
        TelamonShortcutLabel { sequence: StandardKey.Copy }
        Caption { text: "Empty (no size)" }
        TelamonShortcutLabel { sequence: "" }
    }
}
