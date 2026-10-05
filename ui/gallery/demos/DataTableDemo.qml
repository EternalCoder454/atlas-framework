import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for DataTable: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 460
    implicitHeight: 230
    width: implicitWidth
    height: implicitHeight

    ListModel {
        id: rows
        ListElement { name: "firefox"; cpu: 12.5; mem: 812 }
        ListElement { name: "plasmashell"; cpu: 4.2; mem: 420 }
        ListElement { name: "kwin_wayland"; cpu: 2.1; mem: 260 }
        ListElement { name: "systemd"; cpu: 0.1; mem: 18 }
        ListElement { name: "sshd"; cpu: 0; mem: 6 }
    }
    DataTable {
        anchors.fill: parent
        anchors.margins: 10
        model: rows
        sortRole: "cpu"
        resizableColumns: true
        columnsMenu: true
        selectionMode: DataTable.MultiSelection
        hiddenColumns: [3]
        Component.onCompleted: selectRows([1, 2])
        columns: [
            { title: "Name", role: "name", fill: true },
            { title: "CPU", role: "cpu", width: 5, align: Qt.AlignRight, heat: 20, text: v => v.toFixed(1) + "%" },
            { title: "Memory", role: "mem", width: 6, align: Qt.AlignRight, text: v => v + " MB" },
            { title: "Threads", role: "mem", width: 5, align: Qt.AlignRight }
        ]
        Accessible.name: "Processes"
    }
}
