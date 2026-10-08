import QtQuick
import org.kde.kirigami as Kirigami

// The "Transparency and blur" row for an app's settings: a SectionRow with a
// switch bound to Appearance.transparency, the setting every Telamon app shares
// (`Transparency` under `[Appearance]` in telamonrc). Turning it off makes every
// window, menu, dialog and tooltip solid. When the compositor offers no blur
// the switch is off and dimmed and the subtitle says why; the title and the
// subtitle stay as readable as any row's.
//
//     Section {
//         TelamonTransparencySwitch {}
//     }
SectionRow {
    id: root

    title: qsTr("Transparency and blur")
    subtitle: Appearance.blurAvailable ? qsTr("Windows and menus are see-through and blur what is behind them. Turn off for solid surfaces.") : qsTr("Not available: the desktop's blur effect is off or not supported.")
    showSwitch: true
    // What the windows do, not only what is stored: without blur they are solid.
    switchChecked: Appearance.effective
    switchEnabled: Appearance.blurAvailable
    Accessible.name: root.title
    Accessible.description: root.subtitle

    leading: Symbol {
        icon: Symbols.BlurOn
        size: Kirigami.Units.iconSizes.smallMedium
        color: TelamonStyle.textMuted
    }

    onSwitchToggled: checked => Appearance.transparency = checked
    Component.onCompleted: Appearance.refresh()
}
