import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for SectionRow: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 460
    implicitHeight: 600
    width: implicitWidth
    height: implicitHeight

    Section {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        SectionRow { title: "Plain"; subtitle: "With a subtitle" }
        SectionRow { title: "Value"; value: "42" }
        SectionRow { title: "Chevron"; chevron: true }
        SectionRow { title: "Checkmark"; checkmark: true }
        SectionRow { title: "Radio"; radio: true; checkmark: true }
        SectionRow { title: "Switch"; showSwitch: true; switchChecked: false }
        SectionRow { title: "Disclosure"; disclosure: true; expanded: true }
        SectionRow {
            title: "Trailing"
            subtitle: "A button and a spin box"
            SecondaryButton { text: "Open" }
            AtlasSpinBox { value: 3 }
        }
        SectionRow {
            title: "Leading"
            leading: [
                Rectangle { width: 28; height: 28; radius: 14; color: AtlasStyle.accent } // atlas-lint: allow-raw circular avatar sample
            ]
        }
        SectionRow {
            title: "Busy"
            subtitle: "Working"
            value: "hidden"
            chevron: true
            busy: true
            animated: root.animate
        }
        SectionRow {
            content: [
                AtlasSlider { Layout.fillWidth: true; value: 0.4 }
            ]
        }
        SectionRow { title: "Disabled"; chevron: true; enabled: false }
    }
}
