import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A thin rule between groups of ContextMenuItems.
T.MenuSeparator {
    implicitWidth: Kirigami.Units.gridUnit * 8
    implicitHeight: visible ? AtlasStyle.spacingSmall * 2 + 1 : 0
    topPadding: AtlasStyle.spacingSmall
    bottomPadding: AtlasStyle.spacingSmall
    leftPadding: AtlasStyle.spacingLarge
    rightPadding: AtlasStyle.spacingLarge

    contentItem: Rectangle {
        implicitHeight: 1
        color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
    }
}
