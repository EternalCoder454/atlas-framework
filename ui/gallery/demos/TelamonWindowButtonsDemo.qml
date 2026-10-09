import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonWindowButtons in each state: at rest, hover, pressed, maximised
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

        QQC2.Label { textFormat: Text.PlainText; text: "Rest" }
        TelamonWindowButtons { active: true; _animate: root.animate }
        QQC2.Label { textFormat: Text.PlainText; text: "Minimize hover" }
        TelamonWindowButtons { active: true; _animate: root.animate; _forceHover: "minimize" }
        QQC2.Label { textFormat: Text.PlainText; text: "Maximize hover" }
        TelamonWindowButtons { active: true; _animate: root.animate; _forceHover: "maximize" }
        QQC2.Label { textFormat: Text.PlainText; text: "Close hover" }
        TelamonWindowButtons { active: true; _animate: root.animate; _forceHover: "close" }
        QQC2.Label { textFormat: Text.PlainText; text: "Pressed" }
        TelamonWindowButtons { active: true; _animate: root.animate; _forcePressed: "maximize" }
        QQC2.Label { textFormat: Text.PlainText; text: "Close pressed" }
        TelamonWindowButtons { active: true; _animate: root.animate; _forcePressed: "close" }
        QQC2.Label { textFormat: Text.PlainText; text: "Maximized" }
        TelamonWindowButtons { active: true; _animate: root.animate; _forceMaximized: 1 }
        QQC2.Label { textFormat: Text.PlainText; text: "Inactive window" }
        TelamonWindowButtons { active: false; _animate: root.animate }
        QQC2.Label { textFormat: Text.PlainText; text: "Disabled" }
        TelamonWindowButtons { active: true; _animate: root.animate; enabled: false }
    }
}
