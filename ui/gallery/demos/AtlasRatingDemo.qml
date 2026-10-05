import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasRating: fixed content, no timers or randomness.
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
        AtlasRating { value: 4.5; count: 123 }
        AtlasRating { value: 3 }
        AtlasRating { value: 0.5 }
        AtlasRating { value: 0 }
        AtlasRating { value: 5; count: 7 }
        AtlasRating { id: editable; readOnly: false; value: 2 }
    }
}
