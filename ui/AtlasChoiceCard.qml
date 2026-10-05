pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// One of a few choices, shown as a picture with its name under it: a check
// circle by the name, a ring in the accent colour around the picture when
// chosen, and a fainter ring on hover and keyboard focus. `source` is the
// picture, `text` the name, `aspectRatio` the picture's width over its height
// (1.6, a 16:10 screen, by default). It is a checkable button: put the cards
// in a ButtonGroup, or set `autoExclusive: true`, so choosing one clears the
// others. A user's choice does not end an app's binding on `checked` (see
// docs/reference/atlas-ui/atlas-choice-card.md). Screen readers get a radio
// button named `text`. See that page for the rest.
//
//   ButtonGroup { id: group }
//   AtlasChoiceCard {
//       text: qsTr("Dark")
//       source: "qrc:/themes/dark.png"
//       ButtonGroup.group: group
//       checked: app.theme === "dark"
//       onToggled: if (checked) app.theme = "dark"
//   }
T.AbstractButton {
    id: control

    property url source
    property real aspectRatio: 1.6

    // The ratio kept to a usable number.
    readonly property real _ratio: Number.isFinite(control.aspectRatio) && control.aspectRatio > 0 ? control.aspectRatio : 1.6
    // The ring sits just outside the picture, inside the card's padding.
    readonly property real _ring: AtlasStyle.spacingSmall

    // A user's choice is held by a Binding for one turn, so an app binding on
    // `checked` is kept.
    property bool _edit: false
    property bool _editing: false
    readonly property Binding _hold: Binding {
        target: control
        property: "checked"
        value: control._edit
        when: control._editing
        restoreMode: Binding.RestoreBinding
    }
    function _release(): void {
        control._editing = false;
    }
    onToggled: {
        control._edit = control.checked;
        control._editing = true;
        Qt.callLater(control._release);
    }

    checkable: true
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    padding: control._ring
    implicitWidth: Kirigami.Units.gridUnit * 11 + leftPadding + rightPadding
    implicitHeight: column.implicitHeight + topPadding + bottomPadding

    Accessible.role: Accessible.RadioButton
    Accessible.name: control.text
    Accessible.checkable: true
    Accessible.checked: control.checked

    background: Item {
        AtlasFocusRing {
            gap: 2
            radius: AtlasStyle.radiusLarge + control._ring + gap
            shown: control.visualFocus
        }
    }

    contentItem: ColumnLayout {
        id: column
        spacing: AtlasStyle.spacing

        Item {
            id: frame
            Layout.fillWidth: true
            Layout.preferredHeight: width / control._ratio

            Rectangle {
                anchors.fill: parent
                anchors.margins: -control._ring
                radius: AtlasStyle.radiusLarge + control._ring
                color: "transparent"
                border.width: control.checked ? 3 : 2
                border.color: control.checked ? AtlasStyle.accent : control.enabled && (control.hovered || control.visualFocus) ? (AtlasStyle.highContrast ? AtlasStyle.accent : Qt.alpha(AtlasStyle.accent, 0.45)) : "transparent"
                Accessible.ignored: true
                Behavior on border.color {
                    ColorAnimation {
                        duration: AtlasStyle.durationShort
                    }
                }
                Behavior on border.width {
                    enabled: !AtlasStyle.reducedMotion
                    NumberAnimation {
                        duration: AtlasStyle.durationShort
                        easing.type: Easing.OutCubic
                    }
                }
            }
            // The empty frame shows until the picture has loaded, and stays if it never does.
            Rectangle {
                anchors.fill: parent
                radius: AtlasStyle.radiusLarge
                color: AtlasStyle.control
                Accessible.ignored: true
            }
            Image {
                id: picture
                anchors.fill: parent
                source: control.source
                visible: status === Image.Ready
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                // Decoded at about the size shown, not the file's.
                sourceSize: Qt.size(Math.ceil(Math.max(1, frame.width) * 2), Math.ceil(Math.max(1, frame.height) * 2))
                opacity: control.enabled ? 1 : 0.5
                // The software renderer draws no MultiEffect (a VM without a
                // GPU, where the installer runs): the picture is shown with
                // square corners rather than not at all.
                layer.enabled: visible && picture.GraphicsInfo.api !== GraphicsInfo.Software
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: mask
                }
                Accessible.ignored: true
            }
            Rectangle {
                id: mask
                anchors.fill: parent
                radius: AtlasStyle.radiusLarge
                layer.enabled: true
                visible: false
            }
            // A hairline edge, so a light picture stands out from a light card.
            Rectangle {
                anchors.fill: parent
                radius: AtlasStyle.radiusLarge
                color: "transparent"
                border.width: 1
                border.color: AtlasStyle.highContrast ? AtlasStyle.controlBorder : Qt.alpha(AtlasStyle.text, 0.15)
                Accessible.ignored: true
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: AtlasStyle.spacingSmall
            spacing: AtlasStyle.spacing

            // The check circle: filled with the accent colour when chosen.
            Rectangle {
                id: circle
                implicitWidth: Math.round(Kirigami.Units.gridUnit * 0.9)
                implicitHeight: implicitWidth
                radius: width / 2
                color: control.checked ? (control.enabled ? AtlasStyle.accent : Qt.alpha(AtlasStyle.accent, 0.4)) : "transparent"
                border.width: control.checked ? 0 : 1
                border.color: AtlasStyle.controlBorder
                Accessible.ignored: true
                Behavior on color {
                    ColorAnimation {
                        duration: AtlasStyle.durationShort
                    }
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Math.round(circle.width * 0.75)
                    height: width
                    visible: control.checked
                    source: "checkmark"
                    isMask: true
                    color: AtlasStyle.accentText
                    Accessible.ignored: true
                }
            }
            Text {
                // At most what is left of the picture's width beside the circle.
                Layout.maximumWidth: Math.max(0, frame.width - circle.width - AtlasStyle.spacing)
                text: control.text
                elide: Text.ElideRight
                font.family: AtlasStyle.fontFamily
                font.pointSize: AtlasStyle.fontSizeBody
                font.weight: Font.DemiBold
                color: control.enabled ? AtlasStyle.text : AtlasStyle.textDisabled
                textFormat: Text.PlainText
                Accessible.ignored: true
            }
        }
    }
}
