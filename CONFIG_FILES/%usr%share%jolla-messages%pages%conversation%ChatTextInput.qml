import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Telephony 1.0
import org.nemomobile.configuration 1.0
import org.nemomobile.contacts 1.0
import org.nemomobile.commhistory 1.0
import Sailfish.Contacts 1.0
import "../common/utils.js" as MessageUtils

InverseMouseArea {
    id: chatInputArea

    // Can't use textField height due to excessive implicit padding
    height: timestamp.y + timestamp.height + typeMenu.height + simSelector.height + Theme.paddingMedium

    property string contactName: conversation.people.length === 1 ? conversation.people[0].firstName + " " + conversation.people[0].lastName  : ""
    property alias text: textField.text
    property alias cursorPosition: textField.cursorPosition
    property alias editorFocus: textField.focus
    property alias empty: textField.empty
    property bool enabled: true
    property bool clearAfterSend: true
    property bool recreateDraftEvent: false
    property string simErrorState

    signal sendMessage(string text)

    function send() {
        Qt.inputMethod.commit()
        if (text.length < 1) {
            return
        }
        if (Telephony.promptForMessageSim && conversation.message.isSMS) {
            simSelector.openMenu(chatInputArea)
        } else {
            if (conversation.message.isSMS) {
                if (simErrorState === "modemDisabled" || simErrorState === "noSimInserted") {
                    settingsDBus.showSimCardsSettings()
                    return
                } else if (simErrorState === "simActivationRequired") {
                    pinQueryDBus.requestSimPin()
                    return
                }
            }

            sendOnCurrentAccount()
        }
    }

    function sendOnCurrentAccount() {
        sendMessage(text)
        if (clearAfterSend) {
            text = ""
        }
        draftEvent.updateAndSave()
        // Reset keyboard state
        if (textField.focus) {
            textField.focus = false
            textField.focus = true
        }
    }

    function forceActiveFocus() {
        textField.forceActiveFocus()
    }

    function reset() {
        Qt.inputMethod.commit()
        text = ""
        originalEventId = 0
        draftEvent.reset()
    }

    function saveDraftState() {
        Qt.inputMethod.commit()
        draftEvent.updateAndSave()
    }

    /* Draft messages are queried on load and group id change via DraftsModel.
     * If a draft message is loaded, the conversation type will be changed to
     * match it as well.
     *
     * When deactivated either by minimizing the app or by switching away from
     * the editing page, draft events are created, updated, or deleted.
     */

    DraftEvent {
        id: draftEvent

        onEventChanged: {
            if (freeText !== '' && chatInputArea.text === '') {
                chatInputArea.text = freeText
                chatInputArea.cursorPosition = chatInputArea.text.length
                chatInputArea.editorFocus = true
                /* For broadcast messages, we can assume we already have the right
                 * details, rather than trying to read them from the group, because
                 * there is only one valid communication method per unique group.
                 *
                 * For non-broadcast, make sure we're using the same one */
                if (!conversation.message.broadcast && remoteUids.length > 0) {
                    conversation.message.setChannel(localUid, remoteUids[0])
                }
            }
        }

        function updateAndSave() {
            if (chatInputArea.text === '') {
                if (eventId >= 0) {
                    deleteEvent()
                } else if (chatInputArea.originalEventId > 0) {
                    draftsModel.deleteEvent(chatInputArea.originalEventId);
                }
                reset()
                return
            }

            localUid = conversation.message.localUid
            remoteUids = conversation.message.remoteUids
            freeText = chatInputArea.text

            if (conversation.message.groupId >= 0) {
                groupId = conversation.message.groupId
            } else if (localUid !== '' && remoteUids.length > 0) {
                groupId = conversation.message.groupId = groupManager.ensureGroupExists(conversation.message.localUid, conversation.message.remoteUids)
            } else {
                return
            }

            save()

            if (chatInputArea.originalEventId > 0 && eventId != chatInputArea.originalEventId) {
                // We have altered the original draft, it can be removed
                draftsModel.deleteEvent(chatInputArea.originalEventId);
                chatInputArea.originalEventId = -1
            }
        }
    }

    property Page page: _findPage()
    function _findPage() {
        var parentItem = parent
        while (parentItem) {
            if (parentItem.hasOwnProperty('__silica_page')) {
                return parentItem
            }
            parentItem = parentItem.parent
        }
        return null
    }

    property bool onScreen: visible && Qt.application.active && page !== null && page.status === PageStatus.Active
    onOnScreenChanged: {
        if (!onScreen) {
            saveDraftState()
        }
    }

    property int originalEventId
    DraftsModel {
        id: draftsModel
        filterGroups: conversation.groupIds()
        onFilterGroupsChanged: draftQueryTimer.start()

        onModelReady: {
            draftEvent.event = draftsModel.event(0)
            originalEventId = draftEvent.eventId
            if (chatInputArea.recreateDraftEvent) {
                // Clear the ID so that this draft will be saved as a new event
                draftEvent.eventId = -1
            }
        }
    }

    Timer {
        id: draftQueryTimer
        interval: 1
        onTriggered: {
            if (draftsModel.filterGroups.length > 0)
                draftsModel.getEvents()
            else
                draftEvent.reset()
        }
    }

    TextArea {
        id: textField
        anchors {
            left: parent.left
            right: buttonArea.left
            top: parent.top
            topMargin: Theme.paddingMedium
        }

        focusOutBehavior: FocusBehavior.KeepFocus
        textRightMargin: 0
        font.pixelSize: Theme.fontSizeSmall

        property bool empty: text.length === 0 && !inputMethodComposing

        placeholderText: contactName.length ?
                             //: Personalized placeholder for chat input, e.g. "Hi John"
                             //% "Hi %1"
                             qsTrId("messages-ph-chat_placeholder").arg(contactName) :
                             //: Generic placeholder for chat input
                             //% "Hi"
                             qsTrId("messages-ph-chat_placeholder_generic")
    }

    onClickedOutside: textField.focus = false

    MouseArea {
        id: buttonArea
        anchors {
            top: buttonText.top
            topMargin: -Theme.paddingLarge
            leftMargin: -Theme.paddingLarge - Math.max(0, Theme.itemSizeSmall - buttonText.width)
            left: buttonText.left
            right: parent.right
            bottom: parent.bottom
        }
        enabled: typeMenu.enabled || (!textField.empty && chatInputArea.enabled)
        onClicked: {
            if (textField.empty && typeMenu.enabled) {
                typeMenu.openMenu(chatInputArea)
            } else {
                chatInputArea.send()
            }
        }
        onPressAndHold: if (typeMenu.enabled) typeMenu.openMenu(chatInputArea)
    }

    Label {
        id: buttonText
        anchors {
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: textField.top
            verticalCenterOffset: textField.textVerticalCenterOffset + (textField._editor.height - height)
        }

        font.pixelSize: Theme.fontSizeSmall
        color: !buttonArea.enabled ? Theme.secondaryColor
                                   : (buttonArea.pressed ? Theme.highlightColor
                                                         : Theme.primaryColor)


        //% "Change type"
        //: Button to select conversation type, e.g. SMS or GTalk
        text: textField.empty && typeMenu.enabled ? qsTrId("messages-la-conversation_change_type")
                                                    //% "Send"
                                                  :  qsTrId("messages-la-send")
    }

    ConversationTypeMenu {
        id: typeMenu
        people: conversation.people

        Connections {
            target: conversation
            onPeopleDetailsChanged: {
                typeMenu.refresh()
            }
        }

        enabled: {
            if (count > 1) {
                return true
            }
            if (count == 1) {
                var data = model.get(0)
                if (!conversation.message.matchChannel(data.localUid, data.remoteUid)) {
                    return true
                }
            }
            return false
        }

        onCloseKeyboard: textField.focus = false
        onActivated: {
            var data = model.get(index)
            if (data === null)
                return

            var setChannel = function() {
                conversation.message.setChannel(data.localUid, data.remoteUid)
                typeMenu.closed.disconnect(setChannel)
            }
            typeMenu.closed.connect(setChannel)
        }
    }

    ContextMenu {
        id: simSelector

        // TODO: remove once Qt.inputMethod.animating has been implemented JB#15726
        property Item lateParentItem
        property bool noKeyboard: lateParentItem && ((isLandscape && pageStack.width === Screen.width) ||
                                                     (!isLandscape && pageStack.height === Screen.height))
        onNoKeyboardChanged: {
            if (noKeyboard) {
                open(lateParentItem)
                lateParentItem = null
            }
        }

        function openMenu(parentItem) {
            // close keyboard if necessary
            if (Qt.inputMethod.visible) {
                textField.focus = false
                lateParentItem = parentItem
            } else {
                open(parentItem)
            }
        }

        SimPicker {
            actionType: Telephony.Message
            onSimSelected: {
                telepathyAccounts.selectModem(modemPath)
                sendOnCurrentAccount()
                simSelector.close()
            }
        }
    }

    Label {
        id: timestamp
        anchors {
            top: textField.bottom
            // Spacing underneath separator in TextArea is _labelItem.height + Theme.paddingSmall + 3
            topMargin: -textField._labelItem.height - 3
            left: textField.left
            leftMargin: Theme.horizontalPageMargin
        }

        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeTiny

        function updateTimestamp() {
            var date = new Date()
            text = Format.formatDate(date, Formatter.TimepointRelative) + "  " + contactName
            updater.interval = (60 - date.getSeconds() + 1) * 1000
        }

        Timer {
            id: updater
            repeat: true
            triggeredOnStart: true
            running: Qt.application.active && timestamp.visible
            onTriggered: timestamp.updateTimestamp()
        }
    }

    ConfigurationValue {
        id: characterCountSetting
        key: "/apps/jolla-messages/show_sms_character_count"
        defaultValue: false
    }

    CharacterCountLabel {
        id: characterCountLabel

        anchors {
            left:timestamp.right
            leftMargin: Theme.paddingMedium
            top: timestamp.top
        }

        messageText: visible ? textField.text : ""
        visible: conversation.message.isSMS && characterCountSetting.value
    }

    Label {
        id: messageType
        anchors {
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            top: timestamp.top
        }

        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeTiny
        text: {
            if (conversation.message.isSMS && !Telephony.promptForMessageSim) {
                var type = mainWindow.shortSimName()
                if (type.length > 0) {
                    return type
                }
            }
            return conversation.message.hasChannel ? MessageUtils.accountDisplayName(conversation.people[0],
                                                                                     conversation.message.localUid,
                                                                                     conversation.message.remoteUids[0])
                                                   : ""
        }

        ContactPresenceIndicator {
            id: presence
            anchors {
                right: parent.right
                rightMargin: 2
                bottom: parent.top
            }

            visible: conversation.message.hasChannel && !conversation.message.isSMS
                     && conversation.message.remoteUids.length === 1
            presenceState: !visible ? Person.PresenceUnknown
                                    : MessageUtils.presenceForPersonAccount(conversation.people[0],
                                                                            conversation.message.localUid,
                                                                            conversation.message.remoteUids[0])
        }
    }
}
