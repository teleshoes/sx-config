import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.TextLinking 1.0
import org.nemomobile.commhistory 1.0
import org.nemomobile.messages.internal 1.0

ListItem {
    id: message

    contentHeight: Math.max(timestamp.y + (timestamp.height ? (timestamp.height + Theme.paddingSmall) : 0), retryIcon.height) + Theme.paddingMedium + Theme.paddingSmall
    menu: messageContextMenu

    // NOTE: press effect is provided by the rounded rectangle, so we disable the one provided by ListItem
    _backgroundColor: "transparent"

    property QtObject modelData
    property int modemIndex: simManager.indexOfModemFromImsi(modelData.subscriberIdentity)
    property bool inbound: modelData ? modelData.direction == CommHistory.Inbound : false
    property bool hasAttachments: attachmentLoader.count > 0
    property bool hasText
    property bool canRetry
    property int eventStatus
    property string eventStatusText: modelData ? mainWindow.eventStatusText(eventStatus, modelData.eventId) : ""

    property date currentDateTime
    property bool showDetails

    //HACK-DISABLE-HIDE-TIMESTAMP
    //property bool hideDefaultTimestamp: modelData && (calculateDaysDiff(modelData.startTime, currentDateTime) > 6 && modelData.index !== 0)
    property bool hideDefaultTimestamp: false
    //HACK-DISABLE-HIDE-TIMESTAMP

    function calculateDaysDiff(date, currentDateTime) {
        // We use different formats depending on the age for the message, compared to the
        // current day. To match Formatter, counts days difference using date component only.
        var today = new Date(currentDateTime).setHours(0, 0, 0, 0)
        var messageDate = new Date(date).setHours(0, 0, 0, 0)

        return (today - messageDate) / (24 * 60 * 60 * 1000)
    }

    function formatDate(date, currentDateTime) {
        var daysDiff = calculateDaysDiff(date, currentDateTime)
        var dateString
        var timeString

        if (daysDiff > 6) {
            //HACK-YYYY-MM-DD
            //dateString = Format.formatDate(date, (daysDiff > 365 ? Formatter.DateMedium : Formatter.DateMediumWithoutYear))
            dateString = Qt.formatDateTime(date, 'yyyy-MM-dd  -  ')
            //HACK-YYYY-MM-DD

            //HACK-HH-MM-SS
            //timeString = Format.formatDate(date, Formatter.TimeValue)
            timeString = Qt.formatDateTime(date, 'hh:mm:ss')
            //HACK-HH-MM-SS
        } else if (daysDiff > 0) {
            dateString = Format.formatDate(modelData.startTime, Formatter.WeekdayNameStandalone)

            //HACK-HH-MM-SS
            //timeString = Format.formatDate(date, Formatter.TimeValue)
            timeString = Qt.formatDateTime(date, 'hh:mm:ss')
            //HACK-HH-MM-SS
        } else {
            //HACK-HH-MM-SS
            //timeString = Format.formatDate(date, Formatter.DurationElapsed)
            timeString = Qt.formatDateTime(date, 'hh:mm:ss')
            //HACK-HH-MM-SS
        }

        if (dateString) {
            return qsTrId("messages-la-date_time").arg(dateString).arg(timeString)
        } else {
            return timeString
        }
    }

    function formatDetailedDate(date, currentDateTime) {
        var daysDiff = calculateDaysDiff(date, currentDateTime)
        var dateString
        var timeString = Format.formatDate(date, Formatter.TimeValue)

        if (daysDiff < 365) {
            dateString = Format.formatDate(date, Formatter.DateFullWithoutYear)
        } else {
            dateString = Format.formatDate(date, Formatter.DateFull)
        }

        return qsTrId("messages-la-date_time").arg(dateString).arg(timeString)
    }

    Rectangle {
        property color backgroundColor: !inbound ? "transparent" : (Theme.colorScheme === Theme.DarkOnLight ? Theme.rgba(Theme.highlightColor, 0.2) : Theme.rgba(Theme.primaryColor, 0.1))
        property color highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, menuOpen ? 0 : Theme.highlightBackgroundOpacity)

        visible: inbound || message.highlighted
        color: message.highlighted ? highlightedColor : backgroundColor
        radius: Theme.paddingMedium
        anchors {
            left: inbound ? attachments.left : undefined
            right: !inbound ? attachments.right : undefined
            top: parent.top
            bottom: parent.bottom
            topMargin: Theme.paddingMedium
            bottomMargin: Theme.paddingMedium
            leftMargin: inbound ? (-radius) : 0
            rightMargin: !inbound ? (-radius) : 0
        }

        width: radius
               + Math.max(messageText.width, timestamp.width)
               + (messageText.anchors.leftMargin + messageText.anchors.rightMargin)
               + (hasAttachments && (attachments.width + attachments.anchors.leftMargin + attachments.anchors.rightMargin))
    }

    // Retry icon for non-attachment outbound messages
    Image {
        id: retryIcon
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            margins: Theme.horizontalPageMargin
        }
    }

    Column {
        id: attachments
        height: Math.max(implicitHeight, attachmentOverlay.height)
        width: Math.max(implicitWidth, attachmentOverlay.width)
        anchors {
            left: inbound ? parent.left : undefined
            right: inbound ? undefined : parent.right
            // We really want the baseline of the last line of text, but there's no way to get that
            bottom: messageText.bottom
        }

        Repeater {
            id: attachmentLoader
            model: modelData.messageParts

            AttachmentDelegate {
                anchors {
                    left: inbound ? parent.left : undefined
                    right: inbound ? undefined : parent.right
                }
                messagePart: modelData
                // Retry icon for attachment outbound messages
                showRetryIcon: message.canRetry
                highlighted: message.highlighted
            }
        }
    }

    BackgroundItem {
        anchors.fill: attachments
        enabled: hasAttachments
        onClicked: pageStack.animatorPush(Qt.resolvedUrl("../MessagePartsPage.qml"), { 'modelData': modelData, 'eventStatus': eventStatus })
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
            top: parent.top
            left: inbound ? attachments.right : undefined
            right: inbound ? undefined : attachments.left
            topMargin: Theme.paddingMedium + Theme.paddingSmall
            leftMargin: (!inbound ? Theme.paddingMedium : (attachments.height ? Theme.paddingMedium : Theme.horizontalPageMargin))
                        - (effectiveHorizontalAlignment === Text.AlignRight ? marginCorrection : 0)
            rightMargin: (inbound ? Theme.paddingMedium : (attachments.height ? Theme.paddingMedium : Theme.horizontalPageMargin))
                         - (effectiveHorizontalAlignment === Text.AlignLeft ? marginCorrection : 0)
        }

        property int sidePadding: Theme.itemSizeSmall + Theme.horizontalPageMargin
        property int marginCorrection: width - Math.ceil(contentWidth)
        property int maxWidth: parent.width
                               - (hasAttachments ? (attachments.width - Theme.horizontalPageMargin) : 0)
                               - (retryIcon.width > 0 ? (2 * Theme.horizontalPageMargin + retryIcon.width + 2 * Theme.paddingMedium) : sidePadding)

        y: Theme.paddingMedium / 2
        height: Math.max(implicitHeight, implicitHeight ? (attachments.height + Theme.paddingMedium) : 0)
        width: Math.min(Math.ceil(implicitWidth), maxWidth)

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
            } else {
                hasText = false
                return ""
            }
        }

        color: (message.highlighted || !inbound) ? Theme.highlightColor : Theme.primaryColor
        linkColor: inbound || message.highlighted ? Theme.highlightColor : Theme.primaryColor
        font.pixelSize: inbound ? Theme.fontSizeMedium : Theme.fontSizeSmall
        verticalAlignment: Qt.AlignBottom
    }

    Column {
        id: timestamp

        anchors {
            left: inbound ? parent.left : undefined
            leftMargin: inbound ? Theme.horizontalPageMargin : 0
            right: !inbound ? parent.right : undefined
            rightMargin: !inbound ? Theme.horizontalPageMargin : 0
            top: messageText.bottom
            topMargin: Theme.paddingSmall
        }
        opacity: 0.6
        height: detailedTimestampLoader.item ? detailedTimestampLoader.item.height : implicitHeight
        Behavior on height {
            NumberAnimation {
                id: timestampHeightAnimation
                duration: 100
            }
        }
        width: detailedTimestampLoader.item ? detailedTimestampLoader.item.width : implicitWidth
        Behavior on width {
            NumberAnimation {
                duration: timestampHeightAnimation.duration
            }
        }

        Row {
            id: timestampRow

            spacing: Theme.paddingSmall
            visible: !showDetails && (!!timestampLabel.text || warningIcon.visible)
            height: Theme.iconSizeSmall // Avoid height flicker when details has just one visible row
            anchors {
                left: inbound ? parent.left : undefined
                right: inbound ? undefined : parent.right
            }

            Label {
                id: timestampLabel

                color: messageText.color
                font.pixelSize: Theme.fontSizeExtraSmall
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (eventStatusText)
                        return eventStatusText
                    if (hideDefaultTimestamp)
                        return ""
                    return formatDate(modelData.startTime, currentDateTime)
                }
            }

            HighlightImage {
                id: warningIcon

                visible: false
                highlighted: message.highlighted
                source: "image://theme/icon-s-warning"
                color: timestampLabel.color
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Loader {
            id: detailedTimestampLoader
            sourceComponent: detailedTimestampComponent
            active: showDetails
            visible: !!item
            opacity: 0.0
        }
    }

    Component {
        id: detailedTimestampComponent

        Column {
            spacing: Theme.paddingSmall

            Label {
                anchors {
                    left: inbound ? parent.left : undefined
                    right: inbound ? undefined : parent.right
                }
                visible: !!text
                color: messageText.color
                font.pixelSize: Theme.fontSizeExtraSmall
                text: conversation.phoneDetailsString(inbound ? modelData.remoteUid : modelData.localUid)
            }

            Row {
                spacing: Theme.paddingSmall
                height: Theme.iconSizeSmall // Avoid height flicker when delivered icon appears
                anchors {
                    left: inbound ? parent.left : undefined
                    right: inbound ? undefined : parent.right
                }

                HighlightImage {
                    id: simIcon

                    anchors.verticalCenter: parent.verticalCenter
                    highlighted: message.highlighted
                    visible: mainWindow.multipleEnabledSimCards && message.modemIndex >= 0 && message.modemIndex <= 1
                    source: {
                        if (message.modemIndex === 0)
                            return "image://theme/icon-s-sim1"
                        else if (message.modemIndex === 1)
                            return "image://theme/icon-s-sim2"
                    }
                    color: messageText.color
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Theme.fontSizeExtraSmall
                    visible: simIcon.visible
                    color: simIcon.color
                    text: message.modemIndex >= 0 ? simManager.modemSimModel.get(message.modemIndex)["operator"] : ""
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Theme.fontSizeExtraSmall
                    visible: simIcon.visible
                    color: simIcon.color
                    text: "|"
                }

                Label {
                    color: timestampLabel.color
                    font.pixelSize: Theme.fontSizeExtraSmall
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (eventStatusText)
                            return eventStatusText
                        return formatDetailedDate(modelData.startTime, currentDateTime)
                    }
                }

                HighlightImage {
                    visible: message.showDetails && (modelData.readStatus === CommHistory.ReadStatusRead || eventStatus === CommHistory.DeliveredStatus)
                    highlighted: message.highlighted
                    source: "image://theme/icon-s-checkmark"
                    color: timestampLabel.color
                    anchors.verticalCenter: parent.verticalCenter
                }

                HighlightImage {
                    visible: warningIcon.visible
                    highlighted: message.highlighted
                    source: "image://theme/icon-s-warning"
                    color: timestampLabel.color
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Behavior on showDetails {
        SequentialAnimation {

            // Fade out the simple timestamp, if it isn't hidden and detailed isn't shown
            FadeAnimation {
                duration: 100
                target: timestampRow
                loops: (!hideDefaultTimestamp && !showDetails) ? 1 : 0
                to: 0.0
            }

            // Fade out the detailed timestamp, if it's shown
            FadeAnimation {
                duration: 100
                target: detailedTimestampLoader
                loops: showDetails ? 1 : 0
                to: 0.0
            }

            // This is where showDetails is actually changed, but its value inside this behavior isn't re-evaluated after this
            PropertyAction { }

            // Wait for the height change animation
            PauseAnimation {
                duration: timestampHeightAnimation.duration
            }

            // Fade in the detailed timestamp, if it wasn't shown (showDetails isn't re-evaluated here, so we see its past value)
            FadeAnimation {
                duration: 100
                target: detailedTimestampLoader
                loops: !showDetails ? 1 : 0
                from: 0.0
                to: 1.0
            }

            // Fade in the simple timestamp, if it wasn't shown (showDetails isn't re-evaluated here, so we see its past value)
            FadeAnimation {
                duration: 100
                target: timestampRow
                loops: showDetails ? 1 : 0
                to: 1.0
            }
        }
    }

    onClicked: {
        if (canRetry) {
            conversation.message.retryEvent(modelData)
        } else {
            showDetails = !showDetails
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
                target: message
                //% "Problem with sending message"
                eventStatusText: qsTrId("messages-send_status_failed")
            }
        },
        State {
            name: "manualReceive"
            when: inbound && eventStatus === CommHistory.ManualNotificationStatus
            extend: "inboundError"

            PropertyChanges {
                target: message
                //% "Tap to download multimedia message"
                eventStatusText: qsTrId("messages-mms_manual_download_prompt")
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
                target: message
                //% "Problem with downloading message"
                eventStatusText: qsTrId("messages-receive_status_failed")
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
            }

            PropertyChanges {
                target: timestampLabel
                color: message.highlighted ? messageText.color : Theme.primaryColor
            }

            PropertyChanges {
                target: warningIcon
                visible: true
            }
        }
    ]
}

