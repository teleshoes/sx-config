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

      var homeDir = fileList.getHomePath()
      var sdcardDir = "/media/sdcard/phone"
      var shortcuts = [
        "Last Location",         "qrc:/icons/up",        settings.dirPath,
        "ROOT",                  "qrc:/icons/directory", "/",
        "HOME",                  "qrc:/icons/directory", homeDir,
        "SDCARD",                "qrc:/icons/directory", sdcardDir,
        "screenshots",           "qrc:/icons/directory", homeDir + "/Pictures/screenshots",
        "MMS pix-by-contact",    "qrc:/icons/directory", sdcardDir + "/comm-repos/mms/pix-by-contact",
        "sheet_1080p",           "qrc:/icons/directory", sdcardDir + "/sheet_music/sheet_1080p",
        "Camera (sdcard)",       "qrc:/icons/directory", sdcardDir + "/Pictures/Camera",
        "DCIM-pixmirror-bydate", "qrc:/icons/directory", sdcardDir + "/DCIM-pixmirror-bydate",
        "DDR best",              "qrc:/icons/directory", sdcardDir + "/xbestddr",
        "DDR gnuplot",           "qrc:/icons/directory", sdcardDir + "/xgnuplotddr",
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
