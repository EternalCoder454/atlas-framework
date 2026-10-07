import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// A scrolling page with a large bold title and generous, centred margins.
// `headerTrailing` holds items at the trailing end of the title row (a button,
// a search field); the title elides before them. `maxContentWidth` (default 38
// grid units) is the widest the content grows. Inside a TelamonNavigationStack
// whose header shows, the header carries the title and the page doesn't
// repeat it. `status` (a TelamonStatus value) shows Loading, Empty, NoResults
// or Error in place of the content, under the title; see
// docs/reference/telamon-ui/telamon-page.md.
Item {
    id: root

    property string title
    property string subtitle
    // A spinner and `busyText` above the content, under the title row.
    property bool busy: false
    property string busyText
    // What the page shows in place of its content (a TelamonStatus value) and
    // the content of that: the heading, the explanation, a Symbols value (0
    // for the status's own) and one action. The title row and busy row stay.
    property int status: TelamonStatus.Ready
    property string statusTitle
    property string statusText
    property int statusSymbol: 0
    property TelamonAction statusAction: null
    default property alias content: body.data
    property real maxContentWidth: Kirigami.Units.gridUnit * 38
    property alias headerTrailing: headerRow.data
    // Set by TelamonNavigationStack while its header shows this page's title.
    property bool _titleInHeader: false

    Accessible.description: root.subtitle

    // False until one turn after creation: initial values are not announced
    // one by one. The first announcement comes late, so it does not talk over
    // the navigation stack's announcement of the page's title.
    property bool _ready: false
    // Test hook: replaces Accessible.announce().
    property var _announceHook: null
    onBusyChanged: root._announceBusy()
    onBusyTextChanged: root._announceBusy()
    Component.onCompleted: Qt.callLater(root._start)
    function _start(): void {
        root._ready = true;
        root._speak();
    }
    // Coalesced: only the text that has settled for a turn is announced.
    function _announceBusy(): void {
        if (root._ready) {
            Qt.callLater(root._speak);
        }
    }
    function _speak(): void {
        if (root.busy && root.busyText.length > 0) {
            if (root._announceHook) {
                root._announceHook(root.busyText);
            } else {
                root.Accessible.announce(root.busyText);
            }
        }
    }

    QQC2.ScrollView {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        // The scrollbar overlays the content. The desktop style would reserve
        // its width as padding, which narrows the viewport whenever it shows
        // and makes a binding loop on implicitWidth.
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        // A slim overlay scrollbar instead of the classic one with arrows.
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
            id: vbar
            parent: scroll
            x: scroll.width - width
            height: scroll.height
            policy: QQC2.ScrollBar.AsNeeded
            implicitWidth: 10
            padding: 2
            contentItem: Rectangle {
                implicitWidth: 6
                radius: width / 2
                color: TelamonStyle.alpha(Kirigami.Theme.textColor, vbar.pressed ? 0.45 : vbar.hovered ? 0.35 : 0.22)
                opacity: vbar.active ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: TelamonStyle.duration
                    }
                }
            }
            background: null
        }

        Item {
            width: scroll.width
            implicitHeight: col.implicitHeight + Kirigami.Units.gridUnit * 3

            ColumnLayout {
                id: col
                y: Kirigami.Units.gridUnit * 1.5
                width: Math.min(parent.width - Kirigami.Units.gridUnit * 3, root.maxContentWidth)
                x: Math.round((parent.width - width) / 2)
                spacing: Kirigami.Units.gridUnit * 1.2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: TelamonStyle.spacingLarge
                    visible: !root._titleInHeader || headerRow.visible

                    QQC2.Label {
                        Layout.fillWidth: true
                        visible: !root._titleInHeader
                        text: root.title
                        font.pointSize: TelamonStyle.fontSizeTitle
                        font.bold: true
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        Accessible.role: Accessible.Heading
                    }
                    Row {
                        id: headerRow
                        spacing: TelamonStyle.spacingSmall
                        visible: children.length > 0
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    // Closer to the title than the page's own spacing.
                    Layout.topMargin: -Kirigami.Units.gridUnit * 0.6
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    color: TelamonStyle.textMuted
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignLeft
                }

                // The busy row: slides in and out, and takes no room when idle.
                Item {
                    id: busyRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.busy ? busyContent.implicitHeight : 0
                    Layout.minimumHeight: root.busy ? busyContent.implicitHeight : 0
                    // Layouts give no size to a hidden item, so it stays shown while it shrinks.
                    visible: root.busy || Layout.preferredHeight > 0
                    clip: true
                    opacity: root.busy ? 1 : 0
                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: TelamonStyle.duration
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: TelamonStyle.duration
                        }
                    }
                    RowLayout {
                        id: busyContent
                        width: parent.width
                        spacing: TelamonStyle.spacingLarge
                        TelamonSpinner {
                            running: root.busy
                            animated: !TelamonStyle.reducedMotion
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            Accessible.role: Accessible.Indicator
                            Accessible.name: root.busyText
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: root.busyText
                            color: TelamonStyle.textMuted
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            // The spinner carries the name; reading both says it twice.
                            Accessible.ignored: true
                        }
                    }
                }

                // The page's content; hidden while a status shows. It adds no
                // gap when empty.
                ColumnLayout {
                    id: body
                    Layout.fillWidth: true
                    spacing: col.spacing
                    // With every item hidden it is empty: cancel the gap before it.
                    Layout.topMargin: implicitHeight > 0 ? 0 : -col.spacing
                    visible: root.status === TelamonStatus.Ready && children.length > 0
                }

                TelamonStatusView {
                    id: statusView
                    Layout.fillWidth: true
                    // The visible area under the title row: centred where the
                    // user looks, and it never makes the page scroll.
                    Layout.preferredHeight: Math.max(Kirigami.Units.gridUnit * 8, scroll.height - statusView.y - Kirigami.Units.gridUnit * 3)
                    status: root.status
                    title: root.statusTitle
                    text: root.statusText
                    symbol: root.statusSymbol
                    action: root.statusAction
                }
            }
        }
    }

    // A plain ScrollView doesn't follow keyboard focus: tabbing to a control
    // below the fold would leave it off screen. Scroll just enough to show it.
    // Not for a click: scrolling under the pointer could drop the click.
    function ensureVisible(item) {
        const flick = scroll.contentItem as Flickable;
        if (!item || !flick || item.focusReason === Qt.MouseFocusReason)
            return;
        for (let p = item.parent; p !== col; p = p.parent) {
            if (!p)
                return;
        }
        const r = item.mapToItem(flick.contentItem, 0, 0, item.width, item.height);
        const top = flick.contentY;
        const bottom = top + flick.height;
        if (r.y >= top && r.y + r.height <= bottom)
            return;
        const margin = TelamonStyle.spacingLarge;
        const maxY = Math.max(0, flick.contentHeight - flick.height);
        flick.cancelFlick();
        if (r.y < top)
            flick.contentY = Math.max(0, r.y - margin);
        else
            // Keep the top in view when the item is taller than the page.
            flick.contentY = Math.min(maxY, r.y - margin, r.y + r.height + margin - flick.height);
    }

    Connections {
        target: root.Window.window
        enabled: root.visible
        function onActiveFocusItemChanged() {
            root.ensureVisible(root.Window.activeFocusItem);
        }
    }
}
