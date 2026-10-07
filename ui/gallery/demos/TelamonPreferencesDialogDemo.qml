import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonPreferencesDialog: three pages, the first shown.
// Fixed content, no timers or randomness. `animate` is switched off by
// tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 1000
    implicitHeight: 700
    width: implicitWidth
    height: implicitHeight

    TelamonPreferencesDialog {
        parent: root
        title: "Preferences"
        TelamonPreferencesPage {
            title: "General"
            symbol: Symbols.Settings
            Section {
                title: "Start"
                TelamonFormEntry {
                    label: "Open the last folder"
                    help: "When the app starts"
                    TelamonSwitch {
                        checked: true
                    }
                }
                TelamonFormEntry {
                    label: "Language"
                    TelamonComboBox {
                        model: ["System", "English", "Deutsch"]
                        currentIndex: 0
                    }
                }
            }
        }
        TelamonPreferencesPage {
            title: "Appearance"
            symbol: Symbols.Palette
            Section {
                TelamonFormEntry {
                    label: "Accent colour"
                    TelamonColorField {
                        color: "#3daee9" // telamon-lint: allow-raw (sample value)
                    }
                }
            }
        }
        TelamonPreferencesPage {
            title: "Network"
            symbol: Symbols.Language
            Section {
                TelamonFormEntry {
                    label: "Proxy port"
                    TelamonSpinBox {
                        from: 1
                        to: 65535
                        value: 8080
                    }
                }
            }
        }
        Component.onCompleted: open()
    }
}
