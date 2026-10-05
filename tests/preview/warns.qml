import QtQuick

// A page whose binding fails at run time: QML warns, the picture is still made.
Rectangle {
    color: "white"
    width: missingValue
}
