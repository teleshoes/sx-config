import QtQuick 2.0
import Sailfish.Silica 1.0

FunctionKey {
    key: Qt.Key_Down
    icon.source: "image://theme/icon-m-down" + (pressed ? ("?" + Theme.highlightColor) : "")
    repeat: true
    implicitWidth: shiftKeyWidth
    background.visible: false
}
