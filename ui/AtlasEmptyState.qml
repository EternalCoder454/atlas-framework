pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// What a list shows when it has nothing: a large symbol, a title, a line of
// explanation, and an optional action button, all centred. Fill the list's
// area with it and show it when the list is empty. The button appears when
// `actionText` is set and emits `triggered()`.
//
//   AtlasEmptyState {
//       anchors.fill: parent
//       visible: list.count === 0
//       symbol: Symbols.FolderOpen
//       title: qsTr("No files")
//       text: qsTr("Files you download will show up here.")
//       actionText: qsTr("Open Downloads")
//       onTriggered: openDownloads()
//   }
Item {
    id: control

    // A Material Symbol (Symbols.<Name>), or a theme icon by name.
    property int symbol: 0
    property string iconName
    property string title
    property string text
    // The button's label; empty for no button.
    property string actionText

    signal triggered

    implicitWidth: Math.max(Kirigami.Units.gridUnit * 18, column.implicitWidth + Kirigami.Units.gridUnit * 2)
    implicitHeight: column.implicitHeight + Kirigami.Units.gridUnit * 2

    Accessible.role: Accessible.Grouping
    Accessible.name: control.title
    Accessible.description: control.text

    QtObject {
        id: priv
        // The default font, bold and 30% larger; a pixel-sized theme font has
        // pointSize -1, so it scales its pixel size instead.
        readonly property font titleFont: {
            const f = Kirigami.Theme.defaultFont;
            const o = {
                "family": f.family,
                "bold": true
            };
            if (f.pixelSize > 0) {
                o.pixelSize = Math.round(f.pixelSize * 1.3);
            } else {
                o.pointSize = f.pointSize * 1.3;
            }
            return Qt.font(o);
        }
    }

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 22)
        spacing: Kirigami.Units.largeSpacing

        Item {
            id: iconSlot
            readonly property bool present: control.symbol !== 0 || control.iconName.length > 0
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
            Layout.preferredHeight: present ? Kirigami.Units.iconSizes.huge : 0
            visible: present
            Loader {
                anchors.centerIn: parent
                active: control.symbol !== 0
                sourceComponent: Symbol {
                    icon: control.symbol
                    size: Kirigami.Units.iconSizes.huge
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.45)
                }
            }
            Kirigami.Icon {
                anchors.fill: parent
                visible: control.symbol === 0 && control.iconName.length > 0
                source: control.iconName
                isMask: true
                color: Qt.alpha(Kirigami.Theme.textColor, 0.45)
            }
        }
        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            Layout.preferredHeight: visible ? implicitHeight : 0
            text: control.title
            font: priv.titleFont
            color: Kirigami.Theme.textColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            Layout.preferredHeight: visible ? implicitHeight : 0
            text: control.text
            font: Kirigami.Theme.defaultFont
            color: Qt.alpha(Kirigami.Theme.textColor, 0.7)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
        PrimaryButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.smallSpacing
            visible: control.actionText.length > 0
            Layout.preferredHeight: visible ? implicitHeight : 0
            text: control.actionText
            onClicked: control.triggered()
        }
    }
}
