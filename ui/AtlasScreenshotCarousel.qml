pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A row of screenshots, one at a time: previous and next buttons over the
// picture, dots below, and the arrow keys. Only the shown image and its two
// neighbours are loaded (asynchronously, at a bounded size). At most the first
// 50 sources are shown.
//
//   AtlasScreenshotCarousel {
//       sources: ["file:///a.png", "qrc:/b.png"]
//       Layout.fillWidth: true
//       Layout.preferredHeight: width * 9 / 16
//   }
//
// Where the pictures may come from: each source is resolved the way Qt reads
// it, and only local files (file:, no host), qrc: and image: (the app's own
// image providers) load. Pass absolute urls (`Qt.resolvedUrl("shots/a.png")`
// in the app's file): a relative one is read against Atlas.Ui's own files.
// Anything else (http:, ftp:, data:, a "//host" url, control characters) is
// refused: the slide shows the broken-image state, and the first refusal is
// logged with its scheme only.
// An app that shows remote screenshots either downloads them itself and
// passes the local files (best), or sets `allowRemote: true` for a trusted
// source; then https: also loads. Plain http: never does. Qt logs the whole
// url of an image that fails to load, so a remote url must carry no secret
// (no token in its query). A file: source should come from the app's own
// download or cache, not straight from metadata.
//
// `expandable: true` lets a click, or Enter, open a full-window viewer that
// belongs to the carousel. It shows the same sources under the same rules
// (local only, `allowRemote`), zoomed to fit; a double click toggles 1:1. The
// arrow keys move between images, Esc or a click outside the image closes it,
// and focus returns to the carousel. `expanded` tells whether it is open and
// can be set to open or close it. The open animation is off under reduced
// motion.
//
// With no sources it shows a short "No screenshots" message instead.
T.Control {
    id: control

    // Image urls (strings or url values).
    property var sources: []
    property int currentIndex: 0
    // Lets https: sources load; see above. http: is refused either way.
    property bool allowRemote: false
    // A click or Enter opens the full-window viewer.
    property bool expandable: false
    // Whether the viewer is open. Only an expandable carousel with images opens.
    property bool expanded: false

    // The viewer was opened, showing the image at `index`.
    signal opened(int index)
    // How many sources are shown: at most 50, and none for something that is
    // not a list.
    readonly property int count: {
        const list = control.sources;
        if (!list || typeof list !== "object") {
            return 0;
        }
        const n = Number(list.length);
        return Number.isFinite(n) ? Math.max(0, Math.min(50, Math.floor(n))) : 0;
    }

    QtObject {
        id: priv
        // Slides to `currentIndex`; a Behavior on it animates the move.
        property real position: control.currentIndex
        readonly property bool many: control.count > 12
        // Decoded size: the view's size rounded up so a resize does not
        // reload on every pixel, and never beyond what a screenshot needs.
        readonly property int decodeWidth: Math.min(2560, Math.ceil(Math.max(1, view.width) * 2 / 256) * 256)
        readonly property int decodeHeight: Math.min(1440, Math.ceil(Math.max(1, view.height) * 2 / 256) * 256)
        // Whether a refusal was logged already: one is enough.
        property bool loggedRefusal: false
        // The url a slide loads for `source`, or "" when it is refused (or
        // empty). Resolved by Qt, then checked against what may load, and that
        // same resolved url is what the image gets, so the check and the load
        // can't read the source differently.
        function vetted(source) {
            if (source === undefined || source === null || Array.isArray(source)
                    || (typeof source !== "string" && typeof source !== "object")) {
                return "";
            }
            const text = String(source);
            // Leading spaces (which Qt drops before the scheme), "//host" and
            // "\\host", and control characters (C0, DEL, C1) anywhere.
            if (text === "" || text.length > 8192 || /^[\s\u0085\ufeff]/.test(text)
                    || /^[\/\\]{2}/.test(text) || /[\x00-\x1f\x7f-\x9f]/.test(text)) {
                return "";
            }
            const resolved = Qt.resolvedUrl(text).toString();
            const m = /^([a-z][a-z0-9+.-]*):/i.exec(resolved);
            if (!m) {
                return "";
            }
            const scheme = m[1].toLowerCase();
            if (scheme === "file") {
                return /^file:(\/\/(localhost)?)?\/(?![\/\\])/i.test(resolved) ? resolved : "";
            }
            if (scheme === "qrc" || scheme === "image" || (scheme === "https" && control.allowRemote)) {
                return resolved;
            }
            return "";
        }
        // For the log: the scheme alone (the rest may hold a token), if short.
        function schemeOf(source) {
            const m = /^([a-zA-Z][a-zA-Z0-9+.-]{0,15}):/.exec(String(source ?? ""));
            return m ? m[1].toLowerCase() + ":" : "unusual";
        }
        function step(delta) {
            control.currentIndex = Math.max(0, Math.min(control.count - 1, control.currentIndex + delta));
        }
        Behavior on position {
            NumberAnimation {
                duration: AtlasStyle.duration
                easing.type: Easing.OutCubic
            }
        }
    }

    onCountChanged: {
        currentIndex = Math.max(0, Math.min(count - 1, currentIndex));
        if (count === 0) {
            expanded = false;
        }
    }
    onExpandableChanged: {
        if (!expandable) {
            expanded = false;
        }
    }
    // The viewer is a popup and needs a window. `expanded: true` at creation
    // waits for the window; with none by then, or set later with none, it
    // goes back to false instead of staying true with nothing shown.
    property bool _completed: false
    function _openViewer() {
        if (viewer.visible) {
            return;
        }
        viewer.open();
        opened(currentIndex);
    }
    onExpandedChanged: {
        if (expanded) {
            if (!expandable || count === 0) {
                expanded = false;
            } else if (control.Window.window) {
                _openViewer();
            } else if (_completed) {
                expanded = false;
            }
        } else {
            viewer.close();
        }
    }
    Window.onWindowChanged: {
        if (expanded && control.Window.window) {
            _openViewer();
        }
    }
    Component.onCompleted: {
        _completed = true;
        if (expanded) {
            if (control.Window.window && expandable && count > 0) {
                _openViewer();
            } else {
                expanded = false;
            }
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 30
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 30 * 9 / 16) + dots.height
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Screenshots")
    Accessible.onPressAction: {
        if (control.expandable) {
            control.expanded = true;
        }
    }
    //: Spoken position in the screenshot gallery: %1 is the current image, %2 how many there are
    Accessible.description: control.count > 0 ? qsTr("Image %1 of %2").arg(control.currentIndex + 1).arg(control.count) : qsTr("No screenshots")

    Keys.onPressed: event => {
        if (control.count === 0) {
            return;
        }
        const dir = control.mirrored ? -1 : 1;
        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (!control.expandable || event.isAutoRepeat) {
                return;
            }
            control.expanded = true;
            break;
        case Qt.Key_Left:
            priv.step(-dir);
            break;
        case Qt.Key_Right:
            priv.step(dir);
            break;
        case Qt.Key_Home:
            control.currentIndex = 0;
            break;
        case Qt.Key_End:
            control.currentIndex = control.count - 1;
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    background: null

    contentItem: Item {
        Rectangle {
            id: view
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: dots.top
            anchors.bottomMargin: dots.visible ? AtlasStyle.spacingSmall : 0
            radius: AtlasStyle.radius
            color: AtlasStyle.control
            border.width: 1
            border.color: AtlasStyle.separator

            // Empty state.
            Column {
                anchors.centerIn: parent
                spacing: AtlasStyle.spacingSmall
                visible: control.count === 0
                Symbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    icon: Symbols.ImageNotSupported
                    size: Kirigami.Units.iconSizes.large
                    color: AtlasStyle.textDisabled
                }
                Text {
                    text: qsTr("No screenshots")
                    font.family: AtlasStyle.fontFamily
                    font.pointSize: AtlasStyle.fontSizeBody
                    color: AtlasStyle.textMuted
                    textFormat: Text.PlainText
                }
            }

            Item {
                id: clip
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                visible: control.count > 0

                // A click opens the viewer; the buttons over the picture sit
                // above this item and keep their own clicks.
                TapHandler {
                    enabled: control.expandable
                    onTapped: {
                        control.forceActiveFocus(Qt.MouseFocusReason);
                        control.expanded = true;
                    }
                }
                HoverHandler {
                    enabled: control.expandable
                    cursorShape: Qt.PointingHandCursor
                }

                Repeater {
                    model: control.count
                    delegate: Item {
                        id: slide
                        required property int index
                        readonly property bool near: Math.abs(slide.index - control.currentIndex) <= 1
                        width: clip.width
                        height: clip.height
                        x: (slide.index - priv.position) * width * (control.mirrored ? -1 : 1)
                        visible: Math.abs(slide.index - priv.position) < 1.001
                        Accessible.role: Accessible.Graphic
                        //: Name of one screenshot: %1 is its number, %2 how many there are
                        Accessible.name: qsTr("Screenshot %1 of %2").arg(slide.index + 1).arg(control.count)
                        Accessible.description: slide.failed ? qsTr("The screenshot could not be loaded") : ""
                        Accessible.ignored: slide.index !== control.currentIndex

                        readonly property var rawSource: control.sources[slide.index] ?? ""
                        readonly property string loadSource: priv.vetted(slide.rawSource)
                        readonly property bool refused: slide.loadSource === "" && String(slide.rawSource) !== ""
                        // Set by the image: it could not be read.
                        property bool loadError: false
                        readonly property bool failed: slide.refused || slide.loadError

                        // The first refusal in this carousel, with the scheme only.
                        function logRefused() {
                            if (slide.refused && !priv.loggedRefusal) {
                                priv.loggedRefusal = true;
                                console.warn("AtlasScreenshotCarousel: refused screenshot " + (slide.index + 1) + ": " + priv.schemeOf(slide.rawSource) + " sources are not allowed (see allowRemote); later refusals are not logged");
                            }
                        }
                        onRefusedChanged: slide.logRefused()
                        Component.onCompleted: slide.logRefused()

                        Loader {
                            anchors.fill: parent
                            active: slide.near
                            sourceComponent: Item {
                                Image {
                                    id: img
                                    anchors.fill: parent
                                    anchors.margins: AtlasStyle.spacingSmall
                                    source: slide.loadSource
                                    asynchronous: true
                                    onStatusChanged: slide.loadError = img.status === Image.Error
                                    fillMode: Image.PreserveAspectFit
                                    sourceSize: Qt.size(priv.decodeWidth, priv.decodeHeight)
                                }
                                Column {
                                    anchors.centerIn: parent
                                    spacing: AtlasStyle.spacingSmall
                                    visible: img.status !== Image.Ready
                                    Symbol {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        icon: slide.failed ? Symbols.BrokenImage : Symbols.Image
                                        size: Kirigami.Units.iconSizes.large
                                        color: AtlasStyle.textDisabled
                                    }
                                    Text {
                                        visible: slide.failed
                                        text: qsTr("Screenshot unavailable")
                                        font.family: AtlasStyle.fontFamily
                                        font.pointSize: AtlasStyle.fontSizeCaption
                                        color: AtlasStyle.textMuted
                                        textFormat: Text.PlainText
                                        Accessible.ignored: true
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Repeater {
                model: [-1, 1]
                delegate: T.AbstractButton {
                    id: nav
                    required property int modelData
                    readonly property int target: control.currentIndex + nav.modelData
                    readonly property bool leftSide: (nav.modelData < 0) !== control.mirrored
                    readonly property bool available: nav.target >= 0 && nav.target < control.count
                    x: leftSide ? AtlasStyle.spacingSmall * 2 : view.width - width - AtlasStyle.spacingSmall * 2
                    y: Math.round((view.height - height) / 2)
                    width: Math.round(Kirigami.Units.gridUnit * 2)
                    height: width
                    visible: control.count > 1 && (nav.available || opacity > 0)
                    opacity: nav.available ? (nav.hovered || control.hovered ? 1 : 0.7) : 0
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    Accessible.role: Accessible.Button
                    Accessible.name: nav.modelData < 0 ? qsTr("Previous screenshot") : qsTr("Next screenshot")
                    onClicked: priv.step(nav.modelData)
                    Behavior on opacity {
                        NumberAnimation {
                            duration: AtlasStyle.durationShort
                        }
                    }
                    background: Rectangle {
                        radius: AtlasStyle.radiusPill
                        color: Qt.alpha(Kirigami.Theme.backgroundColor, nav.down ? 0.95 : 0.8) // floats over the screenshot, so it follows the window colour, not a token
                        border.width: 1
                        border.color: AtlasStyle.controlBorder
                    }
                    contentItem: Item {
                        Symbol {
                            anchors.centerIn: parent
                            icon: nav.leftSide ? Symbols.ChevronLeft : Symbols.ChevronRight
                            size: Kirigami.Units.iconSizes.smallMedium
                        }
                    }
                }
            }

            AtlasFocusRing {
                radius: view.radius + gap
                shown: control.visualFocus
            }
        }

        Row {
            id: dots
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            spacing: AtlasStyle.spacingSmall
            visible: control.count > 1
            height: visible ? Math.round(Kirigami.Units.gridUnit * 1.2) : 0

            Repeater {
                model: priv.many ? 0 : control.count
                delegate: Item {
                    id: dot
                    required property int index
                    readonly property bool current: dot.index === control.currentIndex
                    width: Kirigami.Units.gridUnit * 0.9
                    height: dots.height
                    Accessible.role: Accessible.Button
                    //: Name of the button that shows screenshot number %1
                    Accessible.name: qsTr("Screenshot %1").arg(dot.index + 1)
                    Accessible.onPressAction: control.currentIndex = dot.index
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.round(Kirigami.Units.gridUnit * (dot.current ? 0.5 : 0.4))
                        height: width
                        radius: width / 2
                        color: dot.current ? AtlasStyle.accent : AtlasStyle.textDisabled
                        Behavior on color {
                            ColorAnimation {
                                duration: AtlasStyle.durationShort
                            }
                        }
                    }
                    TapHandler {
                        onTapped: {
                            control.currentIndex = dot.index;
                            control.forceActiveFocus(Qt.MouseFocusReason);
                        }
                    }
                }
            }
            Text {
                visible: priv.many
                anchors.verticalCenter: parent.verticalCenter
                //: Counter shown on a screenshot: %1 is its number, %2 how many there are ("2 / 5")
                text: qsTr("%1 / %2").arg(control.currentIndex + 1).arg(control.count)
                font.family: AtlasStyle.fontFamily
                font.pointSize: AtlasStyle.fontSizeCaption
                color: AtlasStyle.textMuted
                textFormat: Text.PlainText
            }
        }

        // The full-window viewer. It reads the carousel's sources and
        // currentIndex, so what it may load is what the carousel may load.
        QQC2.Popup {
            id: viewer
            parent: QQC2.Overlay.overlay ?? control.Window.contentItem
            x: 0
            y: 0
            width: parent ? parent.width : 0
            height: parent ? parent.height : 0
            padding: 0
            modal: true
            focus: true
            closePolicy: QQC2.Popup.CloseOnEscape
            onClosed: {
                control.expanded = false;
                control.forceActiveFocus(Qt.OtherFocusReason);
            }
            onAboutToShow: zoom.actual = false

            enter: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: AtlasStyle.duration
                }
            }
            exit: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: AtlasStyle.durationShort
                }
            }

            // Dims the window; it follows the window colour, not a token.
            background: Rectangle {
                color: Qt.alpha(Kirigami.Theme.backgroundColor, AtlasStyle.highContrast ? 1 : 0.94)
            }

            component ViewerButton: T.AbstractButton {
                id: vb
                property int symbolIcon
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                width: Math.round(Kirigami.Units.gridUnit * 2.2)
                height: width
                Accessible.role: Accessible.Button
                background: Rectangle {
                    radius: AtlasStyle.radiusPill
                    color: vb.down ? AtlasStyle.pressed : vb.hovered ? AtlasStyle.hover : AtlasStyle.control
                    border.width: 1
                    border.color: AtlasStyle.controlBorder
                }
                contentItem: Item {
                    Symbol {
                        anchors.centerIn: parent
                        icon: vb.symbolIcon
                        size: Kirigami.Units.iconSizes.smallMedium
                    }
                }
            }

            contentItem: FocusScope {
                id: zoom
                objectName: "viewer"
                // False: the picture is zoomed to fit; true: shown 1:1.
                property bool actual: false
                readonly property int shown: control.currentIndex
                readonly property string source: viewer.visible ? priv.vetted(control.sources[zoom.shown] ?? "") : ""
                focus: true
                Accessible.role: Accessible.Pane
                Accessible.name: qsTr("Screenshot viewer")
                //: Spoken position in the screenshot viewer: %1 is the current image, %2 how many there are ("2 of 5")
                Accessible.description: qsTr("%1 of %2").arg(zoom.shown + 1).arg(control.count)
                onShownChanged: zoom.actual = false
                // A large image at 1:1 starts centred, not at its corner.
                onActualChanged: Qt.callLater(() => {
                    flick.contentX = Math.max(0, (flick.contentWidth - flick.width) / 2);
                    flick.contentY = Math.max(0, (flick.contentHeight - flick.height) / 2);
                })

                Keys.onPressed: event => {
                    const dir = control.mirrored ? -1 : 1;
                    switch (event.key) {
                    case Qt.Key_Left:
                        priv.step(-dir);
                        break;
                    case Qt.Key_Right:
                        priv.step(dir);
                        break;
                    case Qt.Key_Home:
                        control.currentIndex = 0;
                        break;
                    case Qt.Key_End:
                        control.currentIndex = control.count - 1;
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                }

                Flickable {
                    id: flick
                    anchors.fill: parent
                    contentWidth: stage.width
                    contentHeight: stage.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: zoom.actual

                    Item {
                        id: stage
                        width: Math.max(flick.width, zoom.actual ? img.implicitWidth : 0)
                        height: Math.max(flick.height, zoom.actual ? img.implicitHeight : 0)
                        Image {
                            id: img
                            objectName: "viewerImage"
                            anchors.centerIn: parent
                            width: zoom.actual ? implicitWidth : Math.max(0, flick.width - AtlasStyle.spacingXXLarge * 2)
                            height: zoom.actual ? implicitHeight : Math.max(0, flick.height - AtlasStyle.spacingXXLarge * 2)
                            source: zoom.source
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            // A bound on what a hostile picture can cost.
                            sourceSize: Qt.size(8192, 8192)
                            Accessible.role: Accessible.Graphic
                            //: Name of one screenshot: %1 is its number, %2 how many there are
                            Accessible.name: qsTr("Screenshot %1 of %2").arg(zoom.shown + 1).arg(control.count)
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: AtlasStyle.spacingSmall
                    visible: img.status !== Image.Ready
                    Symbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        icon: img.status === Image.Error || zoom.source === "" ? Symbols.BrokenImage : Symbols.Image
                        size: Kirigami.Units.iconSizes.large
                        color: AtlasStyle.textDisabled
                    }
                    Text {
                        visible: img.status === Image.Error || zoom.source === ""
                        text: qsTr("Screenshot unavailable")
                        font.family: AtlasStyle.fontFamily
                        font.pointSize: AtlasStyle.fontSizeCaption
                        color: AtlasStyle.textMuted
                        textFormat: Text.PlainText
                        Accessible.ignored: true
                    }
                }

                // A click outside the picture closes; a double click on it
                // toggles between fit and 1:1.
                TapHandler {
                    onTapped: (point, button) => {
                        const p = img.mapFromItem(zoom, point.position);
                        const pw = img.paintedWidth;
                        const ph = img.paintedHeight;
                        const inside = img.status === Image.Ready
                            && p.x >= (img.width - pw) / 2 && p.x <= (img.width + pw) / 2
                            && p.y >= (img.height - ph) / 2 && p.y <= (img.height + ph) / 2;
                        if (!inside) {
                            viewer.close();
                        } else if (tapCount === 2) {
                            zoom.actual = !zoom.actual;
                        }
                    }
                }

                ViewerButton {
                    id: closeButton
                    y: AtlasStyle.spacingLarge
                    x: control.mirrored ? AtlasStyle.spacingLarge : zoom.width - width - AtlasStyle.spacingLarge
                    symbolIcon: Symbols.Close
                    Accessible.name: qsTr("Close")
                    onClicked: viewer.close()
                }
                Repeater {
                    model: [-1, 1]
                    delegate: ViewerButton {
                        id: vnav
                        required property int modelData
                        readonly property int target: control.currentIndex + vnav.modelData
                        readonly property bool leftSide: (vnav.modelData < 0) !== control.mirrored
                        visible: control.count > 1 && vnav.target >= 0 && vnav.target < control.count
                        x: leftSide ? AtlasStyle.spacingLarge : zoom.width - width - AtlasStyle.spacingLarge
                        y: Math.round((zoom.height - height) / 2)
                        symbolIcon: vnav.leftSide ? Symbols.ChevronLeft : Symbols.ChevronRight
                        Accessible.name: vnav.modelData < 0 ? qsTr("Previous screenshot") : qsTr("Next screenshot")
                        onClicked: priv.step(vnav.modelData)
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.margins: AtlasStyle.spacingLarge
                    visible: control.count > 1
                    text: qsTr("%1 / %2").arg(zoom.shown + 1).arg(control.count)
                    font.family: AtlasStyle.fontFamily
                    font.pointSize: AtlasStyle.fontSizeCaption
                    color: AtlasStyle.textMuted
                    textFormat: Text.PlainText
                    Accessible.ignored: true
                }
            }
        }
    }
}
