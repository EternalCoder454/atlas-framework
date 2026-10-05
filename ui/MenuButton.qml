import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// SecondaryButton with a chevron that opens a menu. Put QQC2.MenuItem children inside.
// With an `action` it shows the action's text and, when it has one, its symbol.
SecondaryButton {
    id: control

    // Read duck-typed, so a plain Qt Action works too.
    readonly property var _actionObject: control.action
    symbol: _actionObject && _actionObject.symbol !== undefined ? _actionObject.symbol : 0

    default property alias items: menu.contentData

    rightPadding: control.mirrored ? leftPadding : leftPadding + Kirigami.Units.iconSizes.small
    leftPadding: control.mirrored ? AtlasStyle.spacingLarge + AtlasStyle.spacingSmall + Kirigami.Units.iconSizes.small : AtlasStyle.spacingLarge + AtlasStyle.spacingSmall
    Accessible.role: Accessible.ButtonMenu
    // Qt has no Accessible.expanded for QML: the state is the description,
    // and a change of it is announced (see the menu below).
    Accessible.description: menu.visible ? qsTr("Expanded") : qsTr("Collapsed")
    QtObject {
        id: priv
        function announceState() {
            control.Accessible.announce(menu.visible ? qsTr("Expanded") : qsTr("Collapsed"));
        }
    }
    onClicked: menu.popup(control, 0, control.height + 4)

    Kirigami.Icon {
        x: control.mirrored ? AtlasStyle.spacingSmall + 2 : parent.width - width - AtlasStyle.spacingSmall - 2
        anchors.verticalCenter: parent.verticalCenter
        source: "arrow-down"
        isMask: true
        color: control.textTint
        width: Kirigami.Units.iconSizes.small
        height: width
        opacity: control.enabled ? 0.8 : 0.4
        Accessible.ignored: true
    }

    QQC2.Menu {
        id: menu
        onVisibleChanged: priv.announceState()
        delegate: QQC2.MenuItem {
            Kirigami.MnemonicData.enabled: false
        }
    }
}
