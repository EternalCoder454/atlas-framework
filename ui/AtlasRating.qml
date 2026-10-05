pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Zero to five stars. `value` is 0 to 5 and halves are drawn (4.5 shows four
// stars and a half). It is `readOnly` by default, a rating to look at. Set
// `readOnly: false` to let the user choose: the stars under the pointer
// preview the choice, a click sets whole stars and emits `edited()`, and with
// the keyboard Left and Right change it by one (mirrored in right-to-left
// layouts), Home clears it and End gives five. `count` adds "(123)" after the
// stars, the number of ratings behind a value.
//
//   AtlasRating { value: app.rating; count: app.ratingCount }
//   AtlasRating {
//       readOnly: false
//       value: review.stars
//       onEdited: review.stars = value
//       Accessible.name: qsTr("Your rating")
//   }
//
// Screen readers get a static "4.5 out of 5" when read-only, and a slider
// that increases and decreases when editable.
T.Control {
    id: control

    property real value: 0
    property bool readOnly: true
    // The number of ratings; 0 or less shows none.
    property int count: 0
    // The size of a star.
    property real starSize: Kirigami.Units.iconSizes.smallMedium
    signal edited

    readonly property int _stars: 5
    // The value held to 0..5 and rounded to halves; NaN counts as 0.
    readonly property real _rounded: isFinite(value) ? Math.round(Math.max(0, Math.min(_stars, value)) * 2) / 2 : 0
    // What is drawn: the hover preview while the pointer is over, else the value.
    property real _hover: 0
    readonly property real _shown: _hover > 0 && _editable ? _hover : _rounded
    readonly property bool _editable: !readOnly && enabled
    // The count with the locale's digits and separators.
    readonly property string _countText: Qt.locale().toString(count, "f", 0)
    readonly property string _valueText: Qt.locale().toString(_rounded, "f", _rounded % 1 === 0 ? 0 : 1)

    // A user edit is held by a Binding for one turn, so an app binding on
    // `value` is kept (see docs/reference/atlasrating.md).
    property real _edit: 0
    property bool _editing: false
    readonly property Binding _hold: Binding {
        target: control
        property: "value"
        value: control._edit
        when: control._editing
        restoreMode: Binding.RestoreBinding
    }
    function _release(): void {
        control._editing = false;
    }

    function _set(v) {
        const next = Math.max(0, Math.min(_stars, v));
        if (next === _rounded) {
            return;
        }
        _edit = next;
        _editing = true;
        edited();
        Qt.callLater(_release);
    }

    implicitWidth: row.implicitWidth + leftPadding + rightPadding
    implicitHeight: Math.max(starSize, countLabel.implicitHeight) + topPadding + bottomPadding
    padding: 0
    hoverEnabled: _editable
    focusPolicy: _editable ? Qt.StrongFocus : Qt.NoFocus
    opacity: enabled ? 1 : 0.6

    Accessible.role: readOnly ? Accessible.StaticText : Accessible.Slider
    Accessible.name: readOnly ? qsTr("%1 out of 5").arg(_valueText) : qsTr("Rating")
    Accessible.description: readOnly ? (count > 0 ? qsTr("%n rating(s)", "", count).replace(String(count), _countText) : "") : qsTr("%1 out of 5").arg(_valueText)
    Accessible.focusable: !readOnly
    Accessible.onIncreaseAction: control._set(control._rounded + 1)
    Accessible.onDecreaseAction: control._set(control._rounded - 1)

    Keys.onPressed: event => {
        if (!control._editable) {
            return;
        }
        const step = control.mirrored ? -1 : 1;
        switch (event.key) {
        case Qt.Key_Right:
            control._set(control._rounded + step);
            break;
        case Qt.Key_Left:
            control._set(control._rounded - step);
            break;
        case Qt.Key_Home:
            control._set(0);
            break;
        case Qt.Key_End:
            control._set(control._stars);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    contentItem: RowLayout {
        id: row
        spacing: AtlasStyle.spacingSmall

        Item {
            id: stars
            implicitWidth: control._stars * control.starSize
            implicitHeight: control.starSize
            Layout.alignment: Qt.AlignVCenter

            Row {
                // Row follows the layout direction by itself.
                Repeater {
                    model: control._stars

                    delegate: Item {
                        id: star
                        required property int index
                        // 1 whole, 0.5 half, 0 empty.
                        readonly property real fillAmount: Math.max(0, Math.min(1, control._shown - index))
                        width: control.starSize
                        height: control.starSize

                        // The empty star underneath, the filled or half one on top.
                        Symbol {
                            anchors.fill: parent
                            icon: Symbols.Star
                            size: control.starSize
                            color: AtlasStyle.textDisabled
                        }
                        Symbol {
                            anchors.fill: parent
                            visible: star.fillAmount > 0
                            icon: star.fillAmount >= 1 ? Symbols.Star : Symbols.StarHalf
                            filled: true
                            size: control.starSize
                            color: control.readOnly || !control._editable || control._hover === 0 ? Kirigami.Theme.neutralTextColor : AtlasStyle.accent
                            // The half star is drawn filled on its left: turn it round in right-to-left.
                            transform: Scale {
                                origin.x: star.width / 2
                                xScale: control.mirrored && star.fillAmount < 1 ? -1 : 1
                            }
                        }
                    }
                }
            }

            HoverHandler {
                id: hover
                enabled: control._editable
                cursorShape: Qt.PointingHandCursor
                onPointChanged: {
                    if (!hovered) {
                        control._hover = 0;
                        return;
                    }
                    const x = control.mirrored ? stars.width - point.position.x : point.position.x;
                    control._hover = Math.max(1, Math.min(control._stars, Math.ceil(x / control.starSize)));
                }
                onHoveredChanged: if (!hovered)
                    control._hover = 0
            }
            TapHandler {
                enabled: control._editable
                onTapped: point => {
                    const x = control.mirrored ? stars.width - point.position.x : point.position.x;
                    control._set(Math.max(1, Math.min(control._stars, Math.ceil(x / control.starSize))));
                    control.forceActiveFocus(Qt.MouseFocusReason);
                }
            }
        }

        QQC2.Label {
            id: countLabel
            visible: control.count > 0
            text: "(" + control._countText + ")"
            font.pointSize: AtlasStyle.fontSizeCaption
            color: AtlasStyle.textMuted
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
    }

    background: Item {
        AtlasFocusRing {
            radius: AtlasStyle.radiusSmall
            shown: control.visualFocus
        }
    }
}
