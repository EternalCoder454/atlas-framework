pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A card for one app in a store: its icon, name, a short summary, a line of
// rating and size, and an action at the end (a TelamonInstallButton unless
// you give another). Pressing the card, anywhere but on the action, emits
// `clicked`: open the app's page.
//
//   TelamonAppCard {
//       name: "Telamon Notepad"
//       summary: qsTr("Fast, plain text editing")
//       icon.name: "accessories-text-editor"      // or icon.source: a url
//       rating: 4.6                                // 0 hides it
//       sizeText: "12 MB"
//       installState: "installing"                 // see TelamonInstallButton
//       progress: 0.4
//       onClicked: openPage()
//       onActionClicked: install()
//       onCancelRequested: cancel()
//   }
//
// `verified: true` puts a "Verified" badge after the name. `compact: true`
// lays the card out as one list row (icon, name, summary, size, action) for
// an Installed or Updates list.
//
// Another action goes in `actionComponent`, a Component the card sizes and centres
// at its end: `actionComponent: Component { TextButton { text: qsTr("Manage") } }`.
T.AbstractButton {
    id: control

    property string name
    property string summary
    // Stars, 0 to 5; a value of 0 or less shows none.
    property real rating: 0
    // The download or installed size, already formatted ("12 MB").
    property string sizeText
    // A Material Symbol (Symbols.<Name>) for an app without an icon.
    property int symbol: 0
    // Forwarded to the default action; see TelamonInstallButton.
    property string installState: "install"
    property real progress: -1
    // Adds a "Verified" badge after the name.
    property bool verified: false
    // A one-row layout for lists: icon, name, summary, size, action.
    property bool compact: false
    // Replaces the TelamonInstallButton. Leave it alone to keep the default.
    property Component actionComponent: defaultAction

    signal actionClicked
    signal cancelRequested

    readonly property Component defaultAction: Component {
        TelamonInstallButton {
            installState: control.installState
            progress: control.progress
            //: Spoken label of a card detail: %1 is the app name, %2 the detail text
            Accessible.name: qsTr("%1: %2").arg(control.name).arg(text)
            onClicked: {
                if (installState !== "installing" && installState !== "removing" && installState !== "queued") {
                    control.actionClicked();
                }
            }
            onCancelRequested: control.cancelRequested()
        }
    }

    QtObject {
        id: priv
        // The default font in bold; `font.bold` cannot be set beside `font:`.
        readonly property font strong: {
            const f = Qt.font({ "family": TelamonStyle.fontFamily, "pointSize": TelamonStyle.fontSizeBody });
            const o = {
                "family": f.family,
                "bold": true
            };
            if (f.pixelSize > 0) {
                o.pixelSize = f.pixelSize;
            } else {
                o.pointSize = f.pointSize;
            }
            return Qt.font(o);
        }
        readonly property bool hasIcon: control.icon.name.length > 0 || control.icon.source.toString().length > 0
        readonly property real iconSide: Math.round(Kirigami.Units.gridUnit * (control.compact ? 2.2 : 3.4))
        // What a screen reader says: the rating in words, not as a bare number.
        readonly property string spokenMeta: {
            const parts = [];
            if (control.rating > 0) {
                //: Spoken rating of an app: %1 is a number from 0 to 5, such as 4.6
                parts.push(qsTr("Rating %1").arg(control.rating.toFixed(1)));
            }
            if (control.sizeText.length > 0) {
                parts.push(control.sizeText);
            }
            return parts.join(", ");
        }
        readonly property string meta: {
            const parts = [];
            if (control.rating > 0) {
                parts.push(control.rating.toFixed(1));
            }
            if (control.sizeText.length > 0) {
                parts.push(control.sizeText);
            }
            return parts.join(" · ");
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 24
    implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
    padding: control.compact ? TelamonStyle.spacing : TelamonStyle.spacingLarge
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    Accessible.name: control.name
    Accessible.description: [control.verified ? qsTr("Verified") : "", control.summary, priv.spokenMeta].filter(s => s.length > 0).join(", ")

    Keys.onReturnPressed: event => {
        // A custom action inside the card that has the focus keeps its own Return.
        if (!control.activeFocus) {
            event.accepted = false;
            return;
        }
        if (!event.isAutoRepeat) {
            control.clicked();
        }
    }
    Keys.onEnterPressed: event => {
        // A custom action inside the card that has the focus keeps its own Return.
        if (!control.activeFocus) {
            event.accepted = false;
            return;
        }
        if (!event.isAutoRepeat) {
            control.clicked();
        }
    }

    background: Item {
        Rectangle {
            id: card
            anchors.fill: parent
            radius: TelamonStyle.radius
            color: control.down ? TelamonStyle.pressed : control.hovered ? TelamonStyle.hover : TelamonStyle.control
            border.width: 1
            border.color: TelamonStyle.separator
            Behavior on color {
                ColorAnimation {
                    duration: TelamonStyle.durationShort
                }
            }
        }
        TelamonFocusRing {
            radius: card.radius + gap
            shown: control.visualFocus
        }
    }

    contentItem: RowLayout {
        spacing: TelamonStyle.spacingLarge

        Rectangle {
            Layout.preferredWidth: priv.iconSide
            Layout.preferredHeight: priv.iconSide
            Layout.alignment: Qt.AlignVCenter
            radius: Math.round(priv.iconSide * 0.225) // proportional to the icon, an app-icon squircle, not a token
            color: priv.hasIcon ? "transparent" : TelamonStyle.alpha(TelamonStyle.accent, 0.14)
            TelamonIcon {
                anchors.fill: parent
                visible: priv.hasIcon
                source: control.icon.name.length > 0 ? control.icon.name : control.icon.source
                isMask: false
            }
            // Made only when needed, so cards with an icon never load the fonts.
            Loader {
                anchors.centerIn: parent
                active: !priv.hasIcon
                sourceComponent: Symbol {
                    icon: control.symbol !== 0 ? control.symbol : Symbols.Apps
                    size: Math.round(priv.iconSide * 0.55)
                    color: TelamonStyle.accent
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Math.round(TelamonStyle.spacingSmall / 2)
            RowLayout {
                Layout.fillWidth: true
                spacing: TelamonStyle.spacingSmall
                Text {
                    Layout.fillWidth: true
                    text: control.name
                    font: priv.strong
                    color: Kirigami.Theme.textColor
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }
                Loader {
                    active: control.verified
                    visible: active
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: TelamonBadge {
                        type: "accent"
                        symbol: Symbols.Verified
                        accessibleName: qsTr("Verified")
                        Accessible.ignored: true // the card's description says it
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: control.summary.length > 0
                text: control.summary
                font.family: TelamonStyle.fontFamily
                font.pointSize: TelamonStyle.fontSizeCaption
                color: TelamonStyle.textMuted
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: control.compact ? 1 : 2
                elide: Text.ElideRight
            }
            RowLayout {
                visible: !control.compact && priv.meta.length > 0
                spacing: TelamonStyle.spacingSmall
                Loader {
                    active: control.rating > 0
                    visible: active
                    sourceComponent: Symbol {
                        icon: Symbols.Star
                        filled: true
                        size: Kirigami.Units.iconSizes.small
                        color: TelamonStyle.warning
                    }
                }
                Text {
                    text: priv.meta
                    font.family: TelamonStyle.fontFamily
                    font.pointSize: TelamonStyle.fontSizeCaption
                    color: TelamonStyle.textMuted
                    textFormat: Text.PlainText
                }
            }
        }

        // Compact rows show the size in a column of its own before the action.
        Text {
            visible: control.compact && control.sizeText.length > 0
            Layout.alignment: Qt.AlignVCenter
            text: control.sizeText
            font.family: TelamonStyle.fontFamily
            font.pointSize: TelamonStyle.fontSizeCaption
            color: TelamonStyle.textMuted
            textFormat: Text.PlainText
        }

        Loader {
            id: actionSlot
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: control.actionComponent
        }
    }
}
