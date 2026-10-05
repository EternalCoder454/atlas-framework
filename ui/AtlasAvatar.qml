pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Effects
import org.kde.kirigami as Kirigami

// A round picture of a person or an account: the image at `source`, or, when
// there is none or it fails to load, the initials of `name` ("Ada Lovelace"
// gives "AL") on a colour taken from the name, so the same person always has
// the same colour. With no name either, the `symbol` (a person by default).
//
//   AtlasAvatar { name: user.displayName; source: user.picture; size: 48 }
//
// The colours are a fixed set that white text reads on (WCAG AA). The picture
// is cropped to a circle with a mask, which needs a GPU backend; on Qt
// Quick's software backend (which draws no mask at all) it is shown square. The accessible name is
// `accessibleName`: `name`, or "Profile picture" when there is none.
Item {
    id: root

    property url source
    property string name
    // Shown when there is no image and no name (Symbols.Person by default).
    property int symbol: Symbols.Person
    property real size: Kirigami.Units.gridUnit * 2
    // What a screen reader says; set it for an avatar that has no name.
    property string accessibleName: name.trim().length > 0 ? name : qsTr("Profile picture")

    readonly property var _palette: ["#1f6fbf", "#7a4cc2", "#1e7a45", "#b0501c", "#b02a61", "#0e7482", "#5a5fc7", "#8a6100"]
    readonly property bool _hasImage: image.status === Image.Ready
    readonly property string _initials: {
        const words = name.trim().split(/\s+/).filter(w => w.length > 0).map(w => Array.from(w)[0]);
        if (words.length === 0) {
            return "";
        }
        const letters = words.length === 1 ? words[0] : words[0] + words[words.length - 1];
        return letters.toUpperCase();
    }
    readonly property color _color: {
        let h = 2166136261;
        const s = name.trim().toLowerCase();
        for (let i = 0; i < s.length; ++i) {
            h = Math.imul(h ^ s.charCodeAt(i), 16777619) >>> 0;
        }
        return _palette[h % _palette.length];
    }

    implicitWidth: size
    implicitHeight: size
    opacity: enabled ? 1 : 0.6

    Accessible.role: Accessible.Graphic
    Accessible.name: root.accessibleName

    Rectangle {
        id: disc
        anchors.fill: parent
        radius: width / 2
        color: root._initials.length > 0 ? root._color : AtlasStyle.alpha(Kirigami.Theme.textColor, 0.12)
        visible: !root._hasImage

        QQC2.Label {
            visible: root._initials.length > 0
            anchors.centerIn: parent
            text: root._initials
            color: "white"
            font.pixelSize: Math.round(root.size * 0.4)
            font.weight: Font.Medium
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
        Symbol {
            visible: root._initials.length === 0
            anchors.centerIn: parent
            icon: root.symbol
            size: Math.round(root.size * 0.55)
            color: AtlasStyle.alpha(Kirigami.Theme.textColor, 0.65)
        }
    }

    Image {
        id: image
        anchors.fill: parent
        source: root.source
        visible: status === Image.Ready
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectCrop
        // Decoded at the drawn size, not the file's.
        sourceSize: Qt.size(Math.ceil(root.size * 2), Math.ceil(root.size * 2))
        // The software backend cannot draw the MultiEffect (the picture would
        // not show at all); llvmpipe can, so this asks the backend, not
        // AtlasStyle.softwareRendering.
        layer.enabled: visible && image.GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
        }
        Accessible.ignored: true
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: width / 2
        layer.enabled: true
        visible: false
    }
}
