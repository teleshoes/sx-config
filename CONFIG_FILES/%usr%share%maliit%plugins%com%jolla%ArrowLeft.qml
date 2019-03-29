import QtQuick 2.0
import Sailfish.Silica 1.0

FunctionKey {
    key: Qt.Key_Left
    icon.source: "image://theme/icon-m-left" + (pressed ? ("?" + Theme.highlightColor) : "")
    repeat: true
    implicitWidth: shiftKeyWidth
    background.visible: false
}
