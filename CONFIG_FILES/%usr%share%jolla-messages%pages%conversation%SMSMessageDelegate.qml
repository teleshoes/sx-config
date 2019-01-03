import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.TextLinking 1.0
import org.nemomobile.commhistory 1.0
import org.nemomobile.messages.internal 1.0

ListItem {
    id: message
    contentHeight: Math.max(timestamp.y + timestamp.height, retryIcon.height) + Theme.paddingMedium
    menu: messageContextMenu

    property QtObject modelData
    property bool inbound: modelData ? modelData.direction == CommHistory.Inbound : false
    property bool hasAttachments: attachmentLoader.count > 0
    property bool hasText
    property bool canRetry
    property int eventStatus

    // Retry icon for non-attachment outbound messages
    Image {
        id: retryIcon
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
            margins: Theme.horizontalPageMargin
        }
    }

    Column {
        id: attachments
        height: Math.max(implicitHeight, attachmentOverlay.height)
        width: Math.max(implicitWidth, attachmentOverlay.width)
        anchors {
            left: inbound ? undefined : parent.left
            right: inbound ? parent.right : undefined
            // We really want the baseline of the last line of text, but there's no way to get that
            bottom: messageText.bottom
            bottomMargin: messageText.y
        }

        Repeater {
            id: attachmentLoader
            model: modelData.messageParts

            AttachmentDelegate {
                anchors.right: inbound ? parent.right : undefined
                messagePart: modelData
                // Retry icon for attachment outbound messages
                showRetryIcon: message.canRetry
                highlighted: message.highlighted
            }
        }
    }

    Item {
        id: attachmentOverlay
        width: height
        height: (busyLoader.active || progressLoader.active || attachmentRetryIcon.status === Image.Ready) ? Theme.itemSizeLarge : 0
        anchors {
            left: attachments.left
            bottom: attachments.bottom
        }

        Rectangle {
            anchors.fill: parent
            color:  modelData.messageParts.length ? Theme.highlightDimmerColor : Theme.highlightColor
            opacity: modelData.messageParts.length ? 0.5 : 0.1
        }

        Loader {
            id: busyLoader
            active: (eventStatus === CommHistory.DownloadingStatus || eventStatus === CommHistory.WaitingStatus ||
                     (eventStatus === CommHistory.SendingStatus && modelData.eventType === CommHistory.MMSEvent)) &&
                    !(progressLoader.active && progressLoader.item && progressLoader.item.visible)
            anchors.centerIn: parent
            sourceComponent: BusyIndicator {
                running: true
            }
        }

        Loader {
            id: progressLoader
            active: (modelData.eventType === CommHistory.MMSEvent) && (eventStatus === CommHistory.DownloadingStatus || eventStatus === CommHistory.SendingStatus)
            anchors.centerIn: parent
            sourceComponent: ProgressCircle {
                visible: transfer.running // running = progress is known, greater than 0 and less than 1
                value: transfer.progress
                inAlternateCycle: true
                MmsMessageProgress {
                    id: transfer
                    path: "/msg/" + modelData.eventId + (inbound ? "/Retrieve" : "/Send")
                    inbound: eventStatus === CommHistory.DownloadingStatus
                }
            }
        }

        // Retry icon for inbound messages (in attachment style)
        Image {
            id: attachmentRetryIcon
            anchors.centerIn: parent
        }
    }

    LinkedText {
        id: messageText
        anchors {
            left: inbound ? parent.left : attachments.right
            right: inbound ? attachments.left : parent.right
            leftMargin: inbound ? sidePadding : (attachments.height ? Theme.paddingMedium : Theme.horizontalPageMargin)
            rightMargin: !inbound ? sidePadding : (attachments.height ? Theme.paddingMedium : Theme.horizontalPageMargin)
        }

        property int sidePadding: Theme.itemSizeSmall + Theme.horizontalPageMargin
        y: Theme.paddingMedium / 2
        height: Math.max(implicitHeight, attachments.height)
        wrapMode: Text.Wrap

        plainText: {
            if (!modelData) {
                hasText = false
                return ""
            } else if (modelData.freeText != "") {
                hasText = true
                return modelData.freeText
            } else if (modelData.subject != "") {
                hasText = true
                return modelData.subject
            } else if (modelData.eventType === CommHistory.MMSEvent) {
                hasText = false
                //% "Multimedia message"
                return qsTrId("messages-ph-mms_empty_text")
            } else {
                hasText = false
                return ""
            }
        }

        color: (message.highlighted || !inbound) ? Theme.highlightColor : Theme.primaryColor
        linkColor: inbound || message.highlighted ? Theme.highlightColor : Theme.primaryColor
        font.pixelSize: inbound ? Theme.fontSizeMedium : Theme.fontSizeSmall
        horizontalAlignment: inbound ? Qt.AlignRight : Qt.AlignLeft
        verticalAlignment: Qt.AlignBottom
    }

    Label {
        id: timestamp
        anchors {
            left: parent.left
            leftMargin: Theme.horizontalPageMargin
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            top: messageText.bottom
            topMargin: Theme.paddingSmall
        }

        color: messageText.color
        opacity: 0.6
        font.pixelSize: Theme.fontSizeExtraSmall
        horizontalAlignment: messageText.horizontalAlignment

        text: {
            if (!modelData) {
                return ""
            }
            // If the status is unusual, show only that
            var rv = mainWindow.eventStatusText(eventStatus)
            if (!rv) {
                // We use different formats depending on the age for the message, compared to the
                // current day.  To match Formatter, counts days difference using date component only
                var today = new Date().setHours(0, 0, 0, 0);
                var messageDate = new Date(modelData.startTime).setHours(0, 0, 0, 0);
                var daysDiff = (today - messageDate) / (24*60*60*1000)
                var timeFmt = Format.formatDate(modelData.startTime, Formatter.TimeValue)
                if (daysDiff > 6) {
                    // Short-Date Time
                    rv = Format.formatDate(modelData.startTime, (daysDiff > 365 ? Formatter.DateMedium : Formatter.DateMediumWithoutYear)) + ' ' +
                         timeFmt
                } else if (daysDiff > 0) {
                    // Weekday Time
                    rv = Format.formatDate(modelData.startTime, Formatter.WeekdayNameStandalone) + ' ' +
                         timeFmt
                } else {
                    // Time
                    rv = timeFmt
                }

                if (modelData.readStatus === CommHistory.ReadStatusRead) {
                    //% "Read"
                    rv += " | " + qsTrId("messages-message_state_read")
                } else if (eventStatus === CommHistory.DeliveredStatus) {
                    //% "Delivered"
                    rv += " | " + qsTrId("messages-message_state_delivered")
                }

                var simName = mainWindow.shortSimNameFromImsi(modelData.subscriberIdentity)
                if (simName) {
                    rv = simName + ", " + rv
                }
            }
            return rv
        }
    }

    onClicked: {
        if (canRetry) {
            conversation.message.retryEvent(modelData)
        } else if (modelData.messageParts.length >= 1 && attachments.height > 0) {
            pageStack.animatorPush(Qt.resolvedUrl("../MessagePartsPage.qml"), { 'modelData': modelData })
        }
    }

    states: [
        State {
            name: "outboundErrorNoAttachment"
            when: !inbound && eventStatus >= CommHistory.TemporarilyFailedStatus && attachments.height == 0
            extend: "outboundError"

            PropertyChanges {
                target: retryIcon
                source: "image://theme/icon-m-reload?" + (message.highlighted ? Theme.highlightColor : Theme.primaryColor)
            }
        },
        State {
            name: "outboundError"
            when: !inbound && eventStatus >= CommHistory.TemporarilyFailedStatus
            extend: "error"

            PropertyChanges {
                target: timestamp
                //% "Problem with sending message"
                text: qsTrId("messages-send_status_failed")
            }
        },
        State {
            name: "manualReceive"
            when: inbound && eventStatus === CommHistory.ManualNotificationStatus
            extend: "inboundError"

            PropertyChanges {
                target: timestamp
                //% "Tap to download multimedia message"
                text: qsTrId("messages-mms_manual_download_prompt")
            }
        },
        State {
            name: "inboundError"
            when: inbound && eventStatus >= CommHistory.TemporarilyFailedStatus
            extend: "error"

            PropertyChanges {
                target: attachmentRetryIcon
                source: "image://theme/icon-m-refresh?" + (message.highlighted ? Theme.highlightColor : Theme.primaryColor)
            }

            PropertyChanges {
                target: timestamp
                //% "Problem with downloading message"
                text: qsTrId("messages-receive_status_failed")
            }

        },
        State {
            name: "error"

            PropertyChanges {
                target: message
                canRetry: true
            }

            PropertyChanges {
                target: messageText
                opacity: 1
            }

            PropertyChanges {
                target: timestamp
                opacity: 1
                color: message.highlighted ? messageText.color : Theme.primaryColor
            }
        }
    ]
}

