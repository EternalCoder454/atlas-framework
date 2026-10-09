import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonCodeEditor: C++ with marked lines and the caret on a line, a wrapped
// read-only Python, and a text over the size limit (shown read-only under a
// note). Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    component Caption: QQC2.Label {
        textFormat: Text.PlainText
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }

    readonly property string cpp: "#include <iostream>\n\n// Greets the caller.\nint main(int argc, char **argv)\n{\n    const char *name = argc > 1 ? argv[1] : \"world\";\n    std::cout << \"Hello, \" << name << \"!\\n\";\n    for (int i = 0; i < 3; ++i) {\n        if (i == 1) continue;\n    }\n    return 0;\n}\n"
    readonly property string python: "def greet(name: str = \"world\") -> str:\n    \"\"\"Say hello to <b>name</b>.\"\"\"\n    return f\"Hello, {name}! This line is long enough that it has to wrap at the edge of the editor.\"\n\n# Not bold: the text is plain.\nprint(greet())\n"

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        spacing: Kirigami.Units.smallSpacing

        Caption { text: "C++, marked lines, caret on line 7" }
        TelamonCodeEditor {
            id: editor
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 11
            fileName: "main.cpp"
            text: root.cpp
            Accessible.name: "main.cpp"
            Component.onCompleted: {
                markLines([[7, 7]], TelamonCodeEditor.Added);
                markLines([4, [8, 9]], TelamonCodeEditor.Changed);
                cursorLine = 7;
                cursorColumn = 5;
            }
        }
        Caption { text: "Python, read-only, wrapped, no line numbers" }
        TelamonCodeEditor {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 7
            language: "Python"
            readOnly: true
            wrap: true
            showLineNumbers: false
            text: root.python
            Accessible.name: "greet.py"
        }
        Caption { text: "Over the size limit" }
        TelamonCodeEditor {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 8
            maximumSize: 1024
            fileName: "log.txt"
            text: {
                let s = "";
                for (let i = 1; i <= 120; ++i) {
                    s += "line " + i + " of a text that is longer than the limit\n";
                }
                return s;
            }
            Accessible.name: "log.txt"
        }
    }
}
