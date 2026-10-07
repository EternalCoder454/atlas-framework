import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonSplitButton (closed): fixed content, no timers or
// randomness. `animate` is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 340
    implicitHeight: 130
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        x: 16
        y: 16
        spacing: 16
        TelamonSplitButton {
            text: "Save"
            symbol: Symbols.Save
            ContextMenuItem { text: "Save As" }
        }
        TelamonSplitButton {
            text: "Install"
            prominent: true
            ContextMenuItem { text: "Install All" }
        }
    }
}
