pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Panes side by side (or stacked) with a draggable divider in the Atlas look:
// a thin separator line inside a wider invisible grab area, tinted on hover
// and while dragged. Put the panes inside as children and size them with
// SplitView.preferredWidth / minimumWidth / fillWidth (SplitView.* attached
// properties, as on Qt's own SplitView).
//
//   AtlasSplitView {
//       stateKey: "main"          // remember the sizes between runs
//       Sidebar { SplitView.preferredWidth: 220; SplitView.minimumWidth: 140 }
//       Content { SplitView.fillWidth: true }
//   }
//
// `stateKey` (empty by default): when set, the sizes are saved under
// "AtlasSplitView-<stateKey>" in the app's settings file (AtlasSettings) a
// moment after a drag, and
// restored when the view is created. Apps with their own storage use
// saveSizes() (a base64 string) and restoreSizes(string) instead.
QQC2.SplitView {
    id: control

    // Names the saved sizes; empty keeps them for this run only.
    property string stateKey

    // The pane sizes as a base64 string, for the app's own storage.
    function saveSizes(): string {
        const buf = control.saveState();
        if (!buf) {
            return "";
        }
        const bytes = new Uint8Array(buf);
        let bin = "";
        for (let i = 0; i < bytes.length; ++i) {
            bin += String.fromCharCode(bytes[i]);
        }
        return Qt.btoa(bin);
    }

    // Applies sizes from saveSizes(); returns false for a string that is
    // empty or does not fit this view (nothing changes then).
    function restoreSizes(sizes: string): bool {
        if (typeof sizes !== "string" || sizes.length === 0) {
            return false;
        }
        let bin = "";
        try {
            bin = Qt.atob(sizes);
        } catch (e) {
            return false;
        }
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; ++i) {
            bytes[i] = bin.charCodeAt(i);
        }
        return control.restoreState(bytes.buffer);
    }

    function _scheduleSave() {
        if (control.stateKey.length > 0 && _ready) {
            saveTimer.restart();
        }
    }
    function _saveNow() {
        saveTimer.stop();
        if (control.stateKey.length > 0) {
            control._store.setValue("Sizes", control.saveSizes());
        }
    }
    property bool _ready: false

    onResizingChanged: if (!resizing) {
        _scheduleSave();
    }
    onWidthChanged: _scheduleSave()
    onHeightChanged: _scheduleSave()

    Component.onCompleted: {
        if (control.stateKey.length > 0) {
            control.restoreSizes(control._store.value("Sizes", ""));
        }
        _ready = true;
    }
    Component.onDestruction: if (saveTimer.running) {
        _saveNow();
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: control._saveNow()
    }

    // Only read and written when stateKey is set.
    readonly property AtlasSettings _store: AtlasSettings {
        group: control.stateKey.length > 0 ? "AtlasSplitView-" + control.stateKey : ""
    }

    handle: Item {
        id: handle

        readonly property bool _vertical: control.orientation === Qt.Vertical
        readonly property bool _active: QQC2.SplitHandle.hovered || QQC2.SplitHandle.pressed

        // The line is 1 px; the rest is the grab area.
        implicitWidth: handle._vertical ? control.width : 7
        implicitHeight: handle._vertical ? 7 : control.height

        Accessible.role: Accessible.Separator
        Accessible.name: qsTr("Pane divider")

        Rectangle {
            anchors.centerIn: parent
            width: handle._vertical ? parent.width : (handle._active ? 3 : 1)
            height: handle._vertical ? (handle._active ? 3 : 1) : parent.height
            radius: handle._active ? width / 2 : 0
            color: handle.QQC2.SplitHandle.pressed ? AtlasStyle.accent : handle.QQC2.SplitHandle.hovered ? Qt.alpha(AtlasStyle.accent, 0.6) : AtlasStyle.controlBorder
        }
        HoverHandler {
            cursorShape: handle._vertical ? Qt.SplitVCursor : Qt.SplitHCursor
        }
    }
}
