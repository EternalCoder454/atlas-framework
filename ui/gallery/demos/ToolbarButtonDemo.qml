import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for ToolbarButton: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 400
    implicitHeight: 160
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8
        RowLayout {
            spacing: 6
            ToolbarButton { icon.name: "format-text-bold"; text: "Bold"; shortcutText: "Ctrl+B" }
            ToolbarButton { icon.name: "format-text-italic"; text: "Italic"; checkable: true; checked: true }
            ToolbarButton { icon.name: "format-text-underline"; text: "Underline"; enabled: false }
            ToolbarButton { icon.name: "go-down"; text: "More"; iconRotation: 90 }
        }
        // Symbols, unchecked and checked, and a focusable one showing its ring.
        RowLayout {
            spacing: 6
            ToolbarButton { symbol: Symbols.codepoint("format_bold"); text: "Bold" }
            ToolbarButton { symbol: Symbols.codepoint("format_italic"); text: "Italic"; checkable: true; checked: true }
            ToolbarButton { symbol: Symbols.codepoint("format_underlined"); text: "Underline"; checkable: true }
            ToolbarButton { symbol: Symbols.codepoint("link"); text: "Link"; enabled: false }
            ToolbarButton { id: focusable; symbol: Symbols.codepoint("search"); text: "Find"; focusable: true; Component.onCompleted: forceActiveFocus(Qt.TabFocusReason) }
        }
        // Round buttons, unchecked, checked and disabled.
        RowLayout {
            spacing: 6
            ToolbarButton { round: true; symbol: Symbols.codepoint("format_bold"); text: "Bold" }
            ToolbarButton { round: true; symbol: Symbols.codepoint("format_italic"); text: "Italic"; checkable: true; checked: true }
            ToolbarButton { round: true; symbol: Symbols.codepoint("link"); text: "Link"; enabled: false }
        }
    }
}
