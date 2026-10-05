import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// The Atlas validators on AtlasTextField: a valid text and an invalid one for
// each. `validateOn: "typing"` shows the message without leaving the field.
// Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: layout.implicitWidth + Kirigami.Units.gridUnit * 2
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        Caption { text: "AtlasUrlValidator, valid" }
        AtlasTextField {
            text: "https://atlas.example/docs"
            validator: AtlasUrlValidator { schemes: ["https"] }
            invalidText: "Enter an https:// address"
        }
        Caption { text: "AtlasUrlValidator, unfinished" }
        AtlasTextField {
            text: "https://"
            validator: AtlasUrlValidator { schemes: ["https"] }
            invalidText: "Enter an https:// address"
            validateOn: "typing"
            Component.onCompleted: textEdited()
        }
        Caption { text: "AtlasEmailValidator, valid" }
        AtlasTextField {
            text: "zach@example.com"
            validator: AtlasEmailValidator {}
            invalidText: "Enter an email address"
        }
        Caption { text: "AtlasEmailValidator, unfinished" }
        AtlasTextField {
            text: "zach@example"
            validator: AtlasEmailValidator {}
            invalidText: "Enter an email address"
            validateOn: "typing"
            Component.onCompleted: textEdited()
        }
        Caption { text: "AtlasPathValidator, valid" }
        AtlasTextField {
            text: "~/Documents"
            validator: AtlasPathValidator {}
            invalidText: "Enter a full path"
        }
        Caption { text: "AtlasPathValidator, missing folder" }
        AtlasTextField {
            text: "/no/such/folder"
            validator: AtlasPathValidator { mustExist: true; directory: true }
            invalidText: "That folder does not exist"
            validateOn: "typing"
            Component.onCompleted: textEdited()
        }
        Caption { text: "AtlasNumberValidator, valid" }
        AtlasTextField {
            text: "12.5"
            validator: AtlasNumberValidator { bottom: 0; top: 100; decimals: 2; locale: "en_US" }
            invalidText: "Enter 0 to 100"
        }
        Caption { text: "AtlasNumberValidator, unfinished" }
        AtlasTextField {
            text: "-"
            validator: AtlasNumberValidator { bottom: -10; top: 100; decimals: 2; locale: "en_US" }
            invalidText: "Enter -10 to 100"
            validateOn: "typing"
            Component.onCompleted: textEdited()
        }
    }
}
