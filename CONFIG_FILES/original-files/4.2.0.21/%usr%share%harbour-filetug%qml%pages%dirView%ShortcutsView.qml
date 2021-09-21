import QtQuick 2.0
import Sailfish.Silica 1.0
import "../../js/directoryViewModel.js" as DirectoryViewModel
import "../../js/misc.js" as Misc

Page {
  id: shortcutsView
  property bool isShortcutsPage: true

  onVisibleChanged: {
    if(visible){
      updateModel()
    }
  }

  SilicaListView {
    anchors.fill: parent

    VerticalScrollDecorator { }

    DirectoryPullDownMenu { }

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

    ListModel {
        id: listModel
    }
  }

  //Create model entries
  function updateModel(){
      listModel.clear()
      var shortcuts = [
        "Last Location",   "qrc:/icons/up",         settings.dirPath,
        "SD card",         "qrc:/icons/sdcard",     engine.getSdCardMountPath(),
        "Documents",       "qrc:/icons/text",       StandardPaths.documents,
        "Downloads",       "qrc:/icons/downloads",  fileList.getHomePath() + "/Downloads",
        "Music",           "qrc:/icons/audio",      StandardPaths.music,
        "Pictures",        "qrc:/icons/image",      StandardPaths.pictures,
        "Videos",          "qrc:/icons/video",      StandardPaths.videos,
        "Android storage", "qrc:/icons/directory",  "/data/sdcard",
      ]

      for (var i=0; i<shortcuts.length; i+=3){
        listModel.append({ "name":      shortcuts[i]
                         , "thumbnail": shortcuts[i+1]
                         , "location":  shortcuts[i+2]
                         })
      }

      var bookmarks = settings.getBookmarks()

      for (var key in bookmarks){
        var entry = bookmarks[key];

        listModel.append({ "name":      entry
                         , "thumbnail": "qrc:/icons/directory"
                         , "location":  key
                         , "bookmark":  true
                         })
      }
  }
}
