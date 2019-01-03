import QtQuick 2.0
import Sailfish.Silica 1.0
import org.nemomobile.contacts 1.0
import org.nemomobile.commhistory 1.0
import Sailfish.Contacts 1.0
import "../common/utils.js" as MessageUtils

ListItem {
    id: delegate
    contentHeight: textColumn.height + Theme.paddingMedium + textColumn.y
    menu: contextMenuComponent

    property QtObject person: model.contactIds.length ? peopleModel.personById(model.contactIds[0]) : null
    property string subscriberIdentity: model.subscriberIdentity || ''

    property string providerName: getProviderName()
    property bool hasIMAccount: _hasIMAccount()

    function getProviderName() {
        if (!model.lastEventGroup || !telepathyAccounts.ready
             || MessageUtils.isSMS(model.lastEventGroup.localUid)) {
            return ""
        }

        return MessageUtils.accountDisplayName(person, model.lastEventGroup.localUid, model.lastEventGroup.remoteUids[0])
    }

    function _hasIMAccount() {
        var groups = model.groups
        for (var i = 0; i < groups.length; i++) {
            if (!MessageUtils.isSMS(groups[i].localUid))
                return true
        }
        return false
    }

    Column {
        id: textColumn
        anchors {
            top: parent.top
            topMargin: Theme.paddingSmall
            left: parent.left
            leftMargin: Theme.horizontalPageMargin
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
        }

        Row {
            width: parent.width

            Image {
                id: groupIcon
                source: model.groups[0].remoteUids.length > 1 ? ("image://theme/icon-s-group-chat?" + (delegate.highlighted ? Theme.highlightColor : Theme.primaryColor)) : ""
                anchors.verticalCenter: name.verticalCenter
            }

            Image {
                id: draftIcon
                source: model.lastEventIsDraft ? ("image://theme/icon-s-edit?" + (delegate.highlighted ? Theme.highlightColor : Theme.primaryColor)) : ""
                anchors.verticalCenter: name.verticalCenter
            }

            Label {
                id: name
                width: parent.width - x

                truncationMode: TruncationMode.Fade
                color: delegate.highlighted ? Theme.highlightColor : Theme.primaryColor
                text: (model.chatName !== undefined && model.chatName != "") ? model.chatName :
                      ((model.contactNames.length) ? model.contactNames.join(", ") : model.groups[0].remoteUids.join(", "))
            }
        }

        Label {
            id: lastMessage
            anchors.left: parent.left
            anchors.right: parent.right

            text: {
                if (model.lastMessageText != '') {
                    return model.lastMessageText
                } else if (model.lastEventType == CommHistory.MMSEvent) {
                    //% "Multimedia message"
                    return qsTrId("messages-ph-mms_empty_text")
                }
                return ''
            }

            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeExtraSmall
            color: delegate.highlighted || model.unreadMessages > 0 ? Theme.highlightColor : Theme.primaryColor
            wrapMode: Text.Wrap
            maximumLineCount: 3

            GlassItem {
                visible: model.unreadMessages > 0
                color: Theme.highlightColor
                falloffRadius: 0.16
                radius: 0.15
                anchors {
                    left: parent.left
                    leftMargin: width / -2 - Theme.horizontalPageMargin
                    top: parent.top
                    topMargin: height / -2 + date.height / 2
                }
            }
        }

        Label {
            id: date

            color: delegate.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            text: {
                var label = mainWindow.eventStatusText(model.lastEventStatus)
                if (!label) {
                    label = Qt.formatDateTime(model.startTime, 'hh:mm   -   yyyy-MM-dd')
                    if (providerName) {
                        label += " \u2022 " + providerName
                    }
                }
                return label
            }

            ContactPresenceIndicator {
                id: presence
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.right
                    leftMargin: Theme.paddingMedium
                }

                visible: hasIMAccount
                presenceState: person ? person.globalPresenceState : Person.PresenceUnknown
            }
        }
    }

    function remove() {
        //% "Deleting"
        remorseAction(qsTrId("messages-remorse_delete_group"), function() { model.contactGroup.deleteGroups() })
    }

    Component {
        id: contextMenuComponent

        ContextMenu {
            id: menu
            MenuItem {
                //% "Delete"
                text: qsTrId("messages-me-delete_conversation")
                onClicked: remove()
            }
        }
    }
}
