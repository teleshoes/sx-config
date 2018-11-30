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
        visible: 'isShortcutsPage' in getDirectoryView() ? false : true
        onClicked: getDirectoryPage().addNewFiles()
    }
    MenuItem {
        text: "Scroll to bottom"
        onClicked: getDirectoryView().scrollToBottom()
    }

    MenuItem {
        text: "Scroll to top"
        onClicked: getDirectoryView().scrollToTop()
    }
    MenuItem {
        id: addToBookmarks
        text: "Add to bookmarks"
        visible: false
        onClicked: {
            visible = false
            removeFromBookmarks.visible = true
            settings.addBookmarkPath(settings.dirPath, settings.dirPath)
        }
    }
    MenuItem {
        id: removeFromBookmarks
        text: "Remove from bookmarks"
        visible: false
        onClicked: {
            visible = false
            addToBookmarks.visible = true
            settings.removeBookmarkPath(settings.dirPath)
        }
    }
    MenuItem {
        text: "Shortcuts"
        onClicked: getDirectoryPage().openShortcuts()
    }
    MenuItem {
        id: directoryProperties
        visible: 'isShortcutsPage' in getDirectoryView() ? false : true
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

        // Don't display options to add/remove bookmarks in the Shortcuts page
        if ('isShortcutsPage' in getDirectoryView())
            return

        if (settings.isPathInBookmarks(settings.dirPath)) {
            removeFromBookmarks.visible = true
            addToBookmarks.visible = false
        } else {
            removeFromBookmarks.visible = false
            addToBookmarks.visible = true
        }
    }
}
