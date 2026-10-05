import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// An inline banner above the content: "File changed on disk", "Could not
// save". `type` tints it: "info" with the accent, "warning" and "error" with
// the theme's neutral and negative colours. Each entry of `actions` (a
// QQC2.Action) becomes a button at the trailing end; with `closable` a small
// cross dismisses it (`closeName` is its accessible name and tooltip).
//
// Use `shown` rather than `visible`, which cannot be animated. A dismissed
// banner holds `shown` false with a Binding, so an app's own `shown` binding
// survives. See docs/reference/atlas-ui/info-banner.md.
Item {
    id: control

    property string type: "info"
    property string text
    property list<QtObject> actions
    property bool closable: false
    property bool shown: true
    // The close button's accessible name and tooltip.
    property string closeName: qsTr("Close")

    readonly property bool dismissed: priv.dismissed

    signal closed

    readonly property color tint: type === "error" ? Kirigami.Theme.negativeTextColor : type === "warning" ? Kirigami.Theme.neutralTextColor : AtlasStyle.accent
    readonly property string iconName: type === "error" ? "dialog-error" : type === "warning" ? "dialog-warning" : "dialog-information"
    implicitWidth: Kirigami.Units.gridUnit * 20
    implicitHeight: Math.round(card.implicitHeight * card.progress)
    visible: card.progress > 0
    clip: card.progress < 1
    Accessible.role: Accessible.Alert
    Accessible.name: control.text
    Accessible.description: control.type === "error" ? qsTr("Error") : control.type === "warning" ? qsTr("Warning") : qsTr("Information")

    // Say it when it appears, or changes while it is up.
    // Both changes in one turn (text set, then shown) announce once, from a
    // queued call.
    QtObject {
        id: priv
        property bool announcePending: false
        property bool dismissed: false
        // Holds `shown` false while dismissed; the app's binding comes back
        // when the hold ends.
        readonly property Binding hold: Binding {
            target: control
            property: "shown"
            value: false
            when: priv.dismissed
            restoreMode: Binding.RestoreBindingOrValue
        }
        function queueAnnounce() {
            if (priv.announcePending) {
                return;
            }
            priv.announcePending = true;
            Qt.callLater(() => {
                priv.announcePending = false;
                if (control.shown && control.text.length > 0) {
                    control.Accessible.announce(control.text);
                }
            });
        }
    }
    onShownChanged: {
        // Written true while dismissed (an app showing it again): let go.
        if (control.shown && priv.dismissed) {
            priv.dismissed = false;
        }
        if (control.shown) {
            priv.queueAnnounce();
        }
    }
    onTypeChanged: priv.dismissed = false
    onTextChanged: {
        priv.dismissed = false;
        if (control.shown && control.visible) {
            priv.queueAnnounce();
        }
    }

    Rectangle {
        id: card

        // 0 when away, 1 when fully open (internal: not part of the API).
        property real progress: control.shown ? 1 : 0

        Behavior on progress {
            NumberAnimation {
                duration: AtlasStyle.durationShort
                easing.type: Easing.OutCubic
            }
        }

        width: parent.width
        implicitHeight: row.implicitHeight + AtlasStyle.spacingSmall * 2 + AtlasStyle.spacingLarge
        radius: AtlasStyle.radius
        color: Qt.alpha(control.tint, 0.14)
        border.width: 1
        border.color: Qt.alpha(control.tint, 0.4)
        opacity: card.progress

        RowLayout {
            id: row
            anchors.fill: parent
            anchors.leftMargin: AtlasStyle.spacingLarge
            anchors.rightMargin: AtlasStyle.spacingSmall + 2
            spacing: AtlasStyle.spacingLarge

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Layout.preferredWidth
                Layout.alignment: Qt.AlignVCenter
                source: control.iconName
            }
            QQC2.Label {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: control.text
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: Kirigami.Theme.textColor
            }
            Repeater {
                model: control.actions
                delegate: Loader {
                    id: slot
                    required property int index
                    required property var modelData
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: slot.index === 0 ? firstButton : otherButton

                                        Component {
                        id: firstButton
                        SecondaryButton {
                            text: slot.modelData.text
                            icon.name: slot.modelData.icon?.name ?? ""
                            enabled: slot.modelData.enabled
                            onClicked: slot.modelData.trigger()
                        }
                    }
                    Component {
                        id: otherButton
                        SecondaryButton {
                            text: slot.modelData.text
                            enabled: slot.modelData.enabled
                            onClicked: slot.modelData.trigger()
                        }
                    }
                }
            }
            T.AbstractButton {
                id: closeButton
                visible: control.closable
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Kirigami.Units.iconSizes.small + AtlasStyle.spacingSmall * 2
                implicitHeight: implicitWidth
                hoverEnabled: true
                focusPolicy: Qt.TabFocus // a click must not take the editor's focus
                Accessible.role: Accessible.Button
                Accessible.name: control.closeName
                AtlasToolTip {
                    text: control.closeName
                    shown: closeButton.hovered || closeButton.visualFocus
                }
                onClicked: {
                    priv.dismissed = true;
                    control.closed();
                }
                background: Rectangle {
                    radius: width / 2
                    color: Qt.alpha(Kirigami.Theme.textColor, closeButton.down ? 0.16 : closeButton.hovered ? 0.1 : 0)
                    AtlasFocusRing {
                        radius: parent.radius + gap
                        shown: closeButton.visualFocus
                    }
                }
                contentItem: Kirigami.Icon {
                    source: "window-close"
                    isMask: true
                    color: Kirigami.Theme.textColor
                    opacity: 0.7
                }
            }
        }
    }
}
