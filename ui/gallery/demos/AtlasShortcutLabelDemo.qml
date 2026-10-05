import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasShortcutLabel with a short, a long and a two-step sequence, a standard
// key, and an empty one (no size). Tests set `animate` to false.
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

        Caption { text: "Single key" }
        AtlasShortcutLabel { sequence: "F5" }
        Caption { text: "Ctrl+S" }
        AtlasShortcutLabel { sequence: "Ctrl+S" }
        Caption { text: "Ctrl+Shift+Alt+K" }
        AtlasShortcutLabel { sequence: "Ctrl+Shift+Alt+K" }
        Caption { text: "Two steps" }
        AtlasShortcutLabel { sequence: "Ctrl+K, Ctrl+C" }
        Caption { text: "StandardKey.Copy" }
        AtlasShortcutLabel { sequence: StandardKey.Copy }
        Caption { text: "Empty (no size)" }
        AtlasShortcutLabel { sequence: "" }
    }
}
