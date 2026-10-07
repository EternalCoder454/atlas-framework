pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// How strong a password is: a bar of four cells that fill with `score`, and
// the label beside it. It sits under a TelamonPasswordField. The scoring (zxcvbn,
// a length rule, a server's verdict) stays in the app: it only shows the result.
// `score` is 0 (very weak) to 4 (strong), or -1 for nothing typed: an empty
// bar and no label. `text` replaces the built-in label ("Very weak", "Weak",
// "Fair", "Good", "Strong"); empty keeps it. The colour is not the only cue:
// the label and the number of filled cells say the same. Screen readers get a
// progress bar with the value "<label>, <score> of 4". See
// docs/reference/telamon-ui/telamon-password-strength.md.
//
//   TelamonPasswordField { id: pw }
//   TelamonPasswordStrength { score: app.strengthOf(pw.text) }
Item {
    id: control

    property int score: -1
    property string text

    // The score kept to what the bar can show; anything else is "nothing typed".
    readonly property int _score: Number.isInteger(control.score) && control.score >= 0 ? Math.min(control.score, 4) : -1
    readonly property string _label: {
        if (control._score < 0) {
            return "";
        }
        if (control.text.length > 0) {
            return control.text;
        }
        return [qsTr("Very weak"), qsTr("Weak"), qsTr("Fair"), qsTr("Good"), qsTr("Strong")][control._score];
    }
    readonly property color _tint: control._score <= 1 ? TelamonStyle.error : control._score === 2 ? TelamonStyle.warning : TelamonStyle.success

    implicitWidth: Kirigami.Units.gridUnit * 16
    implicitHeight: Math.max(row.implicitHeight, Kirigami.Units.gridUnit)

    Accessible.role: Accessible.ProgressBar
    //: Spoken value of the password strength bar: %1 is the label ("Good"), %2 the score from 0 to 4
    Accessible.name: control._score < 0 ? qsTr("Password strength") : qsTr("%1, %2 of 4").arg(control._label).arg(control._score)
    Accessible.description: control._score < 0 ? "" : qsTr("Password strength")

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: TelamonStyle.spacing

        Item {
            id: bar
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Kirigami.Units.gridUnit * 8
            implicitHeight: TelamonStyle.spacingSmall
            // Four cells with a gap between; sized from the bar, so the bar's
            // own width never depends on them. A Row mirrors in right-to-left.
            readonly property real cellWidth: Math.max(0, (bar.width - 3 * TelamonStyle.spacingSmall) / 4)
            Row {
                spacing: TelamonStyle.spacingSmall
                Repeater {
                    model: 4
                    Rectangle {
                        id: cell
                        required property int index
                        readonly property bool filled: cell.index <= control._score
                        width: bar.cellWidth
                        height: TelamonStyle.spacingSmall
                        radius: height / 2
                        // An empty cell is outlined in high contrast, where the faint fill would vanish.
                        color: cell.filled ? control._tint : (TelamonStyle.highContrast ? "transparent" : TelamonStyle.alpha(TelamonStyle.text, 0.12))
                        border.width: !cell.filled && TelamonStyle.highContrast ? 1 : 0
                        border.color: TelamonStyle.controlBorder
                        Accessible.ignored: true
                        Behavior on color {
                            ColorAnimation {
                                duration: TelamonStyle.durationShort
                            }
                        }
                    }
                }
            }
        }
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: control._label
            visible: control._label.length > 0
            font.family: TelamonStyle.fontFamily
            font.pointSize: TelamonStyle.fontSizeCaption
            color: control._score < 0 ? TelamonStyle.textMuted : control._tint
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
    }
}
