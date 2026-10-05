import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasAccentPicker: named swatches, plain colours and a
// disabled picker. Fixed content; `animate` is switched off by tests/visual.
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

        Caption { text: "Named" }
        AtlasAccentPicker {
            Accessible.name: "Accent"
            model: [{
                    "color": "#3584e4", // atlas-lint: allow-raw (sample swatch)
                    "name": "Blue"
                }, {
                    "color": "#26a269", // atlas-lint: allow-raw (sample swatch)
                    "name": "Green"
                }, {
                    "color": "#e5a50a", // atlas-lint: allow-raw (sample swatch)
                    "name": "Yellow"
                }, {
                    "color": "#e5487a", // atlas-lint: allow-raw (sample swatch)
                    "name": "Pink"
                }, {
                    "color": "#9141ac", // atlas-lint: allow-raw (sample swatch)
                    "name": "Purple"
                }]
            currentIndex: 3
        }
        Caption { text: "Plain colours, pale one chosen" }
        AtlasAccentPicker {
            Accessible.name: "Plain"
            model: ["#c01c28", "#ffffff", "#241f31"] // atlas-lint: allow-raw (sample swatches)
            currentIndex: 1
        }
        Caption { text: "Disabled" }
        AtlasAccentPicker {
            Accessible.name: "Disabled"
            enabled: false
            model: ["#3584e4", "#26a269"] // atlas-lint: allow-raw (sample swatches)
            currentIndex: 0
        }
    }
}
