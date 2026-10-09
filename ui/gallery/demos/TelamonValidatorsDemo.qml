import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// The Telamon validators on TelamonTextField: a valid text and an invalid one for
// each. `validateOn: "typing"` shows the message without leaving the field.
// Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: layout.implicitWidth + Kirigami.Units.gridUnit * 2
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        textFormat: Text.PlainText
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        Caption { text: "AtlasUrlValidator, valid" }
        TelamonTextField {
            text: "https://atlas.example/docs"
            validator: TelamonUrlValidator { schemes: ["https"] }
            invalidText: "Enter an https:// address"
        }
        Caption { text: "AtlasUrlValidator, unfinished" }
        TelamonTextField {
            text: "https://"
            validator: TelamonUrlValidator { schemes: ["https"] }
            invalidText: "Enter an https:// address"
            validateOn: "typing"
            Component.onCompleted: textEdited()
        }
        Caption { text: "AtlasEmailValidator, valid" }
        TelamonTextField {
            text: "zach@example.com"
            validator: TelamonEmailValidator {}
            invalidText: "Enter an email address"
        }
        Caption { text: "AtlasEmailValidator, unfinished" }
        TelamonTextField {
            text: "zach@example"
            validator: TelamonEmailValidator {}
            invalidText: "Enter an email address"
            validateOn: "typing"
            Component.onCompleted: textEdited()
        }
        Caption { text: "AtlasPathValidator, valid" }
        TelamonTextField {
            text: "~/Documents"
            validator: TelamonPathValidator {}
            invalidText: "Enter a full path"
        }
        Caption { text: "AtlasPathValidator, missing folder" }
        TelamonTextField {
            text: "/no/such/folder"
            validator: TelamonPathValidator { mustExist: true; directory: true }
            invalidText: "That folder does not exist"
            validateOn: "typing"
            Component.onCompleted: textEdited()
        }
        Caption { text: "AtlasNumberValidator, valid" }
        TelamonTextField {
            text: "12.5"
            validator: TelamonNumberValidator { bottom: 0; top: 100; decimals: 2; locale: "en_US" }
            invalidText: "Enter 0 to 100"
        }
        Caption { text: "AtlasNumberValidator, unfinished" }
        TelamonTextField {
            text: "-"
            validator: TelamonNumberValidator { bottom: -10; top: 100; decimals: 2; locale: "en_US" }
            invalidText: "Enter -10 to 100"
            validateOn: "typing"
            Component.onCompleted: textEdited()
        }
    }
}
