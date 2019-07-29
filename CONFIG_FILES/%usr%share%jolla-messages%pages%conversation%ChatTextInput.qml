import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Telephony 1.0
import org.nemomobile.configuration 1.0
import org.nemomobile.contacts 1.0
import org.nemomobile.commhistory 1.0
import Sailfish.Contacts 1.0
import "../common/utils.js" as MessageUtils

InverseMouseArea {
    id: chatInputArea

    height: visible
            ? textField.y + textField.height + ((typeMenu.height + simSelector.height) || Theme.paddingMedium)
            : 0
    width: parent.width

    property string contactName: conversation.people.length === 1 ? conversation.people[0].firstName : ""
    property alias text: textField.text
    property alias cursorPosition: textField.cursorPosition
    property alias editorFocus: textField.focus
    property alias empty: textField.empty
    property bool enabled: true
    property bool clearAfterSend: true
    property bool recreateDraftEvent: false
    property string simErrorState

    readonly property bool _senderSupportsReplies: conversation.hasPhoneNumber || !conversation.message.isSMS

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

        width: parent.width
        y: Theme.paddingMedium
        focusOutBehavior: FocusBehavior.KeepFocus
        textRightMargin: Theme.horizontalPageMargin + button.width
        font.pixelSize: Theme.fontSizeSmall
        enabled: _senderSupportsReplies

        VerticalAutoScroll.bottomMargin: Theme.paddingMedium

        property bool empty: text.length === 0 && !inputMethodComposing

        labelComponent: Component {
            Row {
                spacing: Theme.paddingSmall

                Label {
                    id: messageType

                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeTiny
                    text: {
                        return conversation.message.hasChannel ? MessageUtils.accountDisplayName(conversation.people[0],
                                                                                                 conversation.message.localUid,
                                                                                                 conversation.message.remoteUids[0])
                                                               : ""
                    }
                }

                ContactPresenceIndicator {
                    id: presence

                    anchors.verticalCenter: parent.verticalCenter
                    visible: conversation.message.hasChannel && !conversation.message.isSMS
                             && conversation.message.remoteUids.length === 1
                    presenceState: !visible ? Person.PresenceUnknown
                                            : MessageUtils.presenceForPersonAccount(conversation.people[0],
                                                                                    conversation.message.localUid,
                                                                                    conversation.message.remoteUids[0])
                }

                Label {
                    id: phoneInfoSpacerLabel

                    anchors.verticalCenter: parent.verticalCenter
                    visible: conversation.message.isSMS && conversation.people.length === 1 && !!phoneInfoLabel.text
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeTiny
                    text: "|"
                }

                Label {
                    id: phoneInfoLabel

                    anchors.verticalCenter: parent.verticalCenter
                    visible: conversation.message.isSMS && conversation.people.length === 1 && !!phoneInfoLabel.text
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeTiny
                    truncationMode: TruncationMode.Fade
                    text: conversation.phoneDetailsString(conversation.message.remoteUids[0])

                    width: Math.min(Math.ceil(implicitWidth),
                                    textField.width - textField.textLeftMargin - textField.textRightMargin
                                    - messageType.width
                                    - (presence.visible ? (presence.width + parent.spacing) : 0)
                                    - (parent.spacing + phoneInfoSpacerLabel.width)
                                    - (characterCountLabel.visible ? (characterCountLabel.width + characterCountSpacerLabel.width
                                                                      + 2 * parent.spacing) : 0)
                                    - Theme.paddingMedium)
                }

                Label {
                    id: characterCountSpacerLabel

                    anchors.verticalCenter: parent.verticalCenter
                    visible: conversation.message.isSMS && characterCountSetting.value
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeTiny
                    opacity: characterCountLabel.opacity
                    text: "|"
                }

                CharacterCountLabel {
                    id: characterCountLabel

                    anchors.verticalCenter: parent.verticalCenter
                    visible: conversation.message.isSMS && characterCountSetting.value
                    messageText: visible ? textField.text : ""
                }
            }
        }

        Row {
            spacing: Theme.paddingSmall
            parent: textField
            opacity: textField.empty ? 1.0 : 0.0
            Behavior on opacity { FadeAnimator {} }
            anchors {
                left: parent.left
                top: parent.top
                right: parent.right
                leftMargin: textField.textLeftMargin
                topMargin: textField.textTopMargin
                rightMargin: textField.textRightMargin
            }

            Label {
                property int maxWidth: parent.width
                                       - (simInfoLabel.visible ? (simInfoLabel.width + simInfoIcon.width
                                                                  + simInfoSpacerLabel.width + 3 * parent.spacing)
                                                               : 0)
                                       - Theme.paddingMedium

                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, maxWidth)
                color: textField.placeholderColor
                truncationMode: TruncationMode.Fade
                font: textField.font
                text: {
                    if (!_senderSupportsReplies) {
                        //% "Sender does not support replies"
                        return qsTrId("messages-ph-sender_des_not_support_replies")
                    }

                    //: Generic placeholder for chat input
                    //% "Type message"
                    return qsTrId("messages-ph-chat_placeholder_generic")
                }
            }

            Label {
                id: simInfoSpacerLabel

                anchors.verticalCenter: parent.verticalCenter
                visible: simInfoLabel.visible
                color: textField.placeholderColor
                text: "|"
            }

            HighlightImage {
                id: simInfoIcon

                anchors.verticalCenter: parent.verticalCenter
                visible: simInfoLabel.visible
                color: textField.placeholderColor
                source: {
                    if (simManager.activeSim === 0) {
                        return "image://theme/icon-s-sim1"
                    } else if (simManager.activeSim === 1) {
                        return "image://theme/icon-s-sim2"
                    } else {
                        return ""
                    }
                }
            }

            Label {
                id: simInfoLabel

                anchors.verticalCenter: parent.verticalCenter
                visible: _senderSupportsReplies && mainWindow.multipleEnabledSimCards && conversation.message.isSMS
                         && !Telephony.promptForMessageSim && simManager.activeSim >= 0
                color: textField.placeholderColor
                text: simManager.activeSim >= 0 ? simManager.modemSimModel.get(simManager.activeSim)["operator"] : ""
            }
        }

        Button {
            id: button

            enabled: typeMenu.enabled || (!textField.empty && chatInputArea.enabled)
            parent: textField
            width: Theme.iconSizeMedium + 2 * Theme.paddingSmall
            height: width
            anchors {
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
                bottom: parent.bottom
                bottomMargin: Theme.paddingSmall
            }
            onClicked: {
                if (textField.empty && typeMenu.enabled) {
                    typeMenu.openMenu(chatInputArea)
                } else {
                    chatInputArea.send()
                }
            }
            onPressAndHold: if (typeMenu.enabled) typeMenu.openMenu(chatInputArea)

            HighlightImage {
                id: image

                source: textField.empty && typeMenu.enabled ? "image://theme/icon-m-change-type"
                                                            : "image://theme/icon-m-send"
                color: !button.enabled ? Theme.secondaryColor
                                       : (button._showPress ? Theme.highlightColor
                                                            : Theme.primaryColor)
                highlighted: parent.down
                anchors.centerIn: parent
                opacity: parent.enabled ? 1.0 : 0.4
                Behavior on opacity { FadeAnimator {} }

                Behavior on source {
                    SequentialAnimation {
                        FadeAnimation {
                            target: image
                            to: 0.0
                        }
                        PropertyAction {} // This is where the property assignment really happens
                        FadeAnimation {
                            target: image
                            to: image.parent.enabled ? 1.0 : 0.4
                        }
                    }
                }
            }
        }
    }

    onClickedOutside: textField.focus = false

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
            // The onScreen condition is to prevent a crash that looks similar
            // to https://bugreports.qt.io/browse/QTBUG-61261
            if ((count == 1) && onScreen) {
                var data = model.get(0)
                var remotes = data.remoteUid !== "" ? [data.remoteUid] : conversation.message.remoteUids
                if (!conversation.message.matchChannel(data.localUid, remotes)) {
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
            var groupId = conversation.message.groupId
            var remotes = conversation.message.remoteUids

            var setChannel = function() {
                if (data.remoteUid !== "") {
                    conversation.message.setChannel(data.localUid, data.remoteUid)
                } else {
                    conversation.message.setBroadcastChannel(data.localUid, remotes, groupId)
                }
                textField.forceActiveFocus()
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

    ConfigurationValue {
        id: characterCountSetting
        key: "/apps/jolla-messages/show_sms_character_count"
        defaultValue: false
    }
}
