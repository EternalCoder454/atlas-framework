import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A find (and replace) bar that slides down above the editor. The owner does
// the searching: it binds `findText` and the three toggles to its search,
// answers findNext() and the others, and reports `matchCount` and
// `currentMatch` (1-based, 0 for none) back. `error` replaces the count,
// for a regular expression that does not compile.
//
// Enter finds the next match, Shift+Enter the previous one, Escape closes it
// and Enter in the replace field replaces. Open it with open(withReplace).
Item {
    id: control

    property string findText
    property string replaceText
    property bool replaceVisible: false
    property bool matchCase: false
    property bool wholeWords: false
    property bool regularExpression: false
    property int matchCount: 0
    property int currentMatch: 0
    property string error
    property bool opened: false

    signal findNext
    signal findPrevious
    signal replaceOne
    signal replaceAll
    signal closed

    // A user edit is held on the public property for one turn, so an app
    // binding such as `matchCase: model.matchCase` survives it.
    property string _findEdit
    property bool _findEditing: false
    property string _replaceEdit
    property bool _replaceEditing: false
    property bool _caseEdit: false
    property bool _caseEditing: false
    property bool _wordsEdit: false
    property bool _wordsEditing: false
    property bool _regexEdit: false
    property bool _regexEditing: false
    readonly property list<Binding> _holds: [
        Binding {
            target: control
            property: "findText"
            value: control._findEdit
            when: control._findEditing
            restoreMode: Binding.RestoreBinding
        },
        Binding {
            target: control
            property: "replaceText"
            value: control._replaceEdit
            when: control._replaceEditing
            restoreMode: Binding.RestoreBinding
        },
        Binding {
            target: control
            property: "matchCase"
            value: control._caseEdit
            when: control._caseEditing
            restoreMode: Binding.RestoreBinding
        },
        Binding {
            target: control
            property: "wholeWords"
            value: control._wordsEdit
            when: control._wordsEditing
            restoreMode: Binding.RestoreBinding
        },
        Binding {
            target: control
            property: "regularExpression"
            value: control._regexEdit
            when: control._regexEditing
            restoreMode: Binding.RestoreBinding
        },
        // The fields and toggles follow the properties, also after the user
        // edited them and the app refused.
        Binding {
            target: findField
            property: "text"
            value: control.findText
        },
        Binding {
            target: replaceField
            property: "text"
            value: control.replaceText
        }
    ]
    function _release(): void {
        control._findEditing = false;
        control._replaceEditing = false;
        control._caseEditing = false;
        control._wordsEditing = false;
        control._regexEditing = false;
    }

    function open(withReplace) {
        if (withReplace) {
            replaceVisible = true;
        }
        opened = true;
        findField.forceActiveFocus();
        findField.selectAll();
    }
    function close() {
        if (!opened) {
            return;
        }
        opened = false;
        closed();
    }

    readonly property string countText: {
        if (error.length > 0) {
            return error;
        }
        if (findText.length === 0) {
            return "";
        }
        //: Position of the current search hit: %1 is its number, %2 how many hits there are ("3 of 12")
        return matchCount === 0 ? qsTr("No results") : qsTr("%1 of %2").arg(currentMatch).arg(matchCount);
    }
    readonly property bool failed: error.length > 0 || (findText.length > 0 && matchCount === 0)
    readonly property real fullHeight: card.implicitHeight + AtlasStyle.spacingSmall

    implicitWidth: Kirigami.Units.gridUnit * 30
    implicitHeight: fullHeight
    height: opened ? fullHeight : 0
    visible: height > 0
    clip: true
    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Find")

    Behavior on height {
        NumberAnimation {
            duration: AtlasStyle.durationShort
            easing.type: Easing.OutCubic
        }
    }

    // A rounded field like SearchField, without its clear-on-Escape.
    component Field: T.TextField {
        id: field

        property string icon
        property bool invalid: false
        readonly property bool rtl: LayoutMirroring.enabled

        implicitWidth: Kirigami.Units.gridUnit * 10
        implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.9)
        leftPadding: AtlasStyle.spacingLarge + (rtl ? 0 : fieldIcon.visible ? fieldIcon.width + AtlasStyle.spacingSmall : 0) + AtlasStyle.spacingSmall
        rightPadding: AtlasStyle.spacingLarge + (rtl ? (fieldIcon.visible ? fieldIcon.width + AtlasStyle.spacingSmall : 0) : 0) + AtlasStyle.spacingSmall
        verticalAlignment: TextInput.AlignVCenter
        placeholderTextColor: Qt.alpha(Kirigami.Theme.textColor, 0.5)
        color: Kirigami.Theme.textColor
        selectionColor: AtlasStyle.accent
        selectedTextColor: AtlasStyle.accentText
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeBody
        selectByMouse: true
        inputMethodHints: Qt.ImhNoPredictiveText
        hoverEnabled: true
        Accessible.role: Accessible.EditableText
        Accessible.name: placeholderText

        background: Rectangle {
            radius: AtlasStyle.radiusPill
            color: Qt.alpha(Kirigami.Theme.textColor, field.hovered && !field.activeFocus ? 0.09 : 0.06)
            border.width: field.activeFocus ? 2 : 1
            border.color: field.activeFocus ? Qt.alpha(field.invalid ? Kirigami.Theme.negativeTextColor : AtlasStyle.accent, 0.7) : Qt.alpha(Kirigami.Theme.textColor, 0.1)
        }

        // A template field draws no placeholder of its own.
        Text {
            x: field.leftPadding
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, field.width - field.leftPadding - field.rightPadding)
            visible: field.length === 0 && field.preeditText.length === 0
            text: field.placeholderText
            font: field.font
            color: field.placeholderTextColor
            elide: Text.ElideRight
            Accessible.ignored: true
        }
        Kirigami.Icon {
            id: fieldIcon
            visible: field.icon.length > 0
            x: field.rtl ? field.width - width - AtlasStyle.spacingLarge : AtlasStyle.spacingLarge
            anchors.verticalCenter: parent.verticalCenter
            width: Kirigami.Units.iconSizes.small
            height: width
            source: field.icon
            isMask: true
            color: Kirigami.Theme.textColor
            opacity: 0.55
        }
    }

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: column.implicitHeight + AtlasStyle.spacingSmall * 2
        radius: AtlasStyle.radiusLarge
        color: Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.5) : Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(1, 1, 1, 0.06))
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: AtlasStyle.spacingSmall
            spacing: AtlasStyle.spacingSmall

            RowLayout {
                spacing: AtlasStyle.spacingSmall

                ToolbarButton {
                    id: chevron
                    icon.name: control.LayoutMirroring.enabled ? "arrow-left" : "arrow-right"
                    text: control.replaceVisible ? qsTr("Hide Replace") : qsTr("Show Replace")
                    // A quarter turn to point down, whichever way it starts.
                    iconRotation: control.replaceVisible ? (control.LayoutMirroring.enabled ? -90 : 90) : 0
                    onClicked: {
                        control.replaceVisible = !control.replaceVisible;
                        if (control.replaceVisible) {
                            replaceField.forceActiveFocus();
                        }
                    }
                    Accessible.checkable: true
                    Accessible.checked: control.replaceVisible
                }
                Field {
                    id: findField
                    invalid: control.failed
                    Layout.fillWidth: true
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 6
                    icon: "search"
                    placeholderText: qsTr("Find")
                    onTextEdited: {
                        control._findEdit = text;
                        control._findEditing = true;
                        Qt.callLater(control._release);
                    }
                    Keys.onReturnPressed: event => (event.modifiers & Qt.ShiftModifier) ? control.findPrevious() : control.findNext()
                    Keys.onEnterPressed: event => (event.modifiers & Qt.ShiftModifier) ? control.findPrevious() : control.findNext()
                    Keys.onEscapePressed: control.close()
                }
                QQC2.Label {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5.5
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 12
                    text: control.countText
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: AtlasStyle.fontFamily
                    font.pointSize: AtlasStyle.fontSizeCaption
                    horizontalAlignment: Text.AlignHCenter
                    color: control.failed ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    opacity: control.failed ? 1 : 0.7
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
                ToolbarButton {
                    icon.name: "go-up"
                    text: qsTr("Previous Match")
                    shortcutText: qsTr("Shift+Enter")
                    enabled: control.matchCount > 0
                    onClicked: control.findPrevious()
                }
                ToolbarButton {
                    icon.name: "go-down"
                    text: qsTr("Next Match")
                    //: Name of the Enter key, as shown in a tooltip
                    shortcutText: qsTr("Enter")
                    enabled: control.matchCount > 0
                    onClicked: control.findNext()
                }
                ToolbarButton {
                    text: qsTr("Match Case")
                    checkable: true
                    checked: control.matchCase
                    onToggled: {
                        control._caseEdit = checked;
                        control._caseEditing = true;
                        Qt.callLater(control._release);
                    }
                    TypeMark {
                        text: "Aa"
                        on: parent.checked
                    }
                }
                ToolbarButton {
                    text: qsTr("Whole Word")
                    checkable: true
                    checked: control.wholeWords
                    onToggled: {
                        control._wordsEdit = checked;
                        control._wordsEditing = true;
                        Qt.callLater(control._release);
                    }
                    TypeMark {
                        text: "ab"
                        font.underline: true
                        on: parent.checked
                    }
                }
                ToolbarButton {
                    text: qsTr("Regular Expression")
                    checkable: true
                    checked: control.regularExpression
                    onToggled: {
                        control._regexEdit = checked;
                        control._regexEditing = true;
                        Qt.callLater(control._release);
                    }
                    TypeMark {
                        text: ".*"
                        on: parent.checked
                    }
                }
                ToolbarButton {
                    icon.name: "window-close"
                    text: qsTr("Close")
                    //: Name of the Escape key, as shown in a tooltip
                    shortcutText: qsTr("Esc")
                    onClicked: control.close()
                }
            }

            RowLayout {
                visible: control.replaceVisible
                spacing: AtlasStyle.spacingSmall

                // Lines the field up under the find field.
                Item {
                    Layout.preferredWidth: chevron.width
                }
                Field {
                    id: replaceField
                    Layout.fillWidth: true
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 6
                    icon: "edit-find-replace"
                    placeholderText: qsTr("Replace")
                    onTextEdited: {
                        control._replaceEdit = text;
                        control._replaceEditing = true;
                        Qt.callLater(control._release);
                    }
                    Keys.onReturnPressed: control.replaceOne()
                    Keys.onEnterPressed: control.replaceOne()
                    Keys.onEscapePressed: control.close()
                }
                SecondaryButton {
                    //: Button: replace the current match (a verb)
                    text: qsTr("Replace")
                    focusPolicy: Qt.NoFocus
                    enabled: control.matchCount > 0
                    onClicked: control.replaceOne()
                }
                SecondaryButton {
                    text: qsTr("Replace All")
                    focusPolicy: Qt.NoFocus
                    enabled: control.matchCount > 0
                    onClicked: control.replaceAll()
                }
            }
        }
    }

    // The letters drawn on a toggle.
    component TypeMark: Text {
        property bool on: false
        anchors.centerIn: parent
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeBody
        font.weight: Font.Medium
        textFormat: Text.PlainText
        color: Kirigami.Theme.textColor
        Accessible.ignored: true
    }
}
