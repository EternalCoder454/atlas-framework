pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A setup or onboarding scaffold: a column of steps on the left, one page at a
// time on the right, and a footer with Back, Skip and Next (Finish on the last
// page). The pages are the items declared inside it. A page may declare these
// plain properties; all are optional:
//   title: string       the step's name in the column
//   canAdvance: bool    default true; false disables Next
//   skippable: bool     default false; true shows Skip on this page
// `showSkip` shows Skip on every page. `next()` (does nothing while the page's
// canAdvance is false) emits `finished()` on the last page. `skip()` emits
// `skipped(index)` and moves on, except on the last page, where only the signal
// fires. `showSteps: false` hides the column; it also hides when the window is
// narrow, and then a "Step 2 of 3" line shows above the page.
//
// For a first-run setup: `nextText`, `finishText` and `backText` replace the
// built-in button labels (empty keeps them). `busy` shows a spinner on Next and
// ignores it (and Alt+Left, Back and Skip) while the app works. Every use of
// Next emits `advanceRequested(index)`; with `autoAdvance: false` the control
// then stays, and the app calls `next()` itself when its work is done.
// `canGoBack: false` hides Back and turns Alt+Left off. `stepStyle` is `Column`
// (the default) or `Dots`: a row of dots above the page, the current one wider
// and in the accent colour. `showSteps: false` hides either.
// See docs/reference/atlas-ui/atlas-onboarding.md.
//
//   AtlasOnboarding {
//       anchors.fill: parent
//       onFinished: window.close()
//       Item { property string title: qsTr("Welcome"); /* ... */ }
//       Item { property string title: qsTr("Account"); property bool canAdvance: nameField.text.length > 0 }
//       Item { property string title: qsTr("Done") }
//   }
Item {
    id: control

    default property list<Item> pages
    property int currentIndex: 0
    readonly property int count: pages.length
    property bool showSteps: true
    property bool showSkip: false
    property string nextText
    property string finishText
    property string backText
    property bool busy: false
    property bool autoAdvance: true
    property bool canGoBack: true
    property int stepStyle: AtlasOnboarding.Column
    // Whether the busy spinner turns; false for a still arc (screenshots).
    property bool _spinnerAnimated: true

    enum StepStyle {
        Column,
        Dots
    }

    signal advanceRequested(int index)
    signal finished
    signal skipped(int index)

    implicitWidth: Kirigami.Units.gridUnit * 40
    implicitHeight: Kirigami.Units.gridUnit * 26

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Setup")

    function next(): void {
        control._pending = false;
        if (!priv.canAdvanceNow) {
            return;
        }
        if (control.currentIndex >= control.count - 1) {
            control.finished();
        } else {
            control.currentIndex++;
        }
    }

    // The Next button: tells the app, then moves on unless the app keeps the
    // turn. next() itself is the move and does not signal.
    function _nextPressed(): void {
        if (control.busy || control._pending || !priv.canAdvanceNow) {
            return;
        }
        control.advanceRequested(control.currentIndex);
        if (control.autoAdvance) {
            control.next();
        } else {
            // The app has the turn: a second press waits until it moves on or
            // sets `busy` and clears it again.
            control._pending = true;
        }
    }
    // True between a Next the app has not answered yet and its answer.
    property bool _pending: false
    onBusyChanged: if (!control.busy) {
        control._pending = false;
    }

    function back(): void {
        if (control.currentIndex > 0) {
            control.currentIndex--;
        }
    }

    function skip(): void {
        if (control.count === 0) {
            return;
        }
        control.skipped(control.currentIndex);
        if (control.currentIndex < control.count - 1) {
            control.currentIndex++;
        }
    }

    onCurrentIndexChanged: {
        // Before the pages exist there is nothing to clamp to.
        const clamped = !priv.ready || control.count === 0 ? control.currentIndex : Math.max(0, Math.min(control.currentIndex, control.count - 1));
        if (clamped !== control.currentIndex) {
            control.currentIndex = clamped;
            return;
        }
        control._pending = false;
        priv.show(true);
    }
    onPagesChanged: {
        // Pages arrive one at a time while the item is built: clamp after.
        if (priv.ready && control.count > 0 && control.currentIndex > control.count - 1) {
            control.currentIndex = control.count - 1;
        }
        priv.show(false);
    }
    Component.onCompleted: {
        priv.ready = true;
        if (control.count > 0 && control.currentIndex > control.count - 1) {
            control.currentIndex = control.count - 1;
        }
        priv.show(false);
    }

    QtObject {
        id: priv

        // False until the item is built: the pages and currentIndex arrive in any order.
        property bool ready: false
        readonly property bool last: control.currentIndex >= control.count - 1
        readonly property var page: control.currentIndex >= 0 && control.currentIndex < control.count ? control.pages[control.currentIndex] : null
        // Read as plain properties: a page that doesn't declare one gets the default.
        readonly property bool canAdvanceNow: page !== null && page["canAdvance"] !== false
        readonly property bool pageSkippable: page !== null && page["skippable"] === true
        readonly property bool narrow: control.width < Kirigami.Units.gridUnit * 34
        readonly property bool stepsShown: control.showSteps && !narrow && control.stepStyle === AtlasOnboarding.Column
        readonly property bool dotsShown: control.showSteps && control.stepStyle === AtlasOnboarding.Dots && control.count > 0

        function titleOf(i: int): string {
            const t = i >= 0 && i < control.count ? control.pages[i]["title"] : undefined;
            return t === undefined || t === null ? "" : String(t);
        }

        // Puts the pages in the content area and shows the current one.
        function show(animated: bool): void {
            for (let i = 0; i < control.pages.length; ++i) {
                const p = control.pages[i];
                if (p.parent !== host) {
                    p.parent = host;
                }
                p.anchors.fill = host;
                p.visible = i === control.currentIndex;
            }
            if (animated) {
                fade.restart();
            }
        }
    }

    // Alt+Left goes back, as in a browser; off with canGoBack, while busy and
    // on the first page.
    Shortcut {
        sequence: "Alt+Left"
        context: Qt.WindowShortcut
        enabled: control.visible && control.Window.active && control.canGoBack && !control.busy && control.currentIndex > 0
        onActivated: control.back()
    }

    RowLayout {
        anchors.fill: parent
        spacing: AtlasStyle.spacingLarge

        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 11
            Layout.maximumWidth: Kirigami.Units.gridUnit * 11
            Layout.alignment: Qt.AlignTop
            visible: priv.stepsShown
            spacing: AtlasStyle.spacingSmall
            Repeater {
                model: control.count
                StepItem {
                    id: step
                    required property int index
                    Layout.fillWidth: true
                    number: step.index + 1
                    text: priv.titleOf(step.index)
                    current: step.index === control.currentIndex
                    done: step.index < control.currentIndex
                    // Only back to a finished step (clickable is false for later ones);
                    // moving forward goes through next() and its canAdvance check.
                    onClicked: {
                        if (step.index < control.currentIndex) {
                            control.currentIndex = step.index;
                        }
                    }
                }
            }
            Item {
                Layout.fillHeight: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: AtlasStyle.spacing

            Text {
                Layout.fillWidth: true
                visible: !priv.stepsShown && !priv.dotsShown && control.count > 0
                Layout.preferredHeight: visible ? implicitHeight : 0
                text: qsTr("Step %1 of %2").arg(control.currentIndex + 1).arg(control.count)
                font.pointSize: AtlasStyle.fontSizeCaption
                color: AtlasStyle.textMuted
                textFormat: Text.PlainText
            }

            // The dots: past ones the accent at 45 %, the current one wider
            // and the accent, future ones the text colour at 20 % (the
            // control border in high contrast, where 20 % would vanish).
            Row {
                id: dots
                Layout.alignment: Qt.AlignHCenter
                visible: priv.dotsShown
                Layout.preferredHeight: visible ? implicitHeight : 0
                spacing: AtlasStyle.spacing
                Accessible.role: Accessible.StaticText
                Accessible.name: qsTr("Step %1 of %2").arg(control.currentIndex + 1).arg(control.count)
                Repeater {
                    model: control.count
                    Rectangle {
                        id: dot
                        required property int index
                        readonly property bool isCurrent: dot.index === control.currentIndex
                        width: dot.isCurrent ? AtlasStyle.spacingXXLarge : AtlasStyle.spacing
                        height: AtlasStyle.spacing
                        radius: height / 2
                        color: dot.isCurrent ? AtlasStyle.accent : dot.index < control.currentIndex ? (AtlasStyle.highContrast ? AtlasStyle.accent : Qt.alpha(AtlasStyle.accent, 0.45)) : (AtlasStyle.highContrast ? AtlasStyle.controlBorder : Qt.alpha(AtlasStyle.text, 0.2))
                        Accessible.ignored: true
                        Behavior on width {
                            enabled: !AtlasStyle.reducedMotion
                            NumberAnimation {
                                duration: AtlasStyle.durationShort
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: AtlasStyle.durationShort
                            }
                        }
                    }
                }
            }

            Item {
                id: host
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                NumberAnimation {
                    id: fade
                    target: host
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: AtlasStyle.duration
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: AtlasStyle.separator
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: AtlasStyle.spacing

                SecondaryButton {
                    visible: control.canGoBack && control.currentIndex > 0
                    enabled: !control.busy
                    text: control.backText.length > 0 ? control.backText : qsTr("Back")
                    onClicked: control.back()
                }
                Item {
                    Layout.fillWidth: true
                }
                TextButton {
                    visible: control.showSkip || priv.pageSkippable
                    enabled: !control.busy
                    text: qsTr("Skip")
                    onClicked: control.skip()
                }
                PrimaryButton {
                    text: priv.last ? (control.finishText.length > 0 ? control.finishText : qsTr("Finish")) : (control.nextText.length > 0 ? control.nextText : qsTr("Next"))
                    enabled: priv.canAdvanceNow
                    busy: control.busy
                    _spinnerAnimated: control._spinnerAnimated
                    onClicked: control._nextPressed()
                }
            }
        }
    }
}
