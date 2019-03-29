import QtQuick 2.0
import Sailfish.Silica 1.0

FunctionKey {
    key: Qt.Key_Up
    icon.source: "image://theme/icon-m-up" + (pressed ? ("?" + Theme.highlightColor) : "")
    repeat: true
    implicitWidth: shiftKeyWidth
    background.visible: false
}
