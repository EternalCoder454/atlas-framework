import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasStat: fixed content, no timers or randomness.
// `animate` is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 420
    implicitHeight: 270
    width: implicitWidth
    height: implicitHeight

    GridLayout {
        x: 16
        y: 16
        columns: 3
        columnSpacing: 28
        rowSpacing: 18
        AtlasStat {
            label: "Download"
            value: "48.2"
            unit: "MB/s"
            symbol: Symbols.Download
            trend: 4.2
            trendText: "+4.2%"
            sparkline: [3, 5, 4, 8, 7, 9, 12, 10, 14, 13]
            Layout.preferredWidth: 110
        }
        AtlasStat {
            label: "Latency"
            value: "23"
            unit: "ms"
            trend: 12
            trendText: "+12%"
            invertTrend: true
            Layout.preferredWidth: 110
        }
        AtlasStat {
            label: "Errors"
            value: "7"
            trend: -30
            trendText: "-30%"
            invertTrend: true
            Layout.preferredWidth: 110
        }
        AtlasStat {
            label: "Uptime"
            value: "99.9"
            unit: "%"
            trendText: "unchanged"
        }
        AtlasStat {
            label: "Plain"
            value: "1,204"
        }
        AtlasStat {
            label: "Gaps"
            value: "5"
            sparkline: [2, 3, NaN, NaN, 6, 4, 5, 7]
            Layout.preferredWidth: 110
        }
    }
}
