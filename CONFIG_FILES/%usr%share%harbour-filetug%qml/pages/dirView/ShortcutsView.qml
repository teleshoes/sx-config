import QtQuick 2.0
import Sailfish.Silica 1.0
import "../../js/directoryViewModel.js" as DirectoryViewModel
import "../../js/misc.js" as Misc

Page {
  id: shortcutsView
  property bool isShortcutsPage: true

  SilicaListView {
    anchors.fill: parent

    VerticalScrollDecorator { }

    DirectoryPullDownMenu { }
    DirectoryPushUpMenu { }

    model: listModel

    header: PageHeader {
        title: "Shortcuts"
    }

    delegate: Component {
        id: listItem

        BackgroundItem {
            id: iconButton
            width: shortcutsView.width
            height: Screen.height / 12

            onClicked: openDir(model.location)

            Image {
                id: image
                anchors.left: parent.left
                anchors.leftMargin: Theme.paddingMedium
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                width: height

                source: model.thumbnail
            }
            Label {
                id: shortcutLabel

                anchors.left: image.right
                anchors.leftMargin: 5
                anchors.right: parent.right
                anchors.rightMargin: Theme.paddingLarge
                anchors.top: parent.top
                anchors.topMargin: model.location == model.name ? (parent.height / 2) - (height / 2) : 5

                font.pixelSize: model.location == model.name ? Theme.fontSizeExtraSmall : Theme.fontSizeSmall

                text: model.name
            }
            Rectangle {
                anchors.fill: parent
                opacity: iconButton.down == true || iconButton.pressed == true ? 0.5 : 0
                color: Theme.secondaryHighlightColor
            }
            Text {
                anchors.left: image.right
                anchors.leftMargin: Theme.paddingSmall
                anchors.top: shortcutLabel.bottom
                anchors.topMargin: 2

                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor

                text: model.location

                visible: model.location == model.name ? false : true
            }
            IconButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.rightMargin: Theme.paddingLarge

                width: Theme.itemSizeSmall
                height: Theme.itemSizeSmall

                visible: model.bookmark ? true : false

                icon.source: "image://theme/icon-m-close"

                onClicked: {
                    if (!model.bookmark)
                        return

                    settings.removeBookmarkPath(model.location)

                    updateModel()
                }
            }
        }
    }

    Component.onCompleted: updateModel()
    section {
        property: 'section'

        delegate: SectionHeader {
            text: section
            height: Theme.itemSizeExtraSmall
        }
    }

    ListModel {
        id: listModel
    }

    /*
     *  Create model entries
     */
    function updateModel()
    {
        listModel.clear()

        // Add locations
        listModel.append({ "section": "Locations",
                           "name": "Last location",
                           "thumbnail": "qrc:/icons/up",
                           "location": settings.dirPath })

        listModel.append({ "section": "Locations",
                           "name": "Documents",
                           "thumbnail": "qrc:/icons/text",
                           "location": StandardPaths.documents })
        listModel.append({ "section": "Locations",
                           "name": "Downloads",
                           "thumbnail": "qrc:/icons/downloads",
                           "location": fileList.getHomePath() + "/Downloads" })
        listModel.append({ "section": "Locations",
                           "name": "Music",
                           "thumbnail": "qrc:/icons/audio",
                           "location": StandardPaths.music })
        listModel.append({ "section": "Locations",
                           "name": "Pictures",
                           "thumbnail": "qrc:/icons/image",
                           "location": StandardPaths.pictures })
        listModel.append({ "section": "Locations",
                           "name": "Videos",
                           "thumbnail": "qrc:/icons/video",
                           "location": StandardPaths.videos })
        listModel.append({ "section": "Locations",
                           "name": "Android storage",
                           "thumbnail": "qrc:/icons/directory",
                           "location": "/data/sdcard"})

        // Add bookmarks if there are any
        var bookmarks = settings.getBookmarks()

        for (var key in bookmarks)
        {
            var entry = bookmarks[key];

            listModel.append({ "section": "Bookmarks",
                               "name": entry,
                               "thumbnail": "qrc:/icons/sdcard",
                               "location": key,
                               "bookmark": true })
        }

        // Add SD card if it's mounted
        if (engine.getSdCardMountPath() != "")
        {
            listModel.append({ "section": "Storage devices",
                               "name": "SD card",
                               "thumbnail": "qrc:/icons/sdcard",
                               "location": engine.getSdCardMountPath()})
        }
    }
  }
}
