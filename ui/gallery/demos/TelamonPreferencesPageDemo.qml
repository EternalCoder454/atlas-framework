import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonPreferencesPage: a dialog with one page, which
// shows without a sidebar. Fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 760
    implicitHeight: 560
    width: implicitWidth
    height: implicitHeight

    TelamonPreferencesDialog {
        parent: root
        title: "Settings"
        preferredWidth: 600
        TelamonPreferencesPage {
            title: "General"
            symbol: Symbols.Settings
            Section {
                title: "Editor"
                TelamonFormEntry {
                    label: "Font size"
                    TelamonSlider {
                        from: 8
                        to: 32
                        value: 14
                    }
                }
                TelamonFormEntry {
                    label: "Wrap lines"
                    TelamonSwitch {
                    }
                }
            }
        }
        Component.onCompleted: open()
    }
}
