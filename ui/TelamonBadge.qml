import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A small pill label for a status or a count: "New", "3", "Beta". `type` picks
// the tint: "neutral" (the default), "accent", "success", "warning" or
// "error". `symbol` adds a Material Symbol before the text. With no text and
// no symbol it is a small dot (`dot`), for "something is new here"; give a dot
// an Accessible.name where the dot is the only sign.
//
//   TelamonBadge { text: qsTr("Beta"); type: "accent" }
//   TelamonBadge { text: "3"; type: "error" }
//   TelamonBadge { type: "success" }          // a dot
//
// Not interactive: no Tab stop. A screen reader gets the text; a dot or a
// symbol with no text gets the name of its type ("Warning"), or
// `accessibleName` when the app sets it ("Update available").
Rectangle {
    id: root

    property string text
    // "neutral" | "accent" | "success" | "warning" | "error"
    property string type: "neutral"
    // A Material Symbol (Symbols.<Name>); 0 for none.
    property int symbol: 0
    property bool dot: text.length === 0 && symbol === 0
    // What a screen reader says; the text, or the type's name when there is none.
    property string accessibleName: text.length > 0 ? text : _typeName

    readonly property color _tint: {
        switch (type) {
        case "accent":
            return TelamonStyle.accent;
        case "success":
            return Kirigami.Theme.positiveTextColor;
        case "warning":
            return Kirigami.Theme.neutralTextColor;
        case "error":
            return Kirigami.Theme.negativeTextColor;
        default:
            return Kirigami.Theme.textColor;
        }
    }
    // The tint pulled toward the text colour, so it reads on its own wash.
    readonly property color _textColor: type === "neutral" ? TelamonStyle.alpha(Kirigami.Theme.textColor, 0.8) : Qt.tint(Kirigami.Theme.textColor, TelamonStyle.alpha(_tint, 0.65))
    readonly property string _typeName: {
        switch (type) {
        case "accent":
            return qsTr("Highlighted");
        case "success":
            return qsTr("Success");
        case "warning":
            return qsTr("Warning");
        case "error":
            return qsTr("Error");
        default:
            return qsTr("Notice");
        }
    }

    implicitWidth: dot ? Math.round(Kirigami.Units.gridUnit * 0.6) : content.implicitWidth + 2 * TelamonStyle.spacing
    implicitHeight: dot ? implicitWidth : Math.round(Kirigami.Units.gridUnit * 1.35)
    radius: height / 2
    color: dot ? _tint : TelamonStyle.alpha(_tint, root.type === "neutral" ? 0.1 : 0.16)
    border.width: dot ? 0 : 1
    border.color: TelamonStyle.alpha(_tint, 0.2)
    opacity: enabled ? 1 : 0.6

    Accessible.role: Accessible.StaticText
    Accessible.name: root.accessibleName

    RowLayout {
        id: content
        visible: !root.dot
        anchors.centerIn: parent
        spacing: TelamonStyle.spacingSmall
        Symbol {
            visible: root.symbol !== 0
            icon: root.symbol
            size: Math.round(Kirigami.Units.iconSizes.small * 0.8)
            color: root._textColor
        }
        QQC2.Label {
            visible: root.text.length > 0
            text: root.text
            font.pointSize: TelamonStyle.fontSizeCaption
            font.weight: Font.Medium
            color: root._textColor
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
    }
}
