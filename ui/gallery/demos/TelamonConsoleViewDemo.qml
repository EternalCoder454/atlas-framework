import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonConsoleView: coloured build output (the eight colours and their bright
// variants, text styles, a background, a truecolour sample, a progress line that
// is rewritten), and a narrow one showing that escape sequences and bidi
// controls never reach the screen. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    readonly property string e: "\u001b"

    implicitWidth: 520
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        textFormat: Text.PlainText
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        spacing: Kirigami.Units.smallSpacing

        Caption { text: "Build output with colours and styles" }
        TelamonConsoleView {
            id: build
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 21
            follow: false
            Component.onCompleted: {
                const e = root.e;
                build.append("$ cargo build --release\n");
                build.append(e + "[1;32m   Compiling" + e + "[0m telamon-core v2.1.0\n");
                build.append(e + "[1;32m   Compiling" + e + "[0m telamon-ui v2.1.0\n");
                build.append(e + "[1;33mwarning" + e + "[0m" + e + "[1m: unused variable `n`" + e + "[0m\n");
                build.append(e + "[1;34m  -->" + e + "[0m src/main.rs:12:9\n");
                build.append(e + "[1;31merror[E0308]" + e + "[0m" + e + "[1m: mismatched types" + e + "[0m\n");
                build.append(e + "[36mnote" + e + "[0m: expected `u32`, found `&str`\n");
                build.append("Download 10%\rDownload 45%\rDownload 100%\n");
                build.append(e + "[30mblack " + e + "[31mred " + e + "[32mgreen " + e + "[33myellow " + e + "[34mblue " + e + "[35mmagenta " + e + "[36mcyan " + e + "[37mwhite" + e + "[0m\n");
                build.append(e + "[90mblack " + e + "[91mred " + e + "[92mgreen " + e + "[93myellow " + e + "[94mblue " + e + "[95mmagenta " + e + "[96mcyan " + e + "[97mwhite" + e + "[0m\n");
                build.append(e + "[1mbold" + e + "[0m " + e + "[2mdim" + e + "[0m " + e + "[3mitalic" + e + "[0m " + e + "[4munderline" + e + "[0m " + e + "[9mstrike" + e + "[0m " + e + "[7minverse" + e + "[0m\n");
                build.append(e + "[41;97m FAIL " + e + "[0m " + e + "[42;30m PASS " + e + "[0m " + e + "[44;97m INFO " + e + "[0m " + e + "[43;30m SKIP " + e + "[0m\n");
                build.append(e + "[38;2;255;120;0mtruecolour " + e + "[38;2;80;200;120mgradient " + e + "[38;2;120;120;255msample" + e + "[0m\n");
                build.append(e + "[38;5;208m256 orange " + e + "[38;5;244m256 grey" + e + "[0m\n");
                build.append(e + "[1;31merror" + e + "[0m: could not compile `telamon-ui`\n");
                build.append("<b>plain</b> text stays literal\n");
            }
        }

        Caption { text: "Escape sequences are dropped" }
        TelamonConsoleView {
            id: hostile
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            Layout.preferredHeight: Kirigami.Units.gridUnit * 9
            follow: false
            wrap: true
            Component.onCompleted: {
                const e = root.e;
                hostile.append("clear" + e + "[2J" + e + "[H" + e + "[1000A kept\n");
                hostile.append("title" + e + "]0;pwned\u0007 and " + e + "]8;;https://example.com\u0007link" + e + "]8;;\u0007 text\n");
                hostile.append("clipboard" + e + "]52;c;aGk=\u0007 untouched\n");
                hostile.append("bell\u0007\u0007\u0007 and back\b\b\bspace\n");
                hostile.append("bidi \u202eevil\u202c shown in order\n");
                hostile.append("<i>html</i> **markdown** stay literal\n");
            }
        }
    }
}
