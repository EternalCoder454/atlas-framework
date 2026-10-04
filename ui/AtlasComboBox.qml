pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A rounded drop-down list: the current choice on a pill with a chevron, the
// choices in a raised card like ContextMenu's. `model`, `textRole`,
// `currentIndex` and `onActivated` work as in any ComboBox; `placeholderText`
// shows while nothing is chosen (currentIndex -1).
//
//   AtlasComboBox {
//       model: [qsTr("Light"), qsTr("Dark"), qsTr("Automatic")]
//       currentIndex: 2
//       onActivated: index => settings.theme = index
//   }
T.ComboBox {
    id: control

    property string placeholderText

    implicitWidth: Kirigami.Units.gridUnit * 12
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.9)
    leftPadding: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
    rightPadding: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.ComboBox
    Accessible.name: control.displayText.length > 0 ? control.displayText : control.placeholderText
    Accessible.description: control.placeholderText

    delegate: T.ItemDelegate {
        id: row

        required property var model
        required property int index

        width: ListView.view ? ListView.view.width : implicitWidth
        implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.8)
        leftPadding: Kirigami.Units.largeSpacing
        rightPadding: Kirigami.Units.largeSpacing
        hoverEnabled: true
        highlighted: control.highlightedIndex === index
        text: control.textRole.length === 0 ? row.model.modelData : Array.isArray(control.model) ? row.model.modelData[control.textRole] : row.model[control.textRole]

        Accessible.name: text

        background: Rectangle {
            radius: 6
            color: row.highlighted ? Qt.alpha(Kirigami.Theme.highlightColor, row.down ? 0.28 : 0.18) : "transparent"
        }
        contentItem: Row {
            spacing: Kirigami.Units.largeSpacing
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.small
                height: width
                // Only the chosen row makes the symbol.
                Loader {
                    anchors.centerIn: parent
                    active: control.currentIndex === row.index
                    sourceComponent: Symbol {
                        name: "check"
                        weight: 600
                        size: Kirigami.Units.iconSizes.small
                        color: Kirigami.Theme.textColor
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: row.availableWidth - Kirigami.Units.iconSizes.small - parent.spacing
                text: row.text
                font: Kirigami.Theme.defaultFont
                color: Kirigami.Theme.textColor
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
    }

    indicator: Kirigami.Icon {
        x: control.mirrored ? control.leftPadding : control.width - width - control.rightPadding
        y: Math.round((control.height - height) / 2)
        width: Kirigami.Units.iconSizes.small
        height: width
        source: "arrow-down"
        isMask: true
        color: Kirigami.Theme.textColor
        opacity: 0.6
    }

    contentItem: Text {
        leftPadding: control.mirrored ? control.indicator.width + Kirigami.Units.smallSpacing : 0
        rightPadding: control.mirrored ? 0 : control.indicator.width + Kirigami.Units.smallSpacing
        text: control.displayText.length > 0 ? control.displayText : control.placeholderText
        font: Kirigami.Theme.defaultFont
        color: control.displayText.length > 0 ? Kirigami.Theme.textColor : Qt.alpha(Kirigami.Theme.textColor, 0.5)
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }

    background: Rectangle {
        radius: height / 2
        color: Qt.alpha(Kirigami.Theme.textColor, control.down || control.popup.visible ? 0.14 : control.hovered ? 0.12 : 0.07)
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.14)
        Behavior on color {
            ColorAnimation {
                duration: Kirigami.Units.shortDuration
            }
        }
        AtlasFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }

    popup: T.Popup {
        y: control.height + Kirigami.Units.smallSpacing
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, Kirigami.Units.gridUnit * 16)
        padding: Kirigami.Units.smallSpacing
        margins: Kirigami.Units.smallSpacing
        modal: false
        closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent

        contentItem: ListView {
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            clip: true
            keyNavigationEnabled: true
        }

        background: Rectangle {
            radius: 10
            color: Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.5) : Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(1, 1, 1, 0.08))
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.16)
        }

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: Kirigami.Units.shortDuration
            }
        }
        exit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: Kirigami.Units.shortDuration
            }
        }
    }
}
