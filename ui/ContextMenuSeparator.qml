import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A thin rule between groups of ContextMenuItems.
T.MenuSeparator {
    implicitWidth: Kirigami.Units.gridUnit * 8
    implicitHeight: visible ? TelamonStyle.spacingSmall * 2 + 1 : 0
    topPadding: TelamonStyle.spacingSmall
    bottomPadding: TelamonStyle.spacingSmall
    leftPadding: TelamonStyle.spacingLarge
    rightPadding: TelamonStyle.spacingLarge

    contentItem: Rectangle {
        implicitHeight: 1
        color: TelamonStyle.alpha(Kirigami.Theme.textColor, 0.12)
    }
}
