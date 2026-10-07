import QtQuick
import QtTest
import Telamon.Ui

TestCase {
    name: "I18n"

    Component {
        id: field
        SearchField {}
    }

    function test_module_strings_are_translated() {
        const f = createTemporaryObject(field, null);
        verify(f !== null);
        compare(f.placeholderText, "Suchen (Test)");
    }
}
