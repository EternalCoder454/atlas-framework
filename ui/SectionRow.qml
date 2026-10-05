import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// One row in a Section: optional icon, title and subtitle on the left; value,
// extra items, a checkmark, a switch or a chevron on the right. A clickable row
// takes keyboard focus (Tab), shows a focus ring and activates with Enter or
// Space. A `radio` row also moves selection with Up and Down.
//
// Slots (since 1.4.0), all lists of items:
//   leading   items before the title (an avatar, a check box); they replace
//             the icon when set
//   content   replaces the title and subtitle column (a slider that spans the
//             row); give its items Layout.fillWidth
//   trailing  the default property: items at the trailing end (a button, a
//             combo box, a spin box). They keep their own focus and Tab order
//             after the row's, and a key they don't use doesn't activate the row.
// `busy` shows a spinner at the trailing edge in place of the value and the
// chevron; the row stays enabled but doesn't activate while it is busy.
FocusScope {
    id: root

    property string title
    property string subtitle
    property string value
    property string iconName
    property bool chevron: false
    // Rotate the chevron a quarter turn when `expanded` (disclosure rows).
    property bool disclosure: false
    property bool expanded: false
    property bool checkmark: false
    property bool radio: false
    property bool showSwitch: false
    property bool switchChecked: false
    property bool clickable: chevron
    property bool busy: false
    // Turn the busy spinner; off for a fixed arc, e.g. in screenshots.
    property bool animated: true
    property alias leading: leadingRow.data
    property alias content: contentRow.data
    default property alias trailing: trailingRow.data

    signal clicked
    signal switchToggled(bool checked)

    readonly property bool atlasRow: true
    // The row itself has keyboard focus, not an item inside it (activeFocus is
    // also true while a trailing control has it).
    readonly property bool _ownFocus: Window.window !== null && Window.window.activeFocusItem === root
    readonly property bool _canActivate: clickable && !busy
    readonly property bool _hasLeading: leadingRow.children.length > 0
    readonly property bool _hasContent: contentRow.children.length > 0
    readonly property bool mirrored: LayoutMirroring.enabled
    // The first visible row in a Section draws no separator above itself.
    readonly property bool isFirst: {
        var v = root.parent ? root.parent.visibleChildren : [];
        for (var i = 0; i < v.length; ++i) {
            if (v[i].atlasRow === true) {
                return v[i] === root;
            }
        }
        return true;
    }

    // AtlasStyle.Normal or AtlasStyle.Compact; Compact shrinks the height and
    // the vertical padding to about 75%. Follows the app-wide AtlasStyle.density
    // unless set here.
    property int density: AtlasStyle.density
    readonly property real _k: density === AtlasStyle.Compact ? 0.75 : 1

    Layout.fillWidth: true
    implicitHeight: Math.max(Math.round(Kirigami.Units.gridUnit * 2.5 * _k), rowLayout.implicitHeight + Math.round(AtlasStyle.spacingLarge * 1.6 * _k))
    activeFocusOnTab: root.clickable
    opacity: !root.enabled || (!root.clickable && root.chevron) ? 0.5 : 1

    // A switch row is exposed through its switch only, so the name is not read twice.
    Accessible.ignored: root.showSwitch
    Accessible.role: root.radio ? Accessible.RadioButton : (root.clickable ? Accessible.Button : Accessible.ListItem)
    Accessible.name: root.title
    Accessible.description: {
        const d = root.subtitle.length > 0 && root.value.length > 0 ? root.subtitle + ", " + root.value : root.subtitle + root.value;
        //: Spoken by a screen reader for a row that is working on something
        return root.busy ? (d.length > 0 ? d + ", " : "") + qsTr("Busy") : d;
    }
    Accessible.checkable: root.radio
    Accessible.checked: root.radio && root.checkmark
    Accessible.focusable: root.clickable
    Accessible.onPressAction: if (root._canActivate) root.clicked()
    // Qt lists Toggle first for a checkable row; assistive tools use it to pick a radio.
    Accessible.onToggleAction: if (root._canActivate && root.radio) root.clicked()

    Keys.onPressed: event => {
        root.byMouse = false;
        event.accepted = false;
    }
    Keys.onReturnPressed: event => root.activate(event)
    Keys.onEnterPressed: event => root.activate(event)
    Keys.onSpacePressed: event => root.activate(event)
    Keys.onDownPressed: event => root.step(true, event)
    Keys.onUpPressed: event => root.step(false, event)

    // True after a click: the focus ring is for keyboard focus only.
    property bool byMouse: false
    onActiveFocusChanged: {
        if (!root.activeFocus) {
            root.byMouse = false;
        } else if (!root.byMouse) {
            root.ensureVisible();
        }
    }

    function activate(event) {
        // A key a trailing control left alone is not for the row.
        if (!root._ownFocus) {
            event.accepted = false;
            return;
        }
        if (root._canActivate && !event.isAutoRepeat) {
            root.clicked();
        }
        event.accepted = root.clickable;
    }

    // Scroll the page so a row reached with Tab is on screen.
    function ensureVisible() {
        var f = root.parent;
        while (f && !(f.contentY !== undefined && f.contentHeight !== undefined && f.flickableDirection !== undefined)) {
            f = f.parent;
        }
        if (!f) {
            return;
        }
        var p = root.mapToItem(f.contentItem, 0, 0);
        var m = AtlasStyle.spacingSmall;
        if (p.y < f.contentY) {
            f.contentY = Math.max(0, p.y - m);
        } else if (p.y + root.height > f.contentY + f.height) {
            f.contentY = p.y + root.height - f.height + m;
        }
    }

    function step(forward, event) {
        if (!root.radio || !root._ownFocus || root.busy) {
            event.accepted = false;
            return;
        }
        var n = root.nextItemInFocusChain(forward);
        if (n && n.radio === true) {
            n.forceActiveFocus();
            n.clicked();
        } else {
            event.accepted = false;
        }
    }

    Rectangle {
        visible: !root.isFirst
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: AtlasStyle.spacingLarge + (root._hasLeading ? leadingRow.width + AtlasStyle.spacingLarge : (root.iconName.length > 0 ? Kirigami.Units.iconSizes.smallMedium + AtlasStyle.spacingLarge : 0))
        height: 1
        color: Qt.alpha(Kirigami.Theme.textColor, 0.1)
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 7
        color: Qt.alpha(Kirigami.Theme.textColor, tap.pressed ? 0.1 : 0.05)
        opacity: root._canActivate && hover.hovered ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: AtlasStyle.durationShort
            }
        }
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 7
        color: "transparent"
        border.width: 2
        border.color: Qt.alpha(AtlasStyle.focus, 0.85)
        visible: root._ownFocus && root.clickable && !root.byMouse
    }

    HoverHandler {
        id: hover
        enabled: root._canActivate
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: tap
        enabled: root._canActivate
        onTapped: {
            root.byMouse = true;
            root.forceActiveFocus();
            root.clicked();
        }
    }

    RowLayout {
        id: rowLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: AtlasStyle.spacingLarge
        anchors.rightMargin: AtlasStyle.spacingLarge
        spacing: AtlasStyle.spacingLarge

        Row {
            id: leadingRow
            visible: root._hasLeading
            spacing: AtlasStyle.spacingSmall
            Layout.alignment: Qt.AlignVCenter
        }
        Kirigami.Icon {
            visible: root.iconName.length > 0 && !root._hasLeading
            source: root.iconName
            fallback: "applications-other"
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }
        RowLayout {
            id: contentRow
            visible: root._hasContent
            Layout.fillWidth: true
            spacing: AtlasStyle.spacingSmall
        }
        ColumnLayout {
            visible: !root._hasContent
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 6
            spacing: 0
            QQC2.Label {
                Layout.fillWidth: true
                text: root.title
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                Accessible.ignored: true
            }
            QQC2.Label {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.65
                textFormat: Text.PlainText
                Accessible.ignored: true
            }
        }
        QQC2.Label {
            visible: root.value.length > 0 && !root.busy
            text: root.value
            opacity: 0.65
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            Layout.maximumWidth: Math.round(root.width * 0.55)
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
        Row {
            id: trailingRow
            spacing: AtlasStyle.spacingSmall
            Layout.alignment: Qt.AlignVCenter
        }
        AtlasSpinner {
            visible: root.busy
            running: root.busy
            animated: root.animated
            implicitWidth: Kirigami.Units.iconSizes.smallMedium
            Accessible.ignored: true
        }
        Kirigami.Icon {
            visible: root.checkmark
            source: "checkmark"
            isMask: true
            color: AtlasStyle.accent
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }
        AtlasSwitch {
            visible: root.showSwitch
            checked: root.switchChecked
            Accessible.name: root.title
            Accessible.description: root.subtitle
            onToggled: {
                root.switchToggled(checked);
                // The switch shows what the system says, not what was clicked:
                // if saving fails, the binding puts it back.
                checked = Qt.binding(() => root.switchChecked);
            }
        }
        Kirigami.Icon {
            visible: root.chevron && !root.busy
            source: root.mirrored ? "arrow-left" : "arrow-right"
            isMask: true
            color: Kirigami.Theme.textColor
            opacity: 0.45
            // A quarter turn to point down, whichever way it starts.
            rotation: root.disclosure && root.expanded ? (root.mirrored ? -90 : 90) : 0
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            Behavior on rotation {
                NumberAnimation {
                    duration: AtlasStyle.durationShort
                }
            }
        }
    }
}
