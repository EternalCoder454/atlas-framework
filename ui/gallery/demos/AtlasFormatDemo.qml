import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasFormat: example outputs of fixed inputs, the en_US
// locale and a fixed `now`, so the picture never changes. `animate` is
// switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    readonly property string _loc: "en_US"
    readonly property date _now: new Date(2026, 2, 8, 12, 0, 0)
    readonly property var _rows: [
        ["bytes(1536)", AtlasFormat.bytes(1536, 1, _loc)],
        ["bytes(3.2 GiB)", AtlasFormat.bytes(3.2 * 1024 * 1024 * 1024, 1, _loc)],
        ["bytesPerSecond(1.5 MiB)", AtlasFormat.bytesPerSecond(1.5 * 1024 * 1024, 1, _loc)],
        ["percent(0.423)", AtlasFormat.percent(0.423, 0, _loc)],
        ["number(1234567.891, 2)", AtlasFormat.number(1234567.891, 2, _loc)],
        ["duration(3900)", AtlasFormat.duration(3900, "short", _loc)],
        ["duration(3900, long)", AtlasFormat.duration(3900, "long", _loc)],
        ["duration(3909, clock)", AtlasFormat.duration(3909, "clock", _loc)],
        ["date(…, short)", AtlasFormat.date(new Date(2026, 2, 1, 14, 5), "short", _loc)],
        ["date(…, atTime)", AtlasFormat.date(new Date(2026, 2, 8, 9, 30), "atTime", _loc, _now)],
        ["date(…, relative)", AtlasFormat.date(new Date(2026, 2, 8, 11, 55), "relative", _loc, _now)],
        ["date(…, relative)", AtlasFormat.date(new Date(2026, 2, 4, 12, 0), "relative", _loc, _now)]
    ]

    implicitWidth: 420
    implicitHeight: 40 + _rows.length * 26
    width: implicitWidth
    height: implicitHeight

    GridLayout {
        anchors.fill: parent
        anchors.margins: 16
        columns: 2
        columnSpacing: 20
        rowSpacing: 6
        Repeater {
            model: root._rows.length * 2
            AtlasLabel {
                required property int index
                readonly property var _row: root._rows[Math.floor(index / 2)]
                Layout.fillWidth: index % 2 === 1
                text: index % 2 === 0 ? _row[0] : _row[1]
                textStyle: index % 2 === 0 ? AtlasLabel.Caption : AtlasLabel.Body
            }
        }
    }
}
