pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// What a list shows when it has nothing: a large symbol, a title, a line of
// explanation, and an optional action button, all centred. Fill the list's
// area with it and show it when the list is empty. The button appears when
// `actionText` is set and emits `triggered()`; `actionSymbol` puts a Symbols
// icon on it.
//
//   TelamonEmptyState {
//       anchors.fill: parent
//       visible: list.count === 0
//       symbol: Symbols.FolderOpen
//       title: qsTr("No files")
//       text: qsTr("Files you download will show up here.")
//       actionText: qsTr("Open Downloads")
//       actionSymbol: Symbols.FolderOpen
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
    // A Symbols value shown on the action button; 0 for none.
    property int actionSymbol: 0

    signal triggered

    implicitWidth: Math.max(Kirigami.Units.gridUnit * 18, column.implicitWidth + Kirigami.Units.gridUnit * 2)
    // Always with the symbol: sized to it, the symbol shows.
    implicitHeight: column._full + Kirigami.Units.gridUnit * 2

    Accessible.role: Accessible.Grouping
    Accessible.name: control.title
    Accessible.description: control.text

    QtObject {
        id: priv
        // The default font, bold and 30% larger; a pixel-sized theme font has
        // pointSize -1, so it scales its pixel size instead.
        readonly property font titleFont: {
            const f = Qt.font({ "family": TelamonStyle.fontFamily, "pointSize": TelamonStyle.fontSizeBody });
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

    // Short of room, the symbol goes first; if the rest still does not fit,
    // it scrolls inside the control rather than drawing outside it.
    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, column.implicitHeight + Kirigami.Units.gridUnit * 2)
        interactive: contentHeight > height
        clip: interactive
        boundsBehavior: Flickable.StopAtBounds
        Accessible.ignored: true

        ColumnLayout {
            id: column
            // The column without the symbol and with it, from the parts rather
            // than the layout: neither depends on whether the symbol shows, so
            // a short pass cannot drop it for good.
            readonly property real _bare: {
                let h = 0;
                let n = 0;
                if (control.title.length > 0) {
                    h += titleText.implicitHeight;
                    ++n;
                }
                if (control.text.length > 0) {
                    h += bodyText.implicitHeight;
                    ++n;
                }
                if (control.actionText.length > 0) {
                    h += actionButton.implicitHeight + TelamonStyle.spacingSmall;
                    ++n;
                }
                return h + Math.max(0, n - 1) * column.spacing;
            }
            readonly property real _full: column._bare + (iconSlot.present ? Kirigami.Units.iconSizes.huge + (column._bare > 0 ? column.spacing : 0) : 0)
            x: Math.round((flick.width - width) / 2)
            y: Math.round(Math.max(Kirigami.Units.gridUnit, (flick.height - implicitHeight) / 2))
            width: Math.min(flick.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 22)
            spacing: TelamonStyle.spacingLarge

            Item {
                id: iconSlot
                readonly property bool present: control.symbol !== 0 || control.iconName.length > 0
                readonly property bool fits: control.height <= 0 || control.height + 0.5 >= column._full + Kirigami.Units.gridUnit * 2
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                Layout.preferredHeight: present ? Kirigami.Units.iconSizes.huge : 0
                visible: present && fits
                Loader {
                    anchors.centerIn: parent
                    active: control.symbol !== 0
                    sourceComponent: Symbol {
                        icon: control.symbol
                        size: Kirigami.Units.iconSizes.huge
                        color: TelamonStyle.textDisabled
                    }
                }
                TelamonIcon {
                    anchors.fill: parent
                    visible: control.symbol === 0 && control.iconName.length > 0
                    source: control.iconName
                    isMask: true
                    color: TelamonStyle.textDisabled
                }
            }
            Text {
                id: titleText
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
                id: bodyText
                Layout.fillWidth: true
                visible: text.length > 0
                Layout.preferredHeight: visible ? implicitHeight : 0
                text: control.text
                font.family: TelamonStyle.fontFamily
                font.pointSize: TelamonStyle.fontSizeBody
                color: TelamonStyle.textMuted
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                Accessible.ignored: true
            }
            PrimaryButton {
                id: actionButton
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: TelamonStyle.spacingSmall
                visible: control.actionText.length > 0
                Layout.preferredHeight: visible ? implicitHeight : 0
                text: control.actionText
                symbol: control.actionSymbol
                onClicked: control.triggered()
            }
        }
    }
}
