import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

AtlasPage {
    id: page

    required property var backend

    signal aboutRequested()

    title: qsTr("Home")

    // Live data is worth fetching only while someone can see it: the timers
    // below stop while the window is minimized or hidden.
    // It is also false while another page is pushed over this one.
    readonly property bool shown: page.visible && page.Window.visibility !== Window.Minimized && page.Window.visibility !== Window.Hidden

    StatusHero {
        iconName: "checkmark"
        headline: qsTr("Hello from an Atlas app")
        subtitle: page.backend.status

        PrimaryButton {
            text: qsTr("Refresh")
            enabled: !page.backend.busy
            onClicked: page.backend.refresh()
        }
        SecondaryButton {
            text: qsTr("Send a Notification")
            enabled: !page.backend.busy
            onClicked: page.backend.sendNotification()
        }
        TextButton {
            text: qsTr("About")
            onClicked: page.aboutRequested()
        }
    }

    Section {
        title: qsTr("Example")
        SectionRow {
            title: qsTr("A row")
            subtitle: qsTr("Put your settings and lists in Sections.")
            value: qsTr("Value")
        }
    }

    Section {
        id: charts
        title: qsTr("Live Chart")

        // Made-up readings: a slow wave with some noise, and a second series
        // under it. A real app binds `values` to its backend's history.
        property list<real> load: []
        property list<real> other: []
        property list<real> cores: []

        Timer {
            interval: 1000
            running: page.shown
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                const t = Date.now() / 1000;
                const next = (list, v) => list.concat([v]).slice(-60);
                charts.load = next(charts.load, 45 + 30 * Math.sin(t / 8) + Math.random() * 12);
                charts.other = next(charts.other, 20 + 10 * Math.sin(t / 5) + Math.random() * 6);
                charts.cores = Array.from({ length: 16 }, (_, i) => Math.max(0, Math.min(100, 50 + 45 * Math.sin(t / 6 + i) + Math.random() * 10 - 5)));
            }
        }

        LiveChart {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            values: charts.load
            values2: charts.other
            maximum: 100
            label: qsTr("Load")
            valueText: charts.load.length ? Math.round(charts.load[charts.load.length - 1]) + "%" : ""
            topText: "100%"
            spanText: qsTr("60 seconds")
        }
    }

    Section {
        title: qsTr("Usage Bars")

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            // Sizes in GiB here; a real app passes bytes and formats them.
            UsageBar {
                total: 32
                values: [17.2, 9.4]
                labels: [qsTr("Used"), qsTr("Cached"), qsTr("Free")]
                texts: ["17.2 GiB", "9.4 GiB", "5.4 GiB"]
            }

            MiniBars {
                values: charts.cores
            }
        }
    }

    Section {
        title: qsTr("Sidebar")

        // A sidebar column as an app would lay it out, here inside a Section.
        ColumnLayout {
            id: sidebar
            property string current: "nvme0n1"

            Layout.margins: Kirigami.Units.largeSpacing
            Layout.preferredWidth: Kirigami.Units.gridUnit * 13
            spacing: 2

            SidebarItem {
                Layout.fillWidth: true
                text: qsTr("Processor")
                icon.name: "cpu"
                tintIcon: false
                value: charts.load.length ? Math.round(charts.load[charts.load.length - 1]) + "%" : ""
                selected: sidebar.current === "cpu"
                onClicked: sidebar.current = "cpu"
            }
            SidebarGroup {
                text: qsTr("Disk")
                iconName: "drive-harddisk-symbolic"

                Repeater {
                    model: [
                        { name: "nvme0n1", label: "Samsung 990 Pro", rate: "12 MB/s" },
                        { name: "sda", label: "Backup", rate: "0 B/s" }
                    ]

                    SidebarItem {
                        required property var modelData
                        Layout.fillWidth: true
                        sub: true
                        text: modelData.label
                        icon.name: "drive-harddisk-symbolic"
                        value: modelData.rate
                        selected: sidebar.current === modelData.name
                        onClicked: sidebar.current = modelData.name
                    }
                }
            }
            SidebarGroup {
                text: qsTr("Network")
                iconName: "network-wired-symbolic"
                expanded: false

                SidebarItem {
                    Layout.fillWidth: true
                    sub: true
                    text: "enp5s0"
                    icon.name: "network-wired-symbolic"
                    value: "1.4 MB/s"
                    selected: sidebar.current === "enp5s0"
                    onClicked: sidebar.current = "enp5s0"
                }
            }
        }
    }

    SearchField {
        id: search
        Layout.alignment: Qt.AlignRight
        placeholderText: qsTr("Search Apps")
        onQueryChanged: table.rebuild()
    }

    // A table with made-up processes. A real app gives it a Rust
    // QAbstractItemModel that sorts itself and moves rows; this one sorts a
    // ListModel in JavaScript.
    DataTable {
        id: table
        Layout.preferredHeight: Kirigami.Units.gridUnit * 16
        sortRole: "cpu"
        depthRole: "depth"
        expandableRole: "expandable"
        expandedRole: "expanded"
        placeholderText: qsTr("No Apps Running")
        columns: [
            { title: qsTr("Name"), role: "name", fill: true, iconRole: "icon" },
            { title: qsTr("State"), role: "state", width: 6, cell: stateCell },
            { title: qsTr("CPU"), role: "cpu", width: 5, align: Qt.AlignRight, heat: 100, text: v => v.toFixed(1) + "%" },
            { title: qsTr("Memory"), role: "memory", width: 6, align: Qt.AlignRight, text: v => v.toFixed(0) + " MiB" }
        ]
        model: ListModel {
            id: apps
        }

        property var groupOpen: true
        readonly property var names: [["Firefox", "firefox"], ["Konsole", "utilities-terminal"], ["Dolphin", "system-file-manager"], ["Kate", "kate"], ["Atlas Updater", "system-software-update"], ["KWin", "kwin"], ["Plasma Shell", "plasma"], ["PipeWire", "audio-card"], ["Discover", "plasmadiscover"], ["Spectacle", "spectacle"], ["Okular", "okular"], ["Gwenview", "gwenview"]]
        property var load: names.map((_, i) => ({ cpu: (i * 7) % 30, memory: 80 + i * 37 }))

        // The rows in their new order, moved and updated in place the way a
        // real model does it: clearing would scroll the list back to the top
        // and lose the keyboard's place.
        function rebuild(holdOrder) {
            const order = table.sortOrder === Qt.AscendingOrder ? 1 : -1;
            const rows = table.names.map((n, i) => ({ name: n[0], icon: n[1], state: i === 5 ? "stopped" : "running", cpu: table.load[i].cpu, memory: table.load[i].memory, depth: 0, expandable: i === 0, expanded: i === 0 && table.groupOpen }));
            const q = search.query.toLowerCase();
            if (q) {
                rows.splice(0, rows.length, ...rows.filter(r => r.name.toLowerCase().includes(q)));
            }
            rows.sort((a, b) => (a[table.sortRole] < b[table.sortRole] ? -1 : a[table.sortRole] > b[table.sortRole] ? 1 : 0) * order);
            // Firefox's processes, under it while it is open.
            const at = rows.findIndex(r => r.expandable);
            if (table.groupOpen && at >= 0) {
                rows.splice(at + 1, 0, { name: "Web Content", icon: "", state: "running", cpu: 4.2, memory: 310, depth: 1, expandable: false, expanded: false }, { name: "GPU Process", icon: "", state: "running", cpu: 1.1, memory: 95, depth: 1, expandable: false, expanded: false });
            }
            if (holdOrder) {
                // New figures only, each row where it is.
                const byName = {};
                for (const r of rows) {
                    byName[r.name] = r;
                }
                for (let i = 0; i < apps.count; ++i) {
                    const r = byName[apps.get(i).name];
                    if (r) {
                        apps.set(i, r);
                    }
                }
                return;
            }
            for (let i = 0; i < rows.length; ++i) {
                let j = -1;
                for (let k = i; k < apps.count; ++k) {
                    if (apps.get(k).name === rows[i].name) {
                        j = k;
                        break;
                    }
                }
                if (j < 0) {
                    apps.insert(i, rows[i]);
                } else {
                    if (j !== i) {
                        apps.move(j, i, 1);
                    }
                    apps.set(i, rows[i]);
                }
            }
            if (apps.count > rows.length) {
                apps.remove(rows.length, apps.count - rows.length);
            }
        }

        onSortRoleChanged: rebuild()
        onSortOrderChanged: rebuild()
        onContextMenuRequested: (row, x, y) => rowMenu.popup(table, x, y)
        onToggleRequested: row => {
            groupOpen = !groupOpen;
            rebuild();
        }
        Component.onCompleted: rebuild()

        Timer {
            interval: 1000
            running: page.shown
            repeat: true
            onTriggered: {
                table.load = table.load.map((l, i) => ({ cpu: Math.max(0, Math.min(100, l.cpu + (Math.random() - 0.5) * 12 * (i % 3 + 1))), memory: l.memory }));
                // Hold the order still under the pointer, and while the
                // menu is open on a row.
                table.rebuild(table.pointerInside || rowMenu.opened);
            }
        }

        ContextMenu {
            id: rowMenu
            ContextMenuItem {
                text: qsTr("Details")
                icon.name: "documentinfo"
            }
            ContextMenuItem {
                text: qsTr("Open File Location")
                icon.name: "folder-open"
            }
            ContextMenuSeparator {}
            ContextMenuItem {
                text: qsTr("Stop")
                icon.name: "media-playback-pause"
            }
            ContextMenuItem {
                text: qsTr("End Task")
                icon.name: "process-stop"
                shortcutText: qsTr("Del")
                destructive: true
            }
        }

        Component {
            id: stateCell
            Row {
                property var value
                property var row
                property var column
                spacing: Kirigami.Units.smallSpacing
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Kirigami.Units.gridUnit * 0.5
                    height: width
                    radius: width / 2
                    color: parent.value === "running" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
                }
                QQC2.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.value === "running" ? qsTr("Running") : qsTr("Stopped")
                    opacity: 0.8
                }
            }
        }
    }

    Section {
        title: qsTr("Editor components")

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            TabBar {
                id: tabs
                Layout.fillWidth: true
                currentIndex: 0
                model: ListModel {
                    id: tabModel
                    ListElement { title: "Untitled"; modified: false; toolTip: "" }
                    ListElement { title: "notes.txt"; modified: true; toolTip: "/home/user/notes.txt" }
                    ListElement { title: "A document with a rather long file name.md"; modified: false; toolTip: "" }
                    ListElement { title: "todo.md"; modified: false; toolTip: "" }
                }
                onActivated: index => currentIndex = index
                onCloseRequested: index => {
                    tabModel.remove(index);
                    currentIndex = Math.min(currentIndex, tabModel.count - 1);
                }
                onNewRequested: {
                    tabModel.append({ title: qsTr("Untitled"), modified: false, toolTip: "" });
                    currentIndex = tabModel.count - 1;
                }
                onMoved: (from, to) => {
                    tabModel.move(from, to, 1);
                    currentIndex = to;
                }

                ToolbarButton {
                    icon.name: "application-menu"
                    text: qsTr("Menu")
                }
            }

            FindBar {
                Layout.fillWidth: true
                opened: true
                replaceVisible: true
                findText: "the"
                replaceText: "THE"
                matchCount: 12
                currentMatch: 3
                onClosed: opened = false
            }

            InfoBanner {
                Layout.fillWidth: true
                type: "info"
                text: qsTr("This file was changed by another program.")
                closable: true
                actions: [
                    QQC2.Action { text: qsTr("Reload") },
                    QQC2.Action { text: qsTr("Keep Mine") }
                ]
            }
            InfoBanner {
                Layout.fillWidth: true
                type: "warning"
                text: qsTr("This file is large. Editing may be slow, and a very long line of text shows how the message wraps when it has to.")
                actions: [QQC2.Action { text: qsTr("Open Read-Only") }]
            }
            InfoBanner {
                Layout.fillWidth: true
                type: "error"
                text: qsTr("Could not save the file: permission denied.")
                closable: true
                actions: [
                    QQC2.Action { text: qsTr("Save As") },
                    QQC2.Action { text: qsTr("Retry") }
                ]
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                ToolbarButton {
                    icon.name: "format-text-bold"
                    text: qsTr("Bold")
                    shortcutText: "Ctrl+B"
                    checkable: true
                    checked: true
                }
                ToolbarButton {
                    icon.name: "format-text-italic"
                    text: qsTr("Italic")
                    shortcutText: "Ctrl+I"
                    checkable: true
                }
                ToolbarButton {
                    icon.name: "format-text-underline"
                    text: qsTr("Underline")
                    shortcutText: "Ctrl+U"
                    checkable: true
                }
                ToolbarButton {
                    icon.name: "format-list-unordered"
                    text: qsTr("Bulleted List")
                }
                Item {
                    Layout.fillWidth: true
                }
                SecondaryButton {
                    text: qsTr("Show Toast")
                    onClicked: toast.show(qsTr("Copied to clipboard"))
                }
            }

            StatusBar {
                Layout.fillWidth: true
                StatusBarItem {
                    text: qsTr("Ln 12, Col 34")
                    toolTip: qsTr("Line and column")
                }
                StatusBarItem {
                    text: qsTr("128 words")
                }
                StatusBarItem {
                    text: "100%"
                    clickable: true
                    toolTip: qsTr("Zoom")
                }
                Item {
                    Layout.fillWidth: true
                }
                StatusBarItem {
                    text: "CRLF"
                    clickable: true
                    toolTip: qsTr("Line ending")
                    menu: QQC2.Menu {
                        QQC2.MenuItem { text: "CRLF" }
                        QQC2.MenuItem { text: "LF" }
                    }
                }
                StatusBarItem {
                    text: "UTF-8"
                    toolTip: qsTr("Encoding")
                }
            }
        }
    }

    Toast {
        id: toast
        parent: page
    }
}
