.pragma library

// The installed font families and the monospace ones found so far, kept for
// the whole process and shared by every TelamonFontPicker: the families are
// read once, and a scan one picker has done is not done again by the next.
var _all = null;
var _fixed = [];
var _scanned = 0;

function all() {
    if (_all === null) {
        _all = Qt.fontFamilies();
    }
    return _all;
}
// How many families (from the start of all()) have been tested.
function scanned() {
    return _scanned;
}
// The monospace ones among them.
function fixedList() {
    return _fixed.slice();
}
// Records that the families up to `end` are tested and `found` are monospace.
function advance(from, end, found) {
    // A picker that fell behind another one adds nothing twice.
    if (from !== _scanned || end <= _scanned) {
        return;
    }
    _fixed = _fixed.concat(found);
    _scanned = end;
}
