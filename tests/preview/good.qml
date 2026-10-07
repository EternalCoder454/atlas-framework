import QtQuick
import QtQuick.Layouts
import Telamon.Ui

// A small page for tests/preview/run.sh: a label, a button, a field.
Item {
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12
        TelamonLabel {
            text: "Preview"
            textStyle: TelamonLabel.Title
        }
        PrimaryButton {
            text: "Save"
        }
        TelamonTextField {
            Layout.preferredWidth: 240
            placeholderText: "Name"
        }
    }
}
