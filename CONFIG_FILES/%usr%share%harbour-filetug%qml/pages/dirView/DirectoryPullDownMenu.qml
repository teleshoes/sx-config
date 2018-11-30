import QtQuick 2.0
import Sailfish.Silica 1.0
import "../../js/directoryViewModel.js" as DirectoryViewModel

PullDownMenu {
    id: pullDownMenu

    MenuItem {
        text: "About"
        onClicked: pageStack.push(Qt.resolvedUrl("../AboutPage.qml"))
    }
    MenuItem {
        text: "Settings"
        onClicked: pageStack.push(Qt.resolvedUrl("../SettingsPage.qml"))
    }
    MenuItem {
        text: "New..."
        visible: getDirectoryPage().visible
        onClicked: getDirectoryPage().addNewFiles()
    }
    MenuItem {
        id: addToBookmarks
        text: "Add to bookmarks"
        visible: false
        onClicked: {
            settings.addBookmarkPath(settings.dirPath, settings.dirPath)
            updateBookmarkOptions()
            getShortcutsPage().updateModel()
        }
    }
    MenuItem {
        id: removeFromBookmarks
        text: "Remove from bookmarks"
        visible: false
        onClicked: {
            settings.removeBookmarkPath(settings.dirPath)
            updateBookmarkOptions()
            getShortcutsPage().updateModel()
        }
    }
    MenuItem {
        id: directoryProperties
        visible: getDirectoryPage().visible
        text: "Directory properties"
        onClicked: {
            var fullPath = settings.dirPath
            var fileName = fullPath.substring(fullPath.lastIndexOf("/")+1, fullPath.length)
            var path = fullPath.replace(fileName, "")

            var entry = { "fullPath": fullPath,
                          "fileName": fileName,
                          "path": path,
                          "fileType": "dirinfo",
                          "thumbnail": "qrc:/icons/directory"  }

            DirectoryViewModel.openFile(entry)
        }
    }

    function updateBookmarkOptions() {
        console.log("UPDATED: " + settings.dirPath)
        removeFromBookmarks.visible = false
        addToBookmarks.visible = false

        if (!getDirectoryPage().visible){
            return
        }

        if (settings.isPathInBookmarks(settings.dirPath)) {
            removeFromBookmarks.visible = true
        } else {
            addToBookmarks.visible = true
        }
    }
}
