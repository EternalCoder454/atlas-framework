import QtQuick
import QtQuick.Layouts
import Atlas.Ui

// A small page for tests/preview/run.sh: a label, a button, a field.
Item {
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12
        AtlasLabel {
            text: "Preview"
            textStyle: AtlasLabel.Title
        }
        PrimaryButton {
            text: "Save"
        }
        AtlasTextField {
            Layout.preferredWidth: 240
            placeholderText: "Name"
        }
    }
}
