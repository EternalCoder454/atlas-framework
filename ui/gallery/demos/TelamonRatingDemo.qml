import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonRating: fixed content, no timers or randomness.
// `animate` is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 300
    implicitHeight: 230
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        x: 16
        y: 16
        spacing: 10
        TelamonRating { value: 4.5; count: 123 }
        TelamonRating { value: 3 }
        TelamonRating { value: 0.5 }
        TelamonRating { value: 0 }
        TelamonRating { value: 5; count: 7 }
        TelamonRating { id: editable; readOnly: false; value: 2 }
    }
}
