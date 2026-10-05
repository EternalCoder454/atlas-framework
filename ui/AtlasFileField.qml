pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import org.kde.kirigami as Kirigami

// A file chooser: a text field with the path and a Browse button that opens the
// system file dialog (through the file chooser portal under Plasma). `path` is
// the text; `url` is the same as a file URL, read-only: "~" and "~/..." mean
// the home folder, a path that is not absolute gives an empty `url`. Nothing is
// run through a shell. With `saveMode` the dialog asks for a name to save to,
// otherwise for an existing file; `nameFilters` are the dialog's filters
// ("Images (*.png *.jpg)"). `editable: false` leaves only the button. `edited()`
// is emitted when the user types a path or chooses one, not when the app sets it.
// The dialog is made on first use.
//
//   AtlasFileField {
//       placeholderText: qsTr("Choose a file")
//       nameFilters: [qsTr("Documents (*.pdf *.odt)")]
//       onEdited: settings.report = path
//       Accessible.name: qsTr("Report file")
//   }
//
// See AtlasFolderField for a folder.
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
    // The dialog's filters, e.g. ["Images (*.png *.jpg)", "All files (*)"].
    property list<string> nameFilters
    // True asks for a file to save to, false for one to open.
    property bool saveMode: false

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
            if (dialogLoader.item) {
                (dialogLoader.item as FileDialog).currentFile = control.url;
                (dialogLoader.item as FileDialog).open();
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
            Accessible.name: control.placeholderText.length > 0 ? control.placeholderText : qsTr("File path")
            onTextEdited: {
                internals.dialogFailed = false;
                control._userSet(text);
            }
        }
        SecondaryButton {
            text: qsTr("Browse…")
            symbol: control.saveMode ? Symbols.Save : Symbols.FileOpen
            onClicked: internals.browse()
        }
    }

    // The dialog is made on first use, so the field costs nothing before.
    Loader {
        id: dialogLoader
        active: false
        sourceComponent: FileDialog {
            id: dialog
            parentWindow: control.Window.window
            title: control.title
            fileMode: control.saveMode ? FileDialog.SaveFile : FileDialog.OpenFile
            nameFilters: control.nameFilters
            currentFile: control.url
            onAccepted: internals.chosen(dialog.selectedFile)
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                internals.dialogFailed = true;
                active = false;
            }
        }
        onLoaded: (item as FileDialog).open()
    }
}
