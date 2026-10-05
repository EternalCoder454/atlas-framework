// Fixture for tests/lint/run.sh: a line ending in `// WANT` must get exactly
// one finding, every other line none. `atlas-lint: allow` silences the next
// line too, so each allowed case has a plain line after it.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    Kirigami.PlaceholderMessage { text: "empty" } // WANT
    Kirigami.PlaceholderMessage { text: "empty" } // atlas-lint: allow fixture
    Item { }
    Kirigami.Heading { text: "title" } // WANT
    Kirigami.Heading { text: "title" } // atlas-lint: allow fixture
    Item { }
    QQC2.ToolTip { text: "tip" } // WANT
    QQC2.ToolTip { text: "tip" } // atlas-lint: allow fixture
    Item { }
    QQC2.ToolTip.text: "tip" // WANT
    QQC2.ToolTip.text: "tip" // atlas-lint: allow fixture
    Item { }
    Rectangle { // WANT
        color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.1)
        QQC2.Label { text: "error" }
    }
    // atlas-lint: allow fixture
    Rectangle {
        color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.1)
        QQC2.Label { text: "error" }
    }
    Item { }
    Rectangle {
        color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.1)
    }
    Rectangle {
        color: "red"
        QQC2.Label { text: "plain" }
    }
    OldThing { } // WANT
    OldThing { } // atlas-lint: allow fixture
    Item { }
    Item { oldProp: 1 } // WANT
}
