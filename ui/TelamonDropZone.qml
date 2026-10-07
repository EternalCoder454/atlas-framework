pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// A dashed, rounded area that files can be dropped on, with a symbol, a line
// of text, a subtitle and an optional Browse button. A drag over it turns the
// border to the accent colour; a drag that carries nothing acceptable turns it
// to the error colour and says so. `dropped(urls)` carries only the accepted
// URLs: local files (file://), unless `allowRemote` is true, that match
// `nameFilters` (globs such as "*.png", case-insensitive; empty accepts all).
// A drag that will be accepted also makes the zone swell slightly (scale 1.02,
// the expressive spring), and it settles back when the drag leaves; under
// reduced motion it does not scale. The zone never opens or reads a file: the app does that with the URLs.
// Return and Space (and a click) emit `browseRequested()` as well, so an app
// opens its file dialog there; the Browse button shows when `browseText` is set.
//
//   TelamonDropZone {
//       Layout.fillWidth: true
//       text: qsTr("Drop images here")
//       subtitle: qsTr("PNG or JPEG")
//       nameFilters: ["*.png", "*.jpg"]
//       browseText: qsTr("Browse…")
//       onDropped: urls => model.addFiles(urls)
//       onBrowseRequested: fileDialog.open()
//   }
Item {
    id: control

    // A Material Symbol (Symbols.<Name>).
    property int symbol: Symbols.UploadFile
    property string text: qsTr("Drop files here")
    property string subtitle
    // The Browse button's label; empty for no button.
    property string browseText
    // MIME types a drag must offer to be considered.
    property list<string> acceptedKeys: ["text/uri-list"]
    // Globs the file names must match, such as ["*.png"]; empty accepts all.
    property list<string> nameFilters
    // Also accept URLs that are not local files (http, https, ...).
    property bool allowRemote: false

    // True while an acceptable drag is over the zone, and while a drag that
    // has nothing acceptable is.
    readonly property bool dragAccepted: priv.over && !priv.rejected
    readonly property bool dragRejected: priv.over && priv.rejected

    // The accepted URLs of a drop.
    signal dropped(list<url> urls)
    signal browseRequested

    // Whether a URL would be accepted (for the tests).
    function _accepts(url: url): bool {
        return priv.acceptUrl(url);
    }

    // Test hooks: force the drag states for the gallery's pictures.
    property bool _forceHover: false
    property bool _forceReject: false

    implicitWidth: Kirigami.Units.gridUnit * 22
    implicitHeight: column.implicitHeight + Kirigami.Units.gridUnit * 3

    activeFocusOnTab: true
    scale: control.dragAccepted ? 1.02 : 1
    Behavior on scale {
        enabled: !TelamonStyle.reducedMotion
        TelamonSpringAnimation {
            expressive: true
            fine: true
        }
    }
    opacity: enabled ? 1 : 0.5
    Accessible.role: Accessible.Button
    Accessible.name: control.text
    Accessible.description: control.subtitle
    Accessible.focusable: true
    Accessible.onPressAction: control.browseRequested()

    Keys.onReturnPressed: event => {
        if (!event.isAutoRepeat) {
            control.browseRequested();
        }
    }
    Keys.onEnterPressed: event => {
        if (!event.isAutoRepeat) {
            control.browseRequested();
        }
    }
    Keys.onSpacePressed: event => {
        if (!event.isAutoRepeat) {
            control.browseRequested();
        }
    }

    QtObject {
        id: priv
        property bool dragOver: false
        property bool dragBad: false
        // Focus that came from a click shows no ring.
        property bool byMouse: false
        readonly property bool over: dragOver || control._forceHover || control._forceReject
        readonly property bool rejected: control._forceReject || (dragOver && dragBad)
        readonly property color stroke: rejected ? TelamonStyle.error : over ? TelamonStyle.accent : TelamonStyle.controlBorder
        readonly property color tint: rejected ? TelamonStyle.alpha(TelamonStyle.error, 0.08) : over ? TelamonStyle.alpha(TelamonStyle.accent, 0.1) : "transparent"

        // A glob such as "*.png" as a case-insensitive whole-name test.
        function globToRegExp(glob: string): var {
            // [\s\S], not ".": a file name may hold a newline.
            const escaped = glob.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/[*?]/g, c => c === "*" ? "[\\s\\S]*" : "[\\s\\S]");
            return new RegExp("^" + escaped + "$", "i");
        }

        function acceptUrl(url: url): bool {
            const s = url.toString();
            // Local means file:/// (no host): file://server/... is a share.
            if (!control.allowRemote && !s.startsWith("file:///")) {
                return false;
            }
            if (control.nameFilters.length === 0) {
                return true;
            }
            const raw = s.split("?")[0].split("#")[0].split("/").pop();
            let name = raw;
            try {
                name = decodeURIComponent(raw);
            } catch (e) {
                // Not UTF-8 (a Linux name can be any bytes): match the
                // encoded name rather than drop every file in the drag.
            }
            for (let i = 0; i < control.nameFilters.length; ++i) {
                if (globToRegExp(control.nameFilters[i]).test(name)) {
                    return true;
                }
            }
            return false;
        }

        function acceptedUrls(urls: list<url>): list<url> {
            const out = [];
            for (let i = 0; i < urls.length; ++i) {
                if (acceptUrl(urls[i])) {
                    out.push(urls[i]);
                }
            }
            return out;
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        Accessible.ignored: true
        ShapePath {
            strokeColor: priv.stroke
            strokeWidth: priv.over ? 2 : 1
            strokeStyle: ShapePath.DashLine
            dashPattern: [4, 4]
            fillColor: priv.tint
            PathRectangle {
                x: 1
                y: 1
                width: control.width - 2
                height: control.height - 2
                radius: TelamonStyle.radiusLarge
            }
        }
    }

    TelamonFocusRing {
        radius: TelamonStyle.radiusLarge + gap
        shown: control.activeFocus && !priv.byMouse
    }

    DropArea {
        anchors.fill: parent
        keys: control.acceptedKeys
        onEntered: drag => {
            priv.dragBad = drag.hasUrls && priv.acceptedUrls(drag.urls).length === 0;
            priv.dragOver = true;
            // Always accept: a rejected enter may never get its exited, which would
            // leave the error border on. The drop itself refuses bad files.
        }
        onExited: priv.dragOver = false
        onDropped: drop => {
            priv.dragOver = false;
            if (!drop.hasUrls) {
                drop.accepted = false;
                return;
            }
            const urls = priv.acceptedUrls(drop.urls);
            if (urls.length === 0) {
                drop.accepted = false;
                return;
            }
            drop.acceptProposedAction();
            control.dropped(urls);
        }
    }

    onActiveFocusChanged: {
        if (!control.activeFocus) {
            priv.byMouse = false;
        }
    }

    TapHandler {
        // The Browse button accepts its own press, so a click on it never reaches
        // this handler: browseRequested() is emitted once.
        onTapped: {
            priv.byMouse = true;
            control.forceActiveFocus(Qt.MouseFocusReason);
            control.browseRequested();
        }
    }

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 22)
        spacing: TelamonStyle.spacing

        Symbol {
            Layout.alignment: Qt.AlignHCenter
            icon: control.symbol
            size: Kirigami.Units.iconSizes.large
            color: priv.rejected ? TelamonStyle.error : priv.over ? TelamonStyle.accent : TelamonStyle.textMuted
            Accessible.ignored: true
        }
        Text {
            Layout.fillWidth: true
            text: priv.rejected ? qsTr("Can't drop this here") : control.text
            font.pointSize: TelamonStyle.fontSizeBody
            font.weight: Font.DemiBold
            color: priv.rejected ? TelamonStyle.error : TelamonStyle.text
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
        Text {
            Layout.fillWidth: true
            visible: control.subtitle.length > 0 && !priv.rejected
            Layout.preferredHeight: visible ? implicitHeight : 0
            text: control.subtitle
            font.pointSize: TelamonStyle.fontSizeCaption
            color: TelamonStyle.textMuted
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
        SecondaryButton {
            id: browseButton
            objectName: "browseButton"
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: TelamonStyle.spacingSmall
            visible: control.browseText.length > 0
            Layout.preferredHeight: visible ? implicitHeight : 0
            text: control.browseText
            // The zone itself is the one Tab stop; it answers Return too.
            focusPolicy: Qt.NoFocus
            onClicked: control.browseRequested()
        }
    }
}
