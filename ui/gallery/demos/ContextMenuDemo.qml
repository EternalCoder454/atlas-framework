import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for ContextMenu: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 320
    implicitHeight: 290
    width: implicitWidth
    height: implicitHeight

    QQC2.ButtonGroup {
        id: sortGroup
    }

    ContextMenu {
        id: menu
        parent: root
        x: 30
        y: 20
        ContextMenuItem { text: "Details"; icon.name: "documentinfo"; shortcutText: "Alt+Return" }
        ContextMenuItem { text: "Pin"; checkable: true; checked: true }
        ContextMenuSeparator {}
        ContextMenuItem { text: "Name"; radio: true; checked: true; QQC2.ButtonGroup.group: sortGroup }
        ContextMenuItem { text: "Size"; radio: true; QQC2.ButtonGroup.group: sortGroup }
        ContextMenuItem { text: "Date"; radio: true; QQC2.ButtonGroup.group: sortGroup }
        ContextMenuSeparator {}
        ContextMenuItem { text: "End Task"; destructive: true; icon.name: "process-stop" }
        Component.onCompleted: open()
    }
}
