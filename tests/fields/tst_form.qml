import QtQuick
import QtQuick.Layouts
import QtTest
import Atlas.Ui

// AtlasForm and AtlasFormEntry (docs/api-1.5.0.md, item 25): when an error
// shows, required for each kind of control, acceptableInput, the focus on the
// first invalid entry, the label, the form's validity, Return, and the
// accessible name, description and announcement.
TestCase {
    id: tc
    name: "Form"
    width: 700
    height: 600
    visible: true
    when: windowShown

    Component {
        id: formComp
        AtlasForm {
            id: form
            width: 500
            property alias eName: eName
            property alias fName: fName
            property alias ePort: ePort
            property alias fPort: fPort
            property alias eBox: eBox
            property alias cBox: cBox
            property alias eKind: eKind
            property alias cKind: cKind
            Section {
                AtlasFormEntry {
                    id: eName
                    label: "Name"
                    help: "Your full name"
                    required: true
                    AtlasTextField {
                        id: fName
                    }
                }
                AtlasFormEntry {
                    id: ePort
                    label: "Port"
                    AtlasTextField {
                        id: fPort
                        validator: IntValidator {
                            bottom: 1
                            top: 65535
                        }
                    }
                }
                AtlasFormEntry {
                    id: eBox
                    label: "Agree"
                    required: true
                    AtlasCheckBox {
                        id: cBox
                    }
                }
                AtlasFormEntry {
                    id: eKind
                    label: "Kind"
                    required: true
                    AtlasComboBox {
                        id: cKind
                        model: ["a", "b"]
                        currentIndex: -1
                    }
                }
            }
        }
    }

    Component {
        id: otherComp
        AtlasTextField {
        }
    }

    // One required entry round a control, outside any form.
    Component {
        id: pathComp
        AtlasFormEntry {
            required: true
            AtlasFolderField {
            }
        }
    }
    Component {
        id: shortcutComp
        AtlasFormEntry {
            required: true
            AtlasShortcutField {
            }
        }
    }
    Component {
        id: switchComp
        AtlasFormEntry {
            required: true
            AtlasSwitch {
            }
        }
    }
    Component {
        id: colorComp
        AtlasFormEntry {
            required: true
            AtlasColorField {
            }
        }
    }
    Component {
        id: areaComp
        AtlasFormEntry {
            required: true
            AtlasTextArea {
            }
        }
    }

    function make() {
        const f = createTemporaryObject(formComp, tc);
        verify(f);
        return f;
    }

    // Focus changes only count in an active window.
    function activate() {
        const w = tc.Window.window;
        if (w) {
            w.requestActivate();
            tryVerify(() => w.active, 3000);
        }
    }

    function test_error_shows_only_after_leaving() {
        activate();
        const f = make();
        const other = createTemporaryObject(otherComp, tc, {y: 300});
        verify(!f.eName.valid);
        compare(f.eName.shownError, "");
        f.fName.forceActiveFocus();
        verify(f.fName.activeFocus);
        wait(30);
        compare(f.eName.shownError, "", "not while the user is in the control");
        other.forceActiveFocus();
        tryCompare(f.eName, "shownError", "Required");
        // It goes as soon as the control has a value.
        f.fName.text = "Ada";
        compare(f.eName.shownError, "");
        verify(f.eName.valid);
    }

    function test_validate_shows_all_and_focuses_the_first_invalid() {
        const f = make();
        compare(f.valid, false);
        verify(!f.validate());
        compare(f.eName.shownError, "Required");
        compare(f.eBox.shownError, "Required");
        compare(f.eKind.shownError, "Required");
        compare(f.ePort.shownError, "", "an optional empty field is fine");
        verify(f.fName.activeFocus, "the first invalid entry has the focus");
        f.fName.text = "Ada";
        verify(!f.validate());
        verify(f.cBox.activeFocus);
        f.cBox.checked = true;
        f.cKind.currentIndex = 1;
        verify(f.validate());
        compare(f.valid, true);
    }

    function test_required_for_each_kind() {
        const f = make();
        // text
        verify(f.eName.required && !f.eName.valid);
        f.fName.text = "x";
        verify(f.eName.valid);
        f.fName.text = "";
        verify(!f.eName.valid);
        // checked
        verify(!f.eBox.valid);
        f.cBox.checked = true;
        verify(f.eBox.valid);
        // index
        verify(!f.eKind.valid);
        f.cKind.currentIndex = 0;
        verify(f.eKind.valid);
        f.cKind.currentIndex = -1;
        verify(!f.eKind.valid);
        // a switch
        const sw = createTemporaryObject(switchComp, tc);
        verify(!sw.valid);
        sw._control.checked = true;
        verify(sw.valid);
        // a text area
        const area = createTemporaryObject(areaComp, tc);
        verify(!area.valid);
        area._control.text = "x";
        verify(area.valid);
        // a path
        const p = createTemporaryObject(pathComp, tc);
        verify(!p.valid);
        p._control.path = "/tmp";
        verify(p.valid);
        // a shortcut
        const s = createTemporaryObject(shortcutComp, tc);
        verify(!s.valid);
        s._control.sequence = "Ctrl+K";
        verify(s.valid);
        // a colour is never empty
        const c = createTemporaryObject(colorComp, tc);
        verify(c.valid);
    }

    function test_acceptable_input() {
        const f = make();
        verify(f.ePort.valid, "empty and not required");
        f.fPort.text = "99999";
        verify(!f.ePort.valid);
        compare(f.ePort.shownError, "", "not shown before the user has left it");
        f.validate();
        compare(f.ePort.shownError, "Check this value");
        f.fPort.text = "80";
        verify(f.ePort.valid);
        compare(f.ePort.shownError, "");
        f.ePort.invalidText = "Use 1 to 65535";
        f.fPort.text = "0";
        compare(f.ePort.shownError, "Use 1 to 65535");
    }

    function test_the_apps_error_shows_at_once() {
        const f = make();
        f.ePort.errorText = "Taken";
        verify(!f.ePort.valid);
        compare(f.ePort.shownError, "Taken");
        f.ePort.errorText = "";
        verify(f.ePort.valid);
        compare(f.ePort.shownError, "");
    }

    function test_clicking_the_label_focuses_the_control() {
        const f = make();
        const label = find(f.eName, i => i.objectName === "atlasFormEntryLabel");
        verify(label);
        verify(!f.fName.activeFocus);
        mouseClick(label);
        tryVerify(() => f.fName.activeFocus);
    }

    function test_form_valid_and_entries() {
        const f = make();
        compare(f.entries.length, 4);
        compare(f.entries[0], f.eName);
        compare(f.entries[3], f.eKind);
        verify(!f.valid);
        f.fName.text = "x";
        f.cBox.checked = true;
        f.cKind.currentIndex = 1;
        verify(f.valid);
        f.fPort.text = "99999";
        verify(!f.valid);
        f.fPort.text = "";
        verify(f.valid);
        f.eKind.destroy();
        tryVerify(() => f.entries.length === 3);
    }

    function test_a_hidden_entry_is_valid() {
        const f = make();
        verify(!f.eName.valid);
        f.eName.visible = false;
        verify(f.eName.valid);
        f.eName.visible = true;
        verify(!f.eName.valid);
        f.eName.visible = false;
        verify(!f.fName.activeFocus, "a hidden entry takes no focus");
    }

    function test_a_disabled_entry_is_valid() {
        const f = make();
        f.eName.enabled = false;
        verify(f.eName.valid);
        f.eName.enabled = true;
        verify(!f.eName.valid);
    }

    function test_announces_the_error() {
        const f = make();
        const spoken = [];
        f.eName._announceHook = t => spoken.push(t);
        f.ePort._announceHook = t => spoken.push(t);
        f.validate();
        compare(spoken.length, 1, "the optional empty port says nothing");
        compare(spoken[0], "Required");
        f.fPort.text = "0";
        f.validate();
        compare(spoken[1], "Check this value");
    }

    function test_accessible_name_and_description() {
        const f = make();
        compare(f.fName.Accessible.name, "Name");
        compare(f.fName.Accessible.description, "Your full name");
        f.validate();
        compare(f.fName.Accessible.description, "Your full name, Required");
        f.eName.label = "Full name";
        compare(f.fName.Accessible.name, "Full name");
    }

    function test_return_accepts_a_valid_form_and_shows_errors_otherwise() {
        const f = make();
        const spy = createTemporaryObject(spyComp, tc, {target: f});
        f.fName.forceActiveFocus();
        keyClick(Qt.Key_Return);
        compare(spy.count, 0, "not while the form is invalid");
        compare(f.eName.shownError, "Required");
        f.fName.text = "Ada";
        f.cBox.checked = true;
        f.cKind.currentIndex = 0;
        f.fName.forceActiveFocus();
        keyClick(Qt.Key_Return);
        compare(spy.count, 1);
    }
    Component {
        id: spyComp
        SignalSpy {
            signalName: "accepted"
        }
    }

    function find(item, test) {
        for (const c of item.children) {
            if (test(c)) {
                return c;
            }
            const r = find(c, test);
            if (r) {
                return r;
            }
        }
        return null;
    }
}
