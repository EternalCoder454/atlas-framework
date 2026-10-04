import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// SecondaryButton with a chevron that opens a menu. Put QQC2.MenuItem children inside.
SecondaryButton {
    id: control

    default property alias items: menu.contentData

    rightPadding: control.mirrored ? leftPadding : leftPadding + Kirigami.Units.iconSizes.small
    leftPadding: control.mirrored ? Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing + Kirigami.Units.iconSizes.small : Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
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
        x: control.mirrored ? Kirigami.Units.smallSpacing + 2 : parent.width - width - Kirigami.Units.smallSpacing - 2
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
