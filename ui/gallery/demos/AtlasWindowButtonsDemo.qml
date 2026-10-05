import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasWindowButtons in each state: at rest, hover, pressed, maximised
// (restore), the window inactive, and disabled. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 360
    implicitHeight: grid.implicitHeight + Kirigami.Units.gridUnit * 2

    GridLayout {
        id: grid
        anchors.centerIn: parent
        columns: 2
        columnSpacing: Kirigami.Units.gridUnit
        rowSpacing: Kirigami.Units.smallSpacing

        QQC2.Label { text: "Rest" }
        AtlasWindowButtons { active: true; _animate: root.animate }
        QQC2.Label { text: "Minimize hover" }
        AtlasWindowButtons { active: true; _animate: root.animate; _forceHover: "minimize" }
        QQC2.Label { text: "Maximize hover" }
        AtlasWindowButtons { active: true; _animate: root.animate; _forceHover: "maximize" }
        QQC2.Label { text: "Close hover" }
        AtlasWindowButtons { active: true; _animate: root.animate; _forceHover: "close" }
        QQC2.Label { text: "Pressed" }
        AtlasWindowButtons { active: true; _animate: root.animate; _forcePressed: "maximize" }
        QQC2.Label { text: "Close pressed" }
        AtlasWindowButtons { active: true; _animate: root.animate; _forcePressed: "close" }
        QQC2.Label { text: "Maximized" }
        AtlasWindowButtons { active: true; _animate: root.animate; _forceMaximized: 1 }
        QQC2.Label { text: "Inactive window" }
        AtlasWindowButtons { active: false; _animate: root.animate }
        QQC2.Label { text: "Disabled" }
        AtlasWindowButtons { active: true; _animate: root.animate; enabled: false }
    }
}
