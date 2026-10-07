// Fixture for tests/lint/run.sh: a line ending in `// WANT` must get exactly
// one finding, every other line none. `telamon-lint: allow` silences the next
// line too, so each allowed case has a plain line after it.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    Kirigami.PlaceholderMessage { text: "empty" } // WANT
    Kirigami.PlaceholderMessage { text: "empty" } // telamon-lint: allow fixture
    Item { }
    Kirigami.Heading { text: "title" } // WANT
    Kirigami.Heading { text: "title" } // telamon-lint: allow fixture
    Item { }
    QQC2.ToolTip { text: "tip" } // WANT
    QQC2.ToolTip { text: "tip" } // telamon-lint: allow fixture
    Item { }
    QQC2.ToolTip.text: "tip" // WANT
    QQC2.ToolTip.text: "tip" // telamon-lint: allow fixture
    Item { }
    Rectangle { // WANT
        color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.1)
        QQC2.Label { text: "error" }
    }
    // telamon-lint: allow fixture
    Rectangle {
        color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.1)
        QQC2.Label { text: "error" }
    }
    Item { }
    Rectangle {
        color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.1)
    }
    Rectangle {
        color: "red" // telamon-lint: allow-raw
        QQC2.Label { text: "plain" }
    }
    OldThing { } // WANT
    OldThing { } // telamon-lint: allow fixture
    Item { }
    Item { oldProp: 1 } // WANT
    Component.onCompleted: {
        TelamonPortal.notify("t", body, [], { markup: true }) // WANT
        TelamonPortal.notify("t", TelamonPortal.escape(body), [], { markup: true })
        TelamonPortal.notify(qsTr("t"), qsTr("<b>fixed</b>"), [], { markup: true })
        TelamonPortal.notify("t", body, [], { eventId: "x" })
        TelamonPortal.notify("t", body, [], { markup: true }) // telamon-lint: allow fixture
    }
}
