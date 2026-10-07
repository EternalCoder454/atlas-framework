import QtQuick
import org.kde.kirigami as Kirigami

// A small line chart with no axes or captions: the trend of a figure in a
// card or a row. `values` is a list of numbers, oldest first, spread over the
// full width; a NaN is a gap. It scales to the values unless `minimum` and
// `maximum` are set, and an automatic scale never shows less than
// `minimumRange`, so a nearly flat series stays flat. `fill` adds a soft
// area under the line. It repaints only when the values really change. See
// telamonsparkline.h for every property.
//
//   TelamonSparkline {
//       values: cpu.usageHistory
//       minimum: 0
//       maximum: 100
//       fill: true
//   }
//
// Decorative inside TelamonStat (which describes the figure); on its own give
// it an Accessible.name.
TelamonSparklineItem {
    id: spark

    implicitWidth: Kirigami.Units.gridUnit * 6
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.6)

    color: TelamonStyle.accent
    opacity: enabled ? 1 : 0.6

    Accessible.role: Accessible.Chart
}
