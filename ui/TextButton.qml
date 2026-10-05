import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Link-styled button: accent text, no fill.
T.AbstractButton {
    id: control

    implicitWidth: label.implicitWidth + leftPadding + rightPadding
    implicitHeight: Math.max(AtlasStyle.controlHeight, label.implicitHeight + AtlasStyle.spacingSmall * 2)
    leftPadding: AtlasStyle.spacingSmall
    rightPadding: leftPadding
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: control.text
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

    contentItem: Text {
        id: label
        Accessible.ignored: true
        verticalAlignment: Text.AlignVCenter
        text: control.text
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeBody
        textFormat: Text.PlainText
        color: control.enabled ? AtlasStyle.accent : AtlasStyle.textDisabled
        Behavior on color {
            ColorAnimation {
                duration: AtlasStyle.durationShort
            }
        }
    }
    background: Rectangle {
        radius: AtlasStyle.radiusSmall
        // Grey hover and press, never the accent.
        color: !control.enabled ? "transparent" : control.down ? AtlasStyle.pressed : control.hovered ? AtlasStyle.hover : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: AtlasStyle.durationShort
            }
        }
        AtlasFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }
}
