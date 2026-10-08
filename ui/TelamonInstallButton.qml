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
//   "remove"      Remove, in the negative colour (a destructive look)
//   "removing"    as "installing", for an uninstall; a press asks to cancel
//   "queued"      Queued, waiting for its turn; a press asks to cancel
//
//   TelamonInstallButton {
//       installState: app.state   // "install", "installing", ...
//       progress: app.progress    // 0 to 1; below 0 when the size is unknown
//       onClicked: app.act()
//       onCancelRequested: app.cancel()
//   }
//
// `clicked` fires for every press, as for any button; while installing a
// press in "installing", "removing" or "queued" also emits `cancelRequested`.
// `installedText` and the other labels
// can be replaced for an app that says "Launch" rather than "Open".
T.AbstractButton {
    id: control

    // One of the eight names above; any other value is drawn as "install".
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
    //: Button that uninstalls an app (a verb)
    property string removeText: qsTr("Remove")
    //: Button label of an app waiting in the queue for its turn to install
    property string queuedText: qsTr("Queued")

    // False holds the progress shimmer still (a screenshot).
    property bool animated: true

    signal cancelRequested

    QtObject {
        id: priv
        readonly property bool installing: control.installState === "installing"
        readonly property bool removing: control.installState === "removing"
        readonly property bool queued: control.installState === "queued"
        // The states that show a progress bar, and the ones a press cancels.
        readonly property bool working: priv.installing || priv.removing
        readonly property bool cancellable: priv.working || priv.queued
        readonly property bool indeterminate: priv.working && control.progress < 0
        readonly property real fraction: Math.max(0, Math.min(1, control.progress))
        // "install", "update" and any unknown or empty value are filled with the accent.
        readonly property bool filled: !priv.working && !priv.queued && control.installState !== "installed" && control.installState !== "error" && control.installState !== "remove"
        // The negative colour: a failed install and the destructive Remove.
        readonly property bool failed: control.installState === "error" || control.installState === "remove"
        readonly property color tint: priv.failed ? TelamonStyle.error : Kirigami.Theme.textColor
        readonly property string label: {
            switch (control.installState) {
            case "installing":
                //: Install button label while installing: a plain notice when the progress is unknown, else the percentage (%1 is a number)
                return priv.indeterminate ? qsTr("Installing…") : qsTr("%1%").arg(Math.round(priv.fraction * 100));
            case "removing":
                //: Install button label while removing: a plain notice when the progress is unknown, else the percentage (%1 is a number)
                return priv.indeterminate ? qsTr("Removing…") : qsTr("%1%").arg(Math.round(priv.fraction * 100));
            case "queued":
                return control.queuedText;
            case "remove":
                return control.removeText;
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
    leftPadding: TelamonStyle.spacingLarge + TelamonStyle.spacingSmall
    rightPadding: leftPadding
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    scale: control.down && control.enabled ? 0.97 : 1

    Accessible.role: Accessible.Button
    Accessible.name: priv.installing ? qsTr("Installing") : priv.removing ? qsTr("Removing") : priv.label
    Accessible.description: priv.working ? (priv.indeterminate ? qsTr("Press to cancel") : qsTr("%1%, press to cancel").arg(Math.round(priv.fraction * 100))) : priv.queued ? qsTr("Press to cancel") : ""
    Accessible.onPressAction: control.clicked()

    onClicked: {
        if (priv.cancellable) {
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
            duration: TelamonStyle.durationShort
            easing.type: Easing.OutCubic
        }
    }

    text: priv.label

    // A bright band, violet to sakura, across its parent (the progress fill).
    component Shimmer: Rectangle {
        property real phase: 0.5
        visible: !TelamonStyle.reducedMotion && !TelamonStyle.softwareRendering
        width: Math.max(parent.width * 0.6, Kirigami.Units.gridUnit * 2)
        height: parent.height
        x: -width + (parent.width + width) * phase
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: TelamonStyle.alpha(TelamonStyle.sakura, 0) }
            GradientStop { position: 0.5; color: TelamonStyle.alpha(TelamonStyle.sakura, 0.6) }
            GradientStop { position: 1; color: TelamonStyle.alpha(TelamonStyle.accent, 0) }
        }
        NumberAnimation on phase {
            running: priv.working && control.animated && control.visible && !TelamonStyle.reducedMotion && !TelamonStyle.softwareRendering
            from: 0
            to: 1
            duration: TelamonStyle.durationLong * 7
            loops: Animation.Infinite
        }
    }

    contentItem: Text {
        text: priv.label
        font.family: TelamonStyle.fontFamily
        font.pointSize: TelamonStyle.fontSizeBody
        color: priv.filled && control.enabled ? TelamonStyle.accentStrongText : priv.tint
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
            radius: TelamonStyle.radiusSmall
            color: {
                const accent = TelamonStyle.accentStrong;
                if (priv.filled) {
                    if (!control.enabled) {
                        return TelamonStyle.alpha(Kirigami.Theme.textColor, 0.12);
                    }
                    return control.down ? Qt.darker(accent, 1.2) : control.hovered ? Qt.lighter(accent, 1.12) : accent;
                }
                if (priv.failed) {
                    return TelamonStyle.alpha(priv.tint, control.down ? 0.28 : control.hovered ? 0.2 : 0.14);
                }
                return control.down ? TelamonStyle.pressed : control.hovered ? Qt.tint(TelamonStyle.control, TelamonStyle.hover) : TelamonStyle.control;
            }
            Behavior on color {
                ColorAnimation {
                    duration: TelamonStyle.durationShort
                }
            }

            // The progress: a thin bar along the bottom edge, inside the button, so
            // the label stays readable. Known progress grows from the leading
            // side; unknown progress slides a short segment to and fro. The
            // working part carries the violet-to-sakura shimmer (flat accent
            // under reduced motion).
            Rectangle {
                id: track
                visible: priv.working
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: TelamonStyle.radiusSmall
                anchors.rightMargin: TelamonStyle.radiusSmall
                anchors.bottomMargin: TelamonStyle.spacingXSmall
                height: TelamonStyle.spacingSmall - 1
                radius: TelamonStyle.radiusPill
                color: TelamonStyle.alpha(Kirigami.Theme.textColor, 0.15)
                clip: true

                Rectangle {
                    id: fill
                    visible: !priv.indeterminate
                    height: parent.height
                    radius: TelamonStyle.radiusPill
                    x: control.mirrored ? parent.width - width : 0
                    width: priv.fraction > 0 ? Math.min(parent.width, Math.max(height, parent.width * priv.fraction)) : 0
                    color: TelamonStyle.accent
                    clip: true
                    Shimmer {}
                    Behavior on width {
                        NumberAnimation {
                            duration: TelamonStyle.duration
                            easing.type: Easing.OutCubic
                        }
                    }
                }
                Rectangle {
                    id: slider
                    visible: priv.indeterminate
                    height: parent.height
                    radius: TelamonStyle.radiusPill
                    width: parent.width * 0.35
                    color: TelamonStyle.accent
                    clip: true
                    Shimmer {}
                    // Software rendering: 20 frames a second at most, no easing.
                    Timer {
                        property real cycle: 0
                        interval: 50
                        repeat: true
                        running: priv.indeterminate && control.visible && control.animated && TelamonStyle.duration > 0 && TelamonStyle.softwareRendering
                        // Start where the slider is, not at the left edge.
                        onRunningChanged: if (running) {
                            cycle = Math.min(1, Math.max(0, slider.x / Math.max(1, track.width - slider.width))) / 2;
                        }
                        onTriggered: {
                            cycle = (cycle + interval / (TelamonStyle.durationLong * 4)) % 1;
                            slider.x = Math.max(0, track.width - slider.width) * (cycle < 0.5 ? cycle * 2 : (1 - cycle) * 2);
                        }
                    }
                    SequentialAnimation on x {
                        running: priv.indeterminate && control.visible && control.animated && TelamonStyle.duration > 0 && !TelamonStyle.softwareRendering
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0
                            to: Math.max(0, track.width - slider.width)
                            duration: TelamonStyle.durationLong * 2
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            from: Math.max(0, track.width - slider.width)
                            to: 0
                            duration: TelamonStyle.durationLong * 2
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
                border.color: priv.filled ? "transparent" : TelamonStyle.controlBorder
            }
        }
        TelamonFocusRing {
            radius: bg.radius + gap
            shown: control.visualFocus
        }
    }
}
