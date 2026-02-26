import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Lipstick 1.0
import org.nemomobile.lipstick 0.1

Item {
    id: customLockItem

    readonly property bool largeScreen: Screen.sizeCategory >= Screen.Large

    width: content.width
    height: content.height

    property var customLockItemFile: "/tmp/custom-lock-item.txt"

    Connections {
        target: Lipstick.compositor
        onDisplayAboutToBeOn: update()
    }

    function update() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + customLockItemFile);
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                var fileContents = xhr.responseText
                content.text = fileContents
            }
        };
        xhr.send();
    }

    Text {
        id: content

        color: Theme.primaryColor
        font {
            pixelSize: largeScreen ? Theme.fontSizeLarge : Math.round(40 * Screen.widthRatio)
            family: "monospace"
        }
    }
}
