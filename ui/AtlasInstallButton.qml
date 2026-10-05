pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A pill button for installing an app, with its progress inside the pill:
// the accent fills it from the left as the download goes. Its `installState` says
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

    contentItem: Text {
        text: priv.label
        font: Kirigami.Theme.defaultFont
        color: priv.filled && control.enabled ? AtlasStyle.accentText : priv.tint
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
            radius: AtlasStyle.radiusPill
            color: {
                const accent = AtlasStyle.accent;
                if (priv.filled) {
                    if (!control.enabled) {
                        return Qt.alpha(Kirigami.Theme.textColor, 0.12);
                    }
                    return control.down ? Qt.darker(accent, 1.2) : control.hovered ? Qt.lighter(accent, 1.12) : accent;
                }
                if (priv.failed) {
                    return Qt.alpha(priv.tint, control.down ? 0.28 : control.hovered ? 0.2 : 0.14);
                }
                return Qt.alpha(Kirigami.Theme.textColor, control.down ? 0.2 : control.hovered ? 0.12 : 0.07);
            }
            Behavior on color {
                ColorAnimation {
                    duration: AtlasStyle.durationShort
                }
            }

            // The progress, inside the pill: a pill of its own, as in AtlasProgressBar.
            // Known progress grows from the left; unknown progress slides a second
            // pill to and fro. Both stay within the pill's bounds.
            Rectangle {
                id: fill
                visible: priv.installing && !priv.indeterminate
                x: 0
                height: parent.height
                radius: AtlasStyle.radiusPill
                width: priv.fraction > 0 ? Math.min(parent.width, Math.max(height, parent.width * priv.fraction)) : 0
                color: Qt.alpha(AtlasStyle.accent, 0.55)
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
                x: 0
                height: parent.height
                radius: AtlasStyle.radiusPill
                width: Math.min(parent.width, parent.width * 0.35)
                color: Qt.alpha(AtlasStyle.accent, 0.55)
                SequentialAnimation on x {
                    running: priv.indeterminate && control.visible && AtlasStyle.duration > 0
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: 0
                        to: Math.max(0, bg.width - slider.width)
                        duration: AtlasStyle.durationLong * 2
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        from: Math.max(0, bg.width - slider.width)
                        to: 0
                        duration: AtlasStyle.durationLong * 2
                        easing.type: Easing.InOutQuad
                    }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Kirigami.Theme.textColor, priv.filled ? 0 : 0.14)
            }
        }
        AtlasFocusRing {
            radius: bg.radius + gap
            shown: control.visualFocus
        }
    }
}
