import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasPopover: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 300
    width: implicitWidth
    height: implicitHeight

    // Fixed positions, so the popover lands the same every time.
    SecondaryButton {
        id: below
        x: 60
        y: 40
        text: "Below"
    }
    SecondaryButton {
        id: above
        x: 320
        y: 240
        text: "Above"
    }

    SecondaryButton {
        id: beside
        x: 20
        y: 232
        text: "End"
    }

    AtlasPopover {
        parent: root
        target: below
        Component.onCompleted: open()
        QQC2.Label {
            text: "Opens below its target, with an arrow."
        }
        TextButton {
            text: "Action"
        }
    }
    AtlasPopover {
        parent: root
        target: above
        Component.onCompleted: open()
        QQC2.Label {
            text: "No room below: opens above."
        }
    }
    AtlasPopover {
        parent: root
        target: beside
        side: AtlasPopover.End
        Component.onCompleted: open()
        QQC2.Label {
            text: "Beside it."
        }
    }
}
