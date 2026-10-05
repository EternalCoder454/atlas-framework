import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasPreferencesDialog: three pages, the first shown.
// Fixed content, no timers or randomness. `animate` is switched off by
// tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 1000
    implicitHeight: 700
    width: implicitWidth
    height: implicitHeight

    AtlasPreferencesDialog {
        parent: root
        title: "Preferences"
        AtlasPreferencesPage {
            title: "General"
            symbol: Symbols.Settings
            Section {
                title: "Start"
                AtlasFormEntry {
                    label: "Open the last folder"
                    help: "When the app starts"
                    AtlasSwitch {
                        checked: true
                    }
                }
                AtlasFormEntry {
                    label: "Language"
                    AtlasComboBox {
                        model: ["System", "English", "Deutsch"]
                        currentIndex: 0
                    }
                }
            }
        }
        AtlasPreferencesPage {
            title: "Appearance"
            symbol: Symbols.Palette
            Section {
                AtlasFormEntry {
                    label: "Accent colour"
                    AtlasColorField {
                        color: "#3daee9" // atlas-lint: allow-raw (sample value)
                    }
                }
            }
        }
        AtlasPreferencesPage {
            title: "Network"
            symbol: Symbols.Language
            Section {
                AtlasFormEntry {
                    label: "Proxy port"
                    AtlasSpinBox {
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
