import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// One cell of a StatusBar: a short text such as "Ln 3, Col 14". With
// `clickable` it gets a hover background and emits clicked(); with a `menu`
// (a QQC2.Menu or ContextMenu) a click pops it up above the cell. The
// StatusBar sets `leadingSeparator` to draw the thin line before the cell.
// A `symbol` (a Material Symbol) is drawn before the text. The menu opens
// just above the cell, from its leading edge (the trailing one when mirrored),
// moved to stay inside the window.
T.AbstractButton {
    id: control

    property bool clickable: false
    property string toolTip
    // A Material Symbol (Symbols.<Name>) shown before the text.
    property int symbol: 0
    // Opened above the item on a click; leave unset for none.
    property QtObject menu: null
    // The menu, untyped: a QQC2.Menu or ContextMenu.
    readonly property var _menuObject: control.menu
    // Set by the StatusBar.
    property bool leadingSeparator: false

    implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding + (leadingSeparator ? 1 : 0)
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.5)
    leftPadding: AtlasStyle.spacingLarge
    rightPadding: leftPadding
    hoverEnabled: true
    // A clickable cell is a Tab stop; a click doesn't take the editor's focus.
    focusPolicy: control.clickable ? Qt.TabFocus : Qt.NoFocus
    Accessible.role: clickable ? Accessible.Button : Accessible.StaticText
    Accessible.focusable: control.clickable
    Accessible.name: control.text
    Accessible.description: control.toolTip

    onClicked: {
        if (control.clickable && control.menu) {
            const m = control._menuObject;
            const w = m.width > 0 ? m.width : m.implicitWidth;
            const h = m.height > 0 ? m.height : m.implicitHeight;
            let x = control.mirrored ? control.width - w : 0;
            let y = -h - AtlasStyle.spacingSmall;
            const win = control.Window.window;
            if (win) {
                // Keep the menu inside the window, whichever side runs out.
                const gap = AtlasStyle.spacingSmall;
                const at = control.mapToItem(null, x, y);
                x += Math.max(gap, Math.min(at.x, win.width - w - gap)) - at.x;
                y += Math.max(gap, Math.min(at.y, win.height - h - gap)) - at.y;
            }
            m.popup(control, x, y);
        }
    }
    onVisibleChanged: {
        // The parent is the bar's row; the bar is above it.
        const bar = parent ? parent.parent : null;
        if (bar && typeof bar.refresh === "function") {
            bar.refresh();
        }
    }

    Keys.onReturnPressed: event => {
        if (control.clickable && !event.isAutoRepeat) {
            control.clicked();
        }
        event.accepted = control.clickable;
    }
    Keys.onEnterPressed: event => {
        if (control.clickable && !event.isAutoRepeat) {
            control.clicked();
        }
        event.accepted = control.clickable;
    }

    // Made when the cell is first hovered or focused, not for every cell.
    property var _tip: null
    function _ensureTip(): void {
        if (!control._tip) {
            control._tip = tipComponent.createObject(control);
        }
    }
    onHoveredChanged: if (control.hovered) control._ensureTip()
    onVisualFocusChanged: if (control.visualFocus) control._ensureTip()
    Component {
        id: tipComponent
        AtlasToolTip {
            text: control.toolTip
            shown: control.toolTip.length > 0 && (control.hovered || control.visualFocus)
        }
    }

    background: Item {
        // The leading edge is the left, or the right when mirrored.
        Rectangle {
            visible: control.leadingSeparator
            x: control.mirrored ? parent.width - width : 0
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: Math.round(parent.height * 0.6)
            color: AtlasStyle.separator
        }
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 1
            anchors.bottomMargin: 1
            anchors.leftMargin: control.leadingSeparator ? AtlasStyle.spacingXSmall : 0
            anchors.rightMargin: 0
            radius: AtlasStyle.radiusSmall
            color: !control.clickable ? "transparent" : control.down ? AtlasStyle.pressed : control.hovered ? AtlasStyle.hover : "transparent"
            AtlasFocusRing {
                radius: parent.radius + gap
                shown: control.visualFocus
            }
        }
    }

    contentItem: Item {
        id: content
        // From the text's own width, not the row's: the text is shrunk to fit.
        implicitWidth: label.implicitWidth + (control.symbol !== 0 ? content.symbolWidth + row.spacing : 0)
        implicitHeight: Math.max(label.implicitHeight, control.symbol !== 0 ? content.symbolWidth : 0)
        readonly property real symbolWidth: Math.round(Kirigami.Units.iconSizes.small * 1.2)
        Row {
            id: row
            anchors.centerIn: parent
            spacing: AtlasStyle.spacingSmall
            // Made only when used, so cells without one never load the fonts.
            Loader {
                active: control.symbol !== 0
                visible: active
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: Symbol {
                    icon: control.symbol
                    size: Math.round(Kirigami.Units.iconSizes.small * 1.2)
                    color: AtlasStyle.textMuted
                }
            }
            Text {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                // Elides when the cell is narrower than the text.
                width: Math.min(implicitWidth, Math.max(0, content.width - (control.symbol !== 0 ? content.symbolWidth + row.spacing : 0)))
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: control.text
                font.family: AtlasStyle.fontFamily
                font.pointSize: AtlasStyle.fontSizeCaption
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: AtlasStyle.textMuted
            }
        }
    }
}
