import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Internal to Atlas.Ui (not in the API): what AtlasListView, DataTable,
// AtlasTreeView and AtlasPage show for a `status` other than Ready. The views
// bind their status* properties to this and hide their rows while `active`.
// The spinner waits 300 ms, so a fast load shows no flash. Error is announced
// once, when the status becomes Error.
Item {
    id: view

    property int status: AtlasStatus.Ready
    property string title
    property string text
    // A Symbols value; 0 for the status's own.
    property int symbol: 0
    property AtlasAction action: null

    // Something other than the rows is showing (the spinner counts from the
    // moment of Loading, though it only appears after the delay).
    readonly property bool active: view.status !== AtlasStatus.Ready
    // The heading and symbol after the per-status defaults.
    readonly property string effectiveTitle: {
        if (view.title.length > 0) {
            return view.title;
        }
        switch (view.status) {
        case AtlasStatus.Empty:
            //: Heading of a view that has no content yet
            return qsTr("Nothing here");
        case AtlasStatus.NoResults:
            //: Heading of a list when a search or filter matches nothing
            return qsTr("No results");
        case AtlasStatus.Error:
            //: Heading of a view whose content could not be loaded
            return qsTr("Something went wrong");
        }
        return "";
    }
    readonly property int effectiveSymbol: {
        if (view.symbol !== 0) {
            return view.symbol;
        }
        switch (view.status) {
        case AtlasStatus.Empty:
            return Symbols.Inbox;
        case AtlasStatus.NoResults:
            return Symbols.SearchOff;
        case AtlasStatus.Error:
            return Symbols.Error;
        }
        return 0;
    }
    // True once Loading has lasted 300 ms.
    readonly property bool spinnerShown: priv.waited && view.status === AtlasStatus.Loading

    // Test hooks: replace Accessible.announce(), and the spinner's delay (ms).
    property var _announceHook: null
    property int _delay: 300

    visible: view.active
    implicitWidth: Kirigami.Units.gridUnit * 18
    implicitHeight: Kirigami.Units.gridUnit * 10

    onStatusChanged: {
        priv.waited = false;
        if (view.status === AtlasStatus.Loading) {
            delay.restart();
        } else {
            delay.stop();
        }
        if (view.status === AtlasStatus.Error) {
            priv.pending = true;
            Qt.callLater(priv.flush);
        } else {
            priv.pending = false;
        }
    }
    Component.onCompleted: {
        if (view.status === AtlasStatus.Loading) {
            delay.restart();
        }
        if (view.status === AtlasStatus.Error) {
            priv.pending = true;
            Qt.callLater(priv.flush);
        }
    }

    QtObject {
        id: priv
        property bool waited: false
        property bool pending: false
        // Speaks the heading and text once they have settled for a turn, so a
        // text set just after the status is part of it.
        function flush(): void {
            if (!priv.pending || view.status !== AtlasStatus.Error) {
                return;
            }
            priv.pending = false;
            const t = view.effectiveTitle + (view.text.length > 0 ? ". " + view.text : "");
            if (view._announceHook) {
                view._announceHook(t);
            } else {
                view.Accessible.announce(t);
            }
        }
    }

    // Runs only while a load is under way.
    Timer {
        id: delay
        interval: view._delay
        onTriggered: priv.waited = true
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 22)
        visible: view.spinnerShown
        spacing: AtlasStyle.spacingLarge

        AtlasSpinner {
            Layout.alignment: Qt.AlignHCenter
            running: view.spinnerShown
            animated: !AtlasStyle.reducedMotion
            Layout.preferredWidth: Kirigami.Units.iconSizes.large
            Layout.preferredHeight: Kirigami.Units.iconSizes.large
        }
        Text {
            Layout.fillWidth: true
            visible: view.title.length > 0
            text: view.title
            font.family: AtlasStyle.fontFamily
            font.pointSize: AtlasStyle.fontSizeBody
            font.bold: true
            color: Kirigami.Theme.textColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        Text {
            Layout.fillWidth: true
            visible: view.text.length > 0
            text: view.text
            font.family: AtlasStyle.fontFamily
            font.pointSize: AtlasStyle.fontSizeBody
            color: AtlasStyle.textMuted
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
    }

    AtlasEmptyState {
        anchors.fill: parent
        visible: view.status === AtlasStatus.Empty || view.status === AtlasStatus.NoResults || view.status === AtlasStatus.Error
        symbol: view.effectiveSymbol
        title: view.effectiveTitle
        text: view.text
        // The action's text without its "&" mnemonic marker.
        actionText: view.action && view.action.enabled ? view.action.text.replace(/&(&|.)/g, "$1") : ""
        actionSymbol: view.action ? view.action.symbol : 0
        onTriggered: {
            if (view.action && view.action.enabled) {
                view.action.trigger();
            }
        }
    }
}
