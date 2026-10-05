import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasPreferencesPage: a dialog with one page, which
// shows without a sidebar. Fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 760
    implicitHeight: 560
    width: implicitWidth
    height: implicitHeight

    AtlasPreferencesDialog {
        parent: root
        title: "Settings"
        preferredWidth: 600
        AtlasPreferencesPage {
            title: "General"
            symbol: Symbols.Settings
            Section {
                title: "Editor"
                AtlasFormEntry {
                    label: "Font size"
                    AtlasSlider {
                        from: 8
                        to: 32
                        value: 14
                    }
                }
                AtlasFormEntry {
                    label: "Wrap lines"
                    AtlasSwitch {
                    }
                }
            }
        }
        Component.onCompleted: open()
    }
}
