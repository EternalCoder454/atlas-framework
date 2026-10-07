import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonButton: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    // Sized by its content, so 200% text still fits (three columns, not five).
    implicitWidth: grid.implicitWidth + 24
    implicitHeight: grid.implicitHeight + 24
    width: implicitWidth
    height: implicitHeight

    // Per variant: normal, with a symbol, checked, disabled, busy.
    GridLayout {
        id: grid
        x: 12
        y: 12
        rowSpacing: 10
        columnSpacing: 10
        columns: 3
        TelamonButton { text: "Default" }
        TelamonButton { text: "Symbol"; symbol: Symbols.codepoint("home") }
        TelamonButton { text: "Checked"; checkable: true; checked: true }
        TelamonButton { text: "Disabled"; enabled: false }
        TelamonButton { text: "Busy"; busy: true; _spinnerAnimated: root.animate }

        TelamonButton { text: "Prominent"; variant: TelamonButton.Prominent }
        TelamonButton { text: "Symbol"; variant: TelamonButton.Prominent; symbol: Symbols.codepoint("home") }
        TelamonButton { text: "Checked"; variant: TelamonButton.Prominent; checkable: true; checked: true }
        TelamonButton { text: "Disabled"; variant: TelamonButton.Prominent; enabled: false }
        TelamonButton { text: "Busy"; variant: TelamonButton.Prominent; busy: true; _spinnerAnimated: root.animate }

        TelamonButton { text: "Destructive"; variant: TelamonButton.Destructive }
        TelamonButton { text: "Delete"; variant: TelamonButton.Destructive; symbol: Symbols.codepoint("delete") }
        TelamonButton { text: "Checked"; variant: TelamonButton.Destructive; checkable: true; checked: true }
        TelamonButton { text: "Disabled"; variant: TelamonButton.Destructive; enabled: false }
        TelamonButton { text: "Busy"; variant: TelamonButton.Destructive; busy: true; _spinnerAnimated: root.animate }

        TelamonButton { text: "Ghost"; variant: TelamonButton.Ghost }
        TelamonButton { text: "Symbol"; variant: TelamonButton.Ghost; symbol: Symbols.codepoint("home") }
        TelamonButton { text: "Checked"; variant: TelamonButton.Ghost; checkable: true; checked: true }
        TelamonButton { text: "Disabled"; variant: TelamonButton.Ghost; enabled: false }
        TelamonButton { text: "Busy"; variant: TelamonButton.Ghost; busy: true; _spinnerAnimated: root.animate }

        // The old way to ask for the prominent look, and an icon from the theme.
        TelamonButton { text: "prominent"; prominent: true }
        TelamonButton { text: "Icon"; icon.name: "document-save" }
    }
}
