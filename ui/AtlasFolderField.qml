pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import org.kde.kirigami as Kirigami

// A folder chooser: a text field with the path and a Browse button that opens the
// system folder dialog (through the file chooser portal under Plasma). `path` is
// the text; `url` is the same as a file URL, read-only: "~" and "~/..." mean
// the home folder, a path that is not absolute gives an empty `url`. Nothing is
// run through a shell. `editable: false` leaves only the button. `edited()`
// is emitted when the user types a path or chooses one, not when the app sets it.
// The dialog is made on first use.
//
//   AtlasFolderField {
//       placeholderText: qsTr("Choose a folder")
//       onEdited: settings.backupFolder = path
//       Accessible.name: qsTr("Backup folder")
//   }
//
// See AtlasFileField for a file.
Item {
    id: control

    // The path as text.
    property string path
    // The path as a file URL; empty when `path` is empty or not absolute.
    readonly property url url: internals.toUrl(control.path)
    property string placeholderText
    // Checks the typed path (any QValidator, such as AtlasPathValidator), and
    // the message the field shows for a path it does not accept.
    property alias validator: field.validator
    property alias invalidText: field.invalidText
    // False: the path cannot be typed, only chosen.
    property bool editable: true
    // The dialog's title; empty for the system's own.
    property string title

    signal edited

    // The user's path, held on `path` for one turn so an app binding survives it.
    property string _edit
    property bool _editing: false
    readonly property Binding _hold: Binding {
        target: control
        property: "path"
        value: control._edit
        when: control._editing
        restoreMode: Binding.RestoreBinding
    }
    // The text field follows `path` even after the user typed in it.
    readonly property Binding _follow: Binding {
        target: field
        property: "text"
        value: control.path
    }
    function _release(): void {
        control._editing = false;
    }
    function _userSet(p: string): void {
        control._edit = p;
        control._editing = true;
        control.edited();
        Qt.callLater(control._release);
    }

    // The dialog (null until first use), and whether it has been seen open since
    // Browse was pressed: a dialog that cannot open reports no Loader error, so
    // the field looks for it shortly after open() and says so if it is not there.
    readonly property var _dialog: dialogLoader.item
    property bool _sawOpen: false
    // A test sets this to a component that never shows, to see the message.
    property Component _dialogOverride: null
    function _openDialog(): void {
        control._dialog.currentFolder = control.url;
        control._dialog.open();
        openCheck.restart();
    }
    Timer {
        id: openCheck
        interval: 400
        onTriggered: {
            if (!control._sawOpen && !(control._dialog && control._dialog.visible)) {
                internals.dialogFailed = true;
            }
        }
    }
    Connections {
        target: control._dialog
        function onVisibleChanged(): void {
            if (control._dialog.visible) {
                control._sawOpen = true;
            }
        }
    }

    QtObject {
        id: internals

        readonly property string home: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace(/^file:\/\//, "")

        function toUrl(p: string): url {
            let full = p;
            if (full === "~" || full.startsWith("~/")) {
                full = internals.home + full.slice(1);
            }
            if (full.length === 0 || full.charAt(0) !== "/") {
                return "";
            }
            return "file://" + full.split("/").map(encodeURIComponent).join("/");
        }
        // The local path of a file URL, or "" for any other scheme.
        function fromUrl(u: url): string {
            const s = u.toString();
            if (!s.startsWith("file://")) {
                return "";
            }
            try {
                return decodeURIComponent(s.slice(7));
            } catch (e) {
                return "";
            }
        }
        property bool dialogFailed: false
        function chosen(u: url): void {
            const p = fromUrl(u);
            if (p.length > 0 && p !== control.path) {
                control._userSet(p);
            }
        }
        function browse(): void {
            dialogFailed = false;
            control._sawOpen = false;
            if (control._dialog) {
                control._openDialog();
            } else {
                dialogLoader.active = true;
            }
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 22
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        AtlasTextField {
            id: field
            Layout.fillWidth: true
            placeholderText: control.placeholderText
            readOnly: !control.editable
            // Said when the dialog cannot be made; a typed or chosen path clears it.
            errorText: internals.dialogFailed ? qsTr("The dialog could not be opened.") : ""
            Accessible.name: control.placeholderText.length > 0 ? control.placeholderText : qsTr("Folder path")
            onTextEdited: {
                internals.dialogFailed = false;
                control._userSet(text);
            }
        }
        SecondaryButton {
            text: qsTr("Browse…")
            symbol: Symbols.FolderOpen
            onClicked: internals.browse()
        }
    }

    // The dialog is made on first use, so the field costs nothing before.
    Loader {
        id: dialogLoader
        active: false
        sourceComponent: control._dialogOverride ?? defaultDialog
        Component {
            id: defaultDialog
            FolderDialog {
                id: dialog
                parentWindow: control.Window.window
                title: control.title
                currentFolder: control.url
                onAccepted: internals.chosen(dialog.selectedFolder)
            }
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                internals.dialogFailed = true;
                active = false;
            }
        }
        onLoaded: control._openDialog()
    }
}
