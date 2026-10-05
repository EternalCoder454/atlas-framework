import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A figure: a small muted label over a big value (with a `unit` beside it),
// an optional trend and an optional sparkline. `trend` is a number or NaN
// (none): above 0 shows an up arrow in the success colour, below 0 a down
// arrow in the error colour, and `trendText` ("+4.2%") sits beside it.
// `invertTrend` swaps the colours where lower is better (latency, errors).
// `sparkline` is a list of numbers drawn small under the value.
//
//   AtlasStat {
//       label: qsTr("Download")
//       value: "48.2"
//       unit: "MB/s"
//       symbol: Symbols.Download
//       trend: 4.2
//       trendText: "+4.2%"
//       sparkline: net.history
//   }
//
// A screen reader gets one text, "label: value unit", and the trend as its
// description ("Up +4.2%"). Figures have equal
// widths, so a changing value does not jiggle.
ColumnLayout {
    id: root

    property string label
    property string value
    property string unit
    // A Material Symbol (Symbols.<Name>) before the label; 0 for none.
    property int symbol: 0
    property real trend: NaN
    property string trendText
    // Lower is better: an increase is shown in the error colour.
    property bool invertTrend: false
    property list<real> sparkline

    readonly property bool _hasTrend: !isNaN(trend) && trend !== 0
    readonly property color _trendColor: {
        const good = (trend > 0) !== invertTrend;
        return good ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor;
    }

    spacing: AtlasStyle.spacingSmall
    opacity: enabled ? 1 : 0.6

    Accessible.role: Accessible.StaticText
    Accessible.name: [label, [value, unit].filter(s => s.length > 0).join(" ")].filter(s => s.length > 0).join(": ")
    // The trend with its direction: "Up +4.2%", "Down -1%".
    Accessible.description: [_hasTrend ? (trend > 0 ? qsTr("Up") : qsTr("Down")) : "", trendText].filter(s => s.length > 0).join(" ")

    RowLayout {
        spacing: AtlasStyle.spacingSmall
        visible: root.label.length > 0 || root.symbol !== 0
        Symbol {
            visible: root.symbol !== 0
            icon: root.symbol
            size: Kirigami.Units.iconSizes.small
            color: AtlasStyle.textMuted
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: root.label
            font.pointSize: AtlasStyle.fontSizeCaption
            color: AtlasStyle.textMuted
            elide: Text.ElideRight
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
    }

    RowLayout {
        spacing: AtlasStyle.spacing
        QQC2.Label {
            text: root.value
            font.pointSize: AtlasStyle.fontSizeTitle
            font.weight: Font.Medium
            font.features: ({
                    "tnum": 1
                })
            color: Kirigami.Theme.textColor
            textFormat: Text.PlainText
            Layout.alignment: Qt.AlignBaseline
            Accessible.ignored: true
        }
        QQC2.Label {
            visible: root.unit.length > 0
            text: root.unit
            color: AtlasStyle.textMuted
            textFormat: Text.PlainText
            Layout.alignment: Qt.AlignBaseline
            Accessible.ignored: true
        }
    }

    RowLayout {
        spacing: AtlasStyle.spacingSmall
        visible: root._hasTrend || root.trendText.length > 0
        Symbol {
            visible: root._hasTrend
            icon: root.trend > 0 ? Symbols.ArrowUpward : Symbols.ArrowDownward
            size: Kirigami.Units.iconSizes.small
            color: root._trendColor
        }
        QQC2.Label {
            text: root.trendText
            font.pointSize: AtlasStyle.fontSizeCaption
            font.features: ({
                    "tnum": 1
                })
            color: root._hasTrend ? root._trendColor : AtlasStyle.textMuted
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
    }

    AtlasSparkline {
        visible: root.sparkline.length > 1
        Layout.fillWidth: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 3
        Layout.topMargin: AtlasStyle.spacingSmall
        implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.6)
        values: root.sparkline
        fill: true
        Accessible.ignored: true
    }
}
