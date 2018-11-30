import QtQuick 2.0
import Sailfish.Silica 1.0
import "../../js/directoryViewModel.js" as DirectoryViewModel

SilicaGridView {
    id: fileListView

    property bool isDirectoryView: true

    property variant directoryView: null

    property bool destroyAfterTransition: false
    property bool fileListLoaded: false

    property string dirView: "grid"

    property string path: ""

    cellHeight: parent.height > parent.width ? parent.width / 4 : parent.width / 7
    cellWidth: parent.height > parent.width ? parent.width / 4 : parent.width / 7

    width: parent.width
    height: parent.height

    currentIndex: engine.currentFileIndex

    onVerticalVelocityChanged: {
        if (verticalVelocity > (Theme.startDragDistance / 5) && flicking)
        {
            getDirectoryPage().showScrollToBottom(true)
            getDirectoryPage().showScrollToTop(false)
        }
        else if (verticalVelocity < 0 - (Theme.startDragDistance / 5) && flicking)
        {
            getDirectoryPage().showScrollToTop(true)
            getDirectoryPage().showScrollToBottom(false)
        }
        else
        {
            getDirectoryPage().showScrollToTop(false)
            getDirectoryPage().showScrollToBottom(false)
        }
    }

    VerticalScrollDecorator { }

    DirectoryPullDownMenu { id: pullDownMenu }

    // Directory title header
    header: Item {
        anchors.left: parent.left
        anchors.right: parent.right

        height: (settings.showDirHeader == true ? Theme.itemSizeLarge : 0) + fileOperationsView.height

        onWidthChanged: fileOperationsView.updateView()

        DirectoryFileOperations {
            id: fileOperationsView

            Component.onCompleted: fileOperationsView.updateView()
        }

        Label {
            id: headerLabel

            text: settings.dirPath

            anchors.top: fileOperationsView.bottom
            anchors.left: parent.left
            anchors.leftMargin: Theme.paddingMedium
            anchors.right: parent.right
            anchors.rightMargin: Theme.paddingLarge

            color: Theme.highlightColor

            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter

            height: settings.showDirHeader == true ? Theme.itemSizeLarge : 0

            visible: settings.showDirHeader
        }
        OpacityRampEffect {
            direction: OpacityRamp.RightToLeft
            slope: 4
            offset: 0.75
            sourceItem: headerLabel
        }
        BusyIndicator {
            x: fileListView.width - (fileListView.width / 2) - (width / 2)
            y: fileListView.height - (fileListView.height / 2) - (height / 2)
            size: BusyIndicatorSize.Large

            running: !fileListLoaded
            visible: !fileListLoaded
        }
    }

    model: fileModel

    delegate: Item {
        id: listItem

        IconButton {
            id: iconButton

            width: fileListView.cellWidth
            height: fileListView.cellHeight
            anchors.leftMargin: 0
            anchors.rightMargin: 0
            anchors.topMargin: 0
            anchors.bottomMargin: 0

            onClicked: {
                // Don't respond to presses if a new directory view is already being opened
                if (animateCollapseRight.running || animateCollapseLeft.running)
                    return

                if (!selectingItems)
                    DirectoryViewModel.openFile(model)
                else
                {
                    if (model.fileName == "..")
                        return

                    if (!iconButton.down)
                        clipboard.addFileToSelectedFiles(model.fullPath)
                    else
                    {
                        clipboard.removeFileFromSelectedFiles(model.fullPath)

                        if (clipboard.getSelectedFileCount() == 0)
                        {
                            getDirectoryPage().selectFiles(false)
                            iconButton.down = false
                            return
                        }
                    }

                    iconButton.down = !iconButton.down
                }
            }

            onPressAndHold: {
                if (!selectingItems)
                {
                    getDirectoryPage().selectFiles(true)
                    clipboard.addFileToSelectedFiles(model.fullPath)

                    iconButton.down = true
                }
            }

            Connections {
                target: clipboard
                onSelectedFilesCleared: {
                    iconButton.down = false
                }
                onFileOperationChanged: {
                    iconButton.down = false
                }
            }

            // Use this so we don't have to fool around with the image provider to provide
            // highlighting color
            Image {
                id: thumbnail

                anchors.fill: parent

                source: model.thumbnail
                asynchronous: true
                width: fileListView.cellWidth
                height: fileListView.cellHeight

                // For smoother looking icons
                sourceSize.width: fileListView.cellWidth
                sourceSize.height: fileListView.cellHeight

                onStatusChanged: {
                    iconButton.down = clipboard.selectedFilesContainsFile(model.fullPath)
                }
            }

            Rectangle {
                anchors.fill: parent
                opacity: iconButton.down == true || iconButton.pressed == true ? 0.5 : 0
                color: selectingItems == true ? Theme.highlightColor : Theme.secondaryHighlightColor
            }

            /*Image {
                id: image
                asynchronous: true
                width: fileListView.cellWidth
                height: fileListView.cellHeight
                visible: true
                source: model.thumbnail

                /*Rectangle {
                    anchors.fill: parent
                }*/
            /*}*/

            Text {
                anchors.fill: parent
                anchors.topMargin: parent.height / 2
                anchors.rightMargin: parent.width / 10
                anchors.leftMargin: parent.width / 10
                anchors.bottomMargin: parent.height / 10

                horizontalAlignment: Text.AlignHCenter


                verticalAlignment: Text.AlignBottom
                text: model.fileName.substr(0,32)
                color: "white"
                font.pointSize: 14
                wrapMode: Text.WrapAnywhere

                style: Text.Outline
                styleColor: "black"

                visible: model.fileType == "image" ? false : true
            }
        }
    }

    SmoothedAnimation {
        id: animateCollapseLeft
        target: fileListView
        properties: "x"
        from: fileListView.x
        to: fileListView.x - fileListView.width
        duration: 200

        onStopped: {
            if (destroyAfterTransition) fileListView.destroy()
            else loadFileList()
        }
    }

    SmoothedAnimation {
        id: animateCollapseRight
        target: fileListView
        properties: "x"
        from: fileListView.x
        to: fileListView.x + fileListView.width
        duration: 200

        onStopped: {
            if (destroyAfterTransition) fileListView.destroy()
            else loadFileList()
        }
    }

    ListModel {
        id: fileModel
    }

    Connections {
        target: fileList
        onFileListCreated: {
            if (!destroyAfterTransition) {
                DirectoryViewModel.updateFileList(fileModel, newFileList)
            }
        }
    }

    /*
     *  Starts loading the file list which will be displayed on the view
     */
    function loadFileList()
    {
        DirectoryViewModel.getFileList(fileModel, path)
    }

    /*
     *  Called when the view has been loaded
     */
    function viewLoaded()
    {
        pullDownMenu.updateBookmarkOptions()
    }

    function removeSelections()
    {
        for (var i=0; i < fileListView.children.length; i++)
        {
            var item = fileListView.children[i]

            item.listItem.iconButton.down = false
        }
    }

    function collapseToLeft(destroyAfterCollapse)
    {
        animateCollapseLeft.start()
        destroyAfterTransition = destroyAfterCollapse
    }

    function collapseToRight(destroyAfterCollapse)
    {
        animateCollapseRight.start()
        destroyAfterTransition = destroyAfterCollapse
    }
}
