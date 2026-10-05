import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasButton: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 640
    implicitHeight: 280
    width: implicitWidth
    height: implicitHeight

    // One row per variant; the columns are the states, which are the same
    // layer for every variant: normal, with a symbol, checked, disabled, busy.
    GridLayout {
        anchors.fill: parent
        anchors.margins: 12
        rowSpacing: 10
        columnSpacing: 10
        columns: 5
        AtlasButton { text: "Default" }
        AtlasButton { text: "Symbol"; symbol: Symbols.codepoint("home") }
        AtlasButton { text: "Checked"; checkable: true; checked: true }
        AtlasButton { text: "Disabled"; enabled: false }
        AtlasButton { text: "Busy"; busy: true; _spinnerAnimated: root.animate }

        AtlasButton { text: "Prominent"; variant: AtlasButton.Prominent }
        AtlasButton { text: "Symbol"; variant: AtlasButton.Prominent; symbol: Symbols.codepoint("home") }
        AtlasButton { text: "Checked"; variant: AtlasButton.Prominent; checkable: true; checked: true }
        AtlasButton { text: "Disabled"; variant: AtlasButton.Prominent; enabled: false }
        AtlasButton { text: "Busy"; variant: AtlasButton.Prominent; busy: true; _spinnerAnimated: root.animate }

        AtlasButton { text: "Destructive"; variant: AtlasButton.Destructive }
        AtlasButton { text: "Delete"; variant: AtlasButton.Destructive; symbol: Symbols.codepoint("delete") }
        AtlasButton { text: "Checked"; variant: AtlasButton.Destructive; checkable: true; checked: true }
        AtlasButton { text: "Disabled"; variant: AtlasButton.Destructive; enabled: false }
        AtlasButton { text: "Busy"; variant: AtlasButton.Destructive; busy: true; _spinnerAnimated: root.animate }

        AtlasButton { text: "Ghost"; variant: AtlasButton.Ghost }
        AtlasButton { text: "Symbol"; variant: AtlasButton.Ghost; symbol: Symbols.codepoint("home") }
        AtlasButton { text: "Checked"; variant: AtlasButton.Ghost; checkable: true; checked: true }
        AtlasButton { text: "Disabled"; variant: AtlasButton.Ghost; enabled: false }
        AtlasButton { text: "Busy"; variant: AtlasButton.Ghost; busy: true; _spinnerAnimated: root.animate }

        // The old way to ask for the prominent look, and an icon from the theme.
        AtlasButton { text: "prominent"; prominent: true }
        AtlasButton { text: "Icon"; icon.name: "document-save" }
    }
}
