/****************************************************************************
**
** Copyright (c) 2015 - 2020 Jolla Ltd.
** Copyright (c) 2020 - 2021 Open Mobile Platform LLC.
**
** License: Proprietary
**
****************************************************************************/

import QtQuick 2.6
import Sailfish.Silica 1.0
import com.jolla.settings 1.0
import Nemo.DBus 2.0
import org.nemomobile.lipstick 0.1
import "../main"

Loader {
    id: root

    property bool hasContent: simpleFavModel.count > 0
                              || listFavModel.count > 0
                              || gridFavModel.count > 0
    property real firstColumnVCenterOffset: width / columns / 2
    property int columns: 4
    property Item pager
    property int padding

    property int sliderColumns: 1

    property var filterToggles: ["grid_favorites_simple"]
    property var filterSliders: ["list_favorites"]
    property var filterActions: ["grid_favorites_page", "action"]

    property var filterNone: []
    property var filterTogglesAndActions: filterToggles.concat(filterActions)

    property bool combineTogglesIntoActions: true

    asynchronous: true
    visible: status === Loader.Ready

    function showEventsSettings() {
        call("showEventsSettings", [])
    }

    function showTopMenuSettings() {
        showPage("system_settings/look_and_feel/topmenu")
    }

    function showUsersSettings() {
        showPage("system_settings/system/users")
    }

    function showAddNewUser() {
        callSettingsDBus("addNewUser")
    }

    function callSettingsDBus(method, arguments) {
        Lipstick.compositor.invokeDBusMethod(
                    "com.jolla.settings",
                    "/com/jolla/settings/ui",
                    "com.jolla.settings.ui",
                    method,
                    arguments)
    }

    function showPage(page) {
        if (page !== "") {
            callSettingsDBus("showPage", [page])
        }
    }

    FavoritesModel {
        id: simpleFavModel

        filter: combineTogglesIntoActions ? filterNone : filterToggles
        key: "/desktop/lipstick-jolla-home/topmenu_shortcuts"
        userModifiedKey: "/desktop/lipstick-jolla-home/topmenu_shortcuts_user"
    }

    FavoritesModel {
        id: gridFavModel

        filter: combineTogglesIntoActions ? filterTogglesAndActions : filterActions
        key: "/desktop/lipstick-jolla-home/topmenu_shortcuts"
        userModifiedKey: "/desktop/lipstick-jolla-home/topmenu_shortcuts_user"
    }

    FavoritesModel {
        id: listFavModel

        filter: "list_favorites"
        key: "/desktop/lipstick-jolla-home/topmenu_shortcuts"
        userModifiedKey: "/desktop/lipstick-jolla-home/topmenu_shortcuts_user"
    }

    sourceComponent: Column {
        width: root.width
        height: implicitHeight

        Item {
            width: 1
            height: root.padding
        }

        /*** TOGGLES ***/
        Item {
            id: simpleFavContainer

            width: parent.width
            height: simpleFavGrid.height
            Rectangle {
                anchors {
                    fill: parent
                    topMargin: -root.padding
                }
                z: -1
                color: Theme.highlightBackgroundColor
                opacity: simpleFavGridManager.movingItem ? Theme.opacityFaint : 0.0
                Behavior on opacity {  FadeAnimator { } }
            }
            Grid {
                id: simpleFavGrid

                columns: root.columns
                height: implicitHeight
                Behavior on height {
                    enabled: Lipstick.compositor.topMenuLayer.housekeeping
                    NumberAnimation { easing.type: Easing.InOutQuad }
                }
                EditableGridManager {
                    id: simpleFavGridManager

                    view: simpleFavGrid
                    pager: root.pager
                    contentContainer: simpleFavContainer
                    dragContainer: pager

                    function itemAt(x, y) {
                        return simpleFavGrid.childAt(x, y)
                    }
                    function itemCount() {
                        return simpleFavRepeater.count
                    }

                    onScroll: pager.scroll(up)
                    onStopScrolling: pager.stopScrolling()
                }
                Repeater {
                    id: simpleFavRepeater

                    model: simpleFavModel
                    delegate: FavoriteSettingsDelegate {
                        manager: simpleFavGridManager
                        height: Theme.itemSizeLarge + Theme.paddingLarge + contextMenuHeight
                        width: Math.floor(root.width / root.columns)
                        onClicked: Lipstick.compositor.topMenuLayer.housekeeping = false
                        onRemove: simpleFavModel.removeFavorite(settingsEntryPath)
                        onReorder: {
                            if (newIndex != -1 && newIndex !== index) {
                                simpleFavModel.move(index, newIndex)
                            }
                        }
                    }
                }
            }
        }

        /*** SLIDERS ***/
        Loader {
            id: listFavLoader

            active: true
            width: root.width

            Rectangle {
                anchors {
                    fill: parent
                    bottomMargin: -Theme.paddingSmall
                }
                z: -1
                color:Theme.highlightBackgroundColor
                opacity: listFavLoader.item && listFavLoader.item.movingItem ? Theme.opacityFaint : 0.0
                Behavior on opacity {  FadeAnimator { } }
            }
            sourceComponent: Grid {
                id: listFavGrid

                property alias movingItem: listFavGridManager.movingItem

                width: root.width
                height: implicitHeight
                columns: sliderColumns
                Behavior on height {
                    enabled: Lipstick.compositor.topMenuLayer.housekeeping
                    NumberAnimation { easing.type: Easing.InOutQuad }
                }
                EditableGridManager {
                    id: listFavGridManager

                    view: listFavGrid
                    pager: root.pager
                    contentContainer: listFavLoader
                    dragContainer: pager

                    function itemAt(x, y) {
                        return listFavGrid.childAt(x, y)
                    }
                    function itemCount() {
                        return listFavRepeater.count
                    }
                    onScroll: pager.scroll(up)
                    onStopScrolling: pager.stopScrolling()
                }
                Repeater {
                    id: listFavRepeater

                    model: listFavModel
                    delegate: FavoriteSettingsDelegate {
                        manager: listFavGridManager
                        width: root.width / sliderColumns
                        height: item.height
                        reorderScale: 1.1
                        onClicked: Lipstick.compositor.topMenuLayer.housekeeping = false
                        onRemove: listFavModel.removeFavorite(settingsEntryPath)
                        onReorder: {
                            if (newIndex != -1 && newIndex !== index) {
                                listFavModel.move(index, newIndex)
                            }
                        }
                    }
                }
            }
        }

        /*** ACTIONS ***/
        Item {
            id: gridFavGridContainer

            width: parent.width
            height: gridFavGrid.height

            Rectangle {
                anchors {
                    fill: parent
                    topMargin: -Theme.paddingSmall
                    bottomMargin: -Theme.paddingMedium
                }
                z: -1
                color:Theme.highlightBackgroundColor
                opacity: gridManager.movingItem ? Theme.opacityFaint : 0.0
                Behavior on opacity {  FadeAnimator { } }
            }
            Grid {
                id: gridFavGrid

                columns: root.columns
                height: implicitHeight
                Behavior on height {
                    enabled: Lipstick.compositor.topMenuLayer.housekeeping
                    NumberAnimation { easing.type: Easing.InOutQuad }
                }
                EditableGridManager {
                    id: gridManager

                    view: gridFavGrid
                    pager: root.pager
                    contentContainer: gridFavGridContainer
                    dragContainer: pager

                    function itemAt(x, y) {
                        return gridFavGrid.childAt(x, y)
                    }
                    function itemCount() {
                        return gridFavRepeater.count
                    }
                    onScroll: pager.scroll(up)
                    onStopScrolling: pager.stopScrolling()
                }
                Repeater {
                    id: gridFavRepeater

                    model: gridFavModel
                    delegate: FavoriteSettingsDelegate {
                        id: pageOrActionDelegate

                        manager: gridManager
                        height: item.height
                        width: Math.floor(root.width / root.columns)
                        actionSource: Qt.resolvedUrl("FavoriteSettingsItem.qml")
                        pageSource: Qt.resolvedUrl("FavoriteSettingsItem.qml")
                        onClicked: Lipstick.compositor.topMenuLayer.housekeeping = false
                        onRemove: gridFavModel.removeFavorite(settingsEntryPath)
                        onReorder: {
                            if (newIndex != -1 && newIndex !== index) {
                                gridFavModel.move(index, newIndex)
                            }
                        }

                        Connections {
                            target: pageOrActionDelegate.item
                            onTriggered: {
                                if (model.object.type == "action") {
                                    Lipstick.compositor.invokeRemoteAction(remoteAction)
                                } else {
                                    root.showPage(pageOrActionDelegate.item.settingsPageEntryPath)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

