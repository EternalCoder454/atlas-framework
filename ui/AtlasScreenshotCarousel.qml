pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A row of screenshots, one at a time: previous and next buttons over the
// picture, dots below, and the arrow keys. Only the shown image and its two
// neighbours are loaded (asynchronously, at a bounded size), so a long list
// costs no more than a short one.
//
//   AtlasScreenshotCarousel {
//       sources: ["file:///a.png", "qrc:/b.png"]
//       Layout.fillWidth: true
//       Layout.preferredHeight: width * 9 / 16
//   }
//
// Where the pictures may come from: only file:, qrc:, image: and relative
// urls load. A source with any other scheme (http:, ftp:, data:, ...) is
// refused; the slide shows the broken-image state and the refusal is logged
// once. An app that shows remote screenshots either downloads them itself and
// passes the local files, or sets `allowRemote: true` for a trusted source;
// then https: also loads. Plain http: never does.
//
// With no sources it shows a short "No screenshots" message instead.
T.Control {
    id: control

    // Image urls (strings or url values).
    property var sources: []
    property int currentIndex: 0
    // Lets https: sources load; see above. http: is refused either way.
    property bool allowRemote: false
    readonly property int count: control.sources ? control.sources.length : 0

    QtObject {
        id: priv
        // Slides to `currentIndex`; a Behavior on it animates the move.
        property real position: control.currentIndex
        readonly property bool many: control.count > 12
        // Decoded size: the view's size rounded up so a resize does not
        // reload on every pixel, and never beyond what a screenshot needs.
        readonly property int decodeWidth: Math.min(2560, Math.ceil(Math.max(1, view.width) * 2 / 256) * 256)
        readonly property int decodeHeight: Math.min(1440, Math.ceil(Math.max(1, view.height) * 2 / 256) * 256)
        // Whether `source` may be loaded: no scheme (a relative url), or a local
        // one, or https: when allowed. The empty source is fine (nothing loads).
        function allowed(source) {
            const text = String(source ?? "");
            const m = /^([a-zA-Z][a-zA-Z0-9+.-]*):/.exec(text);
            if (!m) {
                return true;
            }
            const scheme = m[1].toLowerCase();
            return scheme === "file" || scheme === "qrc" || scheme === "image" || (scheme === "https" && control.allowRemote);
        }
        function schemeOf(source) {
            const m = /^([a-zA-Z][a-zA-Z0-9+.-]*):/.exec(String(source ?? ""));
            return m ? m[1].toLowerCase() : "";
        }
        function step(delta) {
            control.currentIndex = Math.max(0, Math.min(control.count - 1, control.currentIndex + delta));
        }
        Behavior on position {
            NumberAnimation {
                duration: Kirigami.Units.longDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    onCountChanged: currentIndex = Math.max(0, Math.min(count - 1, currentIndex))

    implicitWidth: Kirigami.Units.gridUnit * 30
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 30 * 9 / 16) + dots.height
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Screenshots")
    //: Spoken position in the screenshot gallery: %1 is the current image, %2 how many there are
    Accessible.description: control.count > 0 ? qsTr("Image %1 of %2").arg(control.currentIndex + 1).arg(control.count) : qsTr("No screenshots")

    Keys.onPressed: event => {
        if (control.count === 0) {
            return;
        }
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

    background: null

    contentItem: Item {
        Rectangle {
            id: view
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: dots.top
            anchors.bottomMargin: dots.visible ? Kirigami.Units.smallSpacing : 0
            radius: 14
            color: Qt.alpha(Kirigami.Theme.textColor, 0.06)
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.1)

            // Empty state.
            Column {
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing
                visible: control.count === 0
                Symbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    icon: Symbols.ImageNotSupported
                    size: Kirigami.Units.iconSizes.large
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                }
                Text {
                    text: qsTr("No screenshots")
                    font: Kirigami.Theme.defaultFont
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
                    textFormat: Text.PlainText
                }
            }

            Item {
                id: clip
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                visible: control.count > 0

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
                        readonly property bool refused: !priv.allowed(slide.rawSource)
                        // Set by the image: it could not be read.
                        property bool loadError: false
                        readonly property bool failed: slide.refused || slide.loadError

                        // Said once per refused source, with the scheme only (the rest may hold a token).
                        function logRefused() {
                            if (slide.refused) {
                                console.warn("AtlasScreenshotCarousel: refused screenshot " + (slide.index + 1) + ": the " + priv.schemeOf(slide.rawSource) + ": scheme is not allowed (see allowRemote)");
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
                                    anchors.margins: Kirigami.Units.smallSpacing
                                    source: slide.refused ? "" : slide.rawSource
                                    asynchronous: true
                                    onStatusChanged: slide.loadError = img.status === Image.Error
                                    fillMode: Image.PreserveAspectFit
                                    sourceSize: Qt.size(priv.decodeWidth, priv.decodeHeight)
                                }
                                Column {
                                    anchors.centerIn: parent
                                    spacing: Kirigami.Units.smallSpacing
                                    visible: img.status !== Image.Ready
                                    Symbol {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        icon: slide.failed ? Symbols.BrokenImage : Symbols.Image
                                        size: Kirigami.Units.iconSizes.large
                                        color: Qt.alpha(Kirigami.Theme.textColor, 0.4)
                                    }
                                    Text {
                                        visible: slide.failed
                                        text: qsTr("Screenshot unavailable")
                                        font: Kirigami.Theme.smallFont
                                        color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
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
                    x: leftSide ? Kirigami.Units.smallSpacing * 2 : view.width - width - Kirigami.Units.smallSpacing * 2
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
                            duration: Kirigami.Units.shortDuration
                        }
                    }
                    background: Rectangle {
                        radius: height / 2
                        color: Qt.alpha(Kirigami.Theme.backgroundColor, nav.down ? 0.95 : 0.8)
                        border.width: 1
                        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.16)
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
            spacing: Kirigami.Units.smallSpacing
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
                        color: dot.current ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.3)
                        Behavior on color {
                            ColorAnimation {
                                duration: Kirigami.Units.shortDuration
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
                font: Kirigami.Theme.smallFont
                color: Qt.alpha(Kirigami.Theme.textColor, 0.7)
                textFormat: Text.PlainText
            }
        }
    }
}
