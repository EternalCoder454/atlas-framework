pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A button for installing an app, with its progress inside it:
// a thin bar along its bottom edge fills as the download goes. Its `installState` says
// what it offers and what a press means:
//
//   "install"     Install, in the accent colour
//   "installing"  the fill and a percentage; a press asks to cancel
//   "installed"   Open, in the soft style (nothing left to install)
//   "update"      Update, in the accent colour
//   "error"       Retry, in the negative colour
//
//   AtlasInstallButton {
//       installState: app.state   // "install", "installing", ...
//       progress: app.progress    // 0 to 1; below 0 when the size is unknown
//       onClicked: app.act()
//       onCancelRequested: app.cancel()
//   }
//
// `clicked` fires for every press, as for any button; while installing a
// press also emits `cancelRequested`. `installedText` and the other labels
// can be replaced for an app that says "Launch" rather than "Open".
T.AbstractButton {
    id: control

    // One of the five names above; any other value is drawn as "install".
    // (Item's own `state` stays free for an app's States.)
    property string installState: "install"

    // 0 to 1 while installing; a negative value means no figure is known.
    property real progress: -1
    property string installText: qsTr("Install")
    //: Button that opens an app that is already installed (a verb, not "open" as an adjective)
    property string installedText: qsTr("Open")
    //: Button that updates an installed app to a newer version (a verb)
    property string updateText: qsTr("Update")
    //: Button that tries a failed install again (a verb)
    property string errorText: qsTr("Retry")

    // False holds the progress shimmer still (a screenshot).
    property bool animated: true

    signal cancelRequested

    QtObject {
        id: priv
        readonly property bool installing: control.installState === "installing"
        readonly property bool indeterminate: priv.installing && control.progress < 0
        readonly property real fraction: Math.max(0, Math.min(1, control.progress))
        // "install", "update" and any unknown or empty value are filled with the accent.
        readonly property bool filled: control.installState !== "installing" && control.installState !== "installed" && control.installState !== "error"
        readonly property bool failed: control.installState === "error"
        readonly property color tint: priv.failed ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        readonly property string label: {
            switch (control.installState) {
            case "installing":
                //: Install button label while installing: a plain notice when the progress is unknown, else the percentage (%1 is a number)
                return priv.indeterminate ? qsTr("Installing…") : qsTr("%1%").arg(Math.round(priv.fraction * 100));
            case "installed":
                return control.installedText;
            case "update":
                return control.updateText;
            case "error":
                return control.errorText;
            default:
                return control.installText;
            }
        }
    }

    implicitWidth: Math.max(Math.round(Kirigami.Units.gridUnit * 5.5), contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.7)
    leftPadding: AtlasStyle.spacingLarge + AtlasStyle.spacingSmall
    rightPadding: leftPadding
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    scale: control.down && control.enabled ? 0.97 : 1

    Accessible.role: Accessible.Button
    Accessible.name: priv.installing ? qsTr("Installing") : priv.label
    Accessible.description: priv.installing ? (priv.indeterminate ? qsTr("Press to cancel") : qsTr("%1%, press to cancel").arg(Math.round(priv.fraction * 100))) : ""
    Accessible.onPressAction: control.clicked()

    onClicked: {
        if (priv.installing) {
            control.cancelRequested();
        }
    }
    Keys.onReturnPressed: event => {
        if (enabled && !event.isAutoRepeat) {
            control.clicked();
        }
    }
    Keys.onEnterPressed: event => {
        if (enabled && !event.isAutoRepeat) {
            control.clicked();
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: AtlasStyle.durationShort
            easing.type: Easing.OutCubic
        }
    }

    text: priv.label

    // A bright band, violet to sakura, across its parent (the progress fill).
    component Shimmer: Rectangle {
        property real phase: 0.5
        visible: !AtlasStyle.reducedMotion
        width: Math.max(parent.width * 0.6, Kirigami.Units.gridUnit * 2)
        height: parent.height
        x: -width + (parent.width + width) * phase
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(AtlasStyle.sakura, 0) }
            GradientStop { position: 0.5; color: Qt.alpha(AtlasStyle.sakura, 0.6) }
            GradientStop { position: 1; color: Qt.alpha(AtlasStyle.accent, 0) }
        }
        NumberAnimation on phase {
            running: priv.installing && control.animated && control.visible && !AtlasStyle.reducedMotion
            from: 0
            to: 1
            duration: AtlasStyle.durationLong * 7
            loops: Animation.Infinite
        }
    }

    contentItem: Text {
        text: priv.label
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeBody
        color: priv.filled && control.enabled ? AtlasStyle.accentStrongText : priv.tint
        opacity: control.enabled ? 1 : 0.75
        textFormat: Text.PlainText // no mnemonics
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Item {
        Rectangle {
            id: bg
            anchors.fill: parent
            radius: AtlasStyle.radiusSmall
            color: {
                const accent = AtlasStyle.accentStrong;
                if (priv.filled) {
                    if (!control.enabled) {
                        return Qt.alpha(Kirigami.Theme.textColor, 0.12);
                    }
                    return control.down ? Qt.darker(accent, 1.2) : control.hovered ? Qt.lighter(accent, 1.12) : accent;
                }
                if (priv.failed) {
                    return Qt.alpha(priv.tint, control.down ? 0.28 : control.hovered ? 0.2 : 0.14);
                }
                return control.down ? AtlasStyle.pressed : control.hovered ? Qt.tint(AtlasStyle.control, AtlasStyle.hover) : AtlasStyle.control;
            }
            Behavior on color {
                ColorAnimation {
                    duration: AtlasStyle.durationShort
                }
            }

            // The progress: a thin bar along the bottom edge, inside the button, so
            // the label stays readable. Known progress grows from the leading
            // side; unknown progress slides a short segment to and fro. The
            // working part carries the violet-to-sakura shimmer (flat accent
            // under reduced motion).
            Rectangle {
                id: track
                visible: priv.installing
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: AtlasStyle.radiusSmall
                anchors.rightMargin: AtlasStyle.radiusSmall
                anchors.bottomMargin: AtlasStyle.spacingXSmall
                height: AtlasStyle.spacingSmall - 1
                radius: AtlasStyle.radiusPill
                color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                clip: true

                Rectangle {
                    id: fill
                    visible: !priv.indeterminate
                    height: parent.height
                    radius: AtlasStyle.radiusPill
                    x: control.mirrored ? parent.width - width : 0
                    width: priv.fraction > 0 ? Math.min(parent.width, Math.max(height, parent.width * priv.fraction)) : 0
                    color: AtlasStyle.accent
                    clip: true
                    Shimmer {}
                    Behavior on width {
                        NumberAnimation {
                            duration: AtlasStyle.duration
                            easing.type: Easing.OutCubic
                        }
                    }
                }
                Rectangle {
                    id: slider
                    visible: priv.indeterminate
                    height: parent.height
                    radius: AtlasStyle.radiusPill
                    width: parent.width * 0.35
                    color: AtlasStyle.accent
                    clip: true
                    Shimmer {}
                    SequentialAnimation on x {
                        running: priv.indeterminate && control.visible && control.animated && AtlasStyle.duration > 0
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0
                            to: Math.max(0, track.width - slider.width)
                            duration: AtlasStyle.durationLong * 2
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            from: Math.max(0, track.width - slider.width)
                            to: 0
                            duration: AtlasStyle.durationLong * 2
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: priv.filled ? "transparent" : AtlasStyle.controlBorder
            }
        }
        AtlasFocusRing {
            radius: bg.radius + gap
            shown: control.visualFocus
        }
    }
}
