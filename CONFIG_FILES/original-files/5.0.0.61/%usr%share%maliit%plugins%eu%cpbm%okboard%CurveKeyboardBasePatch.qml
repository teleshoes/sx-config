/*
 * Copyright (C) 2012-2013 Jolla Ltd.
 * Copyright (C) 2012 John Brooks <john.brooks@dereferenced.net>
 * Copyright (C) Jakub Pavelek <jpavelek@live.com>
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * Redistributions of source code must retain the above copyright notice, this list
 * of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list
 * of conditions and the following disclaimer in the documentation and/or other materials
 * provided with the distribution.
 * Neither the name of Nokia Corporation nor the names of its contributors may be
 * used to endorse or promote products derived from this software without specific
 * prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 * THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

import com.jolla 1.0 // okboard (import first because of fake KeyboardBackground declaration in qmldir)

import QtQuick 2.0
import QtQml.Models 2.2
import Sailfish.Silica 1.0
import Sailfish.Silica.Background 1.0
import com.meego.maliitquick 1.0
import com.jolla.keyboard 1.0
import Nemo.Configuration 1.0
import "touchpointarray.js" as ActivePoints

import eu.cpbm.okboard 1.0 // okboard
import "curves.js" as InProgress // okboard

PagedView {
    id: keyboard

    property Item layout
    property bool portraitMode

    property Item lastPressedKey
    property Item lastInitialKey

    property int shiftState: ShiftState.AutoShift
    property bool autocaps
    // TODO: should clean up autocaps handling
    readonly property bool isShifted: shiftKeyPressed
                                      || shiftState === ShiftState.LatchedShift
                                      || shiftState === ShiftState.LockedShift
                                      || (shiftState === ShiftState.AutoShift && autocaps
                                          && (!inputHandler
                                              || typeof inputHandler.preedit !== "string"
                                              || inputHandler.preedit.length === 0))
    readonly property bool isShiftLocked: shiftState === ShiftState.LockedShift
    readonly property alias languageSelectionPopupVisible: languageSelectionPopup.visible

    property bool inSymView
    property bool inSymView2
    // allow chinese input handler to override enter key state
    property bool chineseOverrideForEnter
    property bool pasteEnabled: !_pasteDisabled && Clipboard.hasText
    property bool _pasteDisabled
    Binding on _pasteDisabled {
        // avoid change when keyboard is hiding
        when: MInputMethodQuick.active
        value: !!MInputMethodQuick.extensions.pasteDisabled
    }

    property bool silenceFeedback
    property bool layoutChangeAllowed
    property string deadKeyAccent
    property bool shiftKeyPressed
    // counts how many character keys have been pressed since the ActivePoints array was empty
    property int characterKeyCounter
    property bool closeSwipeActive
    property int closeSwipeThreshold: Math.max(currentLayoutHeight*.3, Theme.itemSizeSmall)

    /* --- okboard begin --- */
    property bool inCurve
    property int curveLastX
    property int curveLastY
    property int curveStartX
    property int curveStartY
    property bool disablePopper
    property bool curvepreedit: curve.curvepreedit  // just a proxy
    property string curveerror: curve.errormsg // proxy
    property double scaling_ratio: curve.scaling_ratio // idem
    property string wpm: curve.wpm // idem
    property string preedit: inputHandler.preedit?inputHandler.preedit:""
    property int curveCount
    property int curveIndex
    /* --- okboard end --- */

    readonly property real currentLayoutHeight: layout ? layout.height : 2 * Theme.itemSizeHuge
    readonly property real minimumLayoutHeight: {
        var height = currentLayoutHeight

        if (moving) {
            var items = keyboard.exposedItems
            for (var i = 0; i < items.length; ++i) {
                height = Math.min(height, items[i].height)
            }
        }

        return height
    }

    // Can be changed to PreeditTestHandler to have another mode of input
    property Item inputHandler: InputHandler {
    }

    readonly property bool swipeGestureIsSafe: !releaseTimer.running
    readonly property string sourceDirectory: "/usr/share/maliit/plugins/com/jolla/layouts/"

    verticalAlignment: PagedView.AlignBottom

    onPortraitModeChanged: cancelAllTouchPoints()

    // if height changed while touch point was being held
    // we can't rely on point values anymore
    onHeightChanged: closeSwipeActive = false

    onMovingChanged: {
        if (moving) {
            cancelAllTouchPoints()
        }
    }

    delegate: Item {
        id: layoutDelegate

        property Item loadedLayout: layoutLoader.item
        property Item loader: layoutLoader
        readonly property bool exposed: layoutLoader.status === Loader.Ready && PagedView.exposed
        readonly property bool current: layoutLoader.status === Loader.Ready && PagedView.isCurrentItem

        width: keyboard.width
        height: layoutLoader.height

        onExposedChanged: {
            // Reset the layout keyboard state when it is dragged into view.
            var attributes = exposed && !PagedView.isCurrentItem ? layoutLoader.item.attributes : null

            if (attributes) {
                attributes.isShifted = keyboard.shouldUseAutocaps(layoutLoader.item)
                attributes.inSymView = false
                attributes.inSymView2 = false
                attributes.isShiftLocked = false
            }
        }

        onCurrentChanged: {
            var attributes = layoutLoader.item.attributes

            if (current) {
                // Bind to the active keyboad state when made the current layout.
                attributes.isShifted = Qt.binding(function() { return keyboard.isShifted })
                attributes.inSymView = Qt.binding(function() { return keyboard.inSymView })
                attributes.inSymView2 = Qt.binding(function() { return keyboard.inSymView2 })
                attributes.isShiftLocked = Qt.binding(function() { return keyboard.isShiftLocked })
            } else {
                // Break bindings to the active keyboard state when replaced as the current item
                // to keep the visual appearance stable as it slides away.
                attributes.isShifted = attributes.isShifted
                attributes.inSymView = attributes.inSymView
                attributes.inSymView2 = attributes.inSymView2
                attributes.isShiftLocked = attributes.isShiftLocked
            }
        }

        KeyboardBackground {
            width: layoutDelegate.width
            height: layoutDelegate.height
            transformItem: keyboard
        }

        Loader {
            id: layoutLoader

            anchors.horizontalCenter: parent.horizontalCenter
            width: keyboard.portraitMode ? keyboard.width : geometry.keyboardWidthLandscape
            height: status === Loader.Error ? Theme.itemSizeHuge : implicitHeight
            source: keyboard.sourceDirectory + model.file
        }
    }

    Popper {
        id: popper

        z: 10
        target: lastPressedKey
        onExpandedChanged: {
            if (expanded) {
                keyboard.cancelGesture()
            }
        }
    }

    LanguageSelectionPopup {
        id: languageSelectionPopup
        z: 11
    }

    Timer {
        id: pressTimer
        interval: 500
    }

    Timer {
        id: releaseTimer
        interval: 300
    }

    Timer {
        id: languageSwitchTimer

        interval: 500
        onTriggered: {
            if (canvas.layoutModel.enabledCount > 1) {
                var point = ActivePoints.findByKeyId(Qt.Key_Space)
                languageSelectionPopup.show(point)
            }
        }
    }

    Timer {
        id: autocapsTimer

        interval: 1
        onTriggered: applyAutocaps()
    }

    /* --- okboard begin --- */
    Timer {
        id: curveDisableTimer
        interval: 400  // a bit smaller than Popper timer to make sure curve is disabled when selecting an item in the Popper
        onTriggered: {
            resetCurve()
        }
    }
    /* --- okboard end --- */

    QuickPick {
        id: quickPick
    }

    Connections {
        target: MInputMethodQuick
        onCursorPositionChanged: {
            if (MInputMethodQuick.surroundingTextValid) {
                applyAutocaps()

                if (shiftState !== ShiftState.LockedShift) {
                    resetShift()
                }
            }
        }
        onFocusTargetChanged: {
            if (activeEditor) {
                resetKeyboard()
                autocapsTimer.start() // focus change may come before updated context, delay handling
            }
        }
        onInputMethodReset: {
            if (inputHandler) {
                inputHandler._reset()
            }
        }
    }

    ConfigurationValue {
        id: useMouseEvents
        key: "/sailfish/text_input/use_mouse_events"
        defaultValue: false
    }


    /* --- okboard begin --- */
    Gribouille {
        id: curve
        opacity: 1
        anchors.fill: parent
    }
    /* --- okboard end --- */


    MouseArea {
        id: mouseArea

        enabled: useMouseEvents.value
        anchors.fill: parent
        z: -1

        onPressed: {
            startX = mouse.x
            startY = mouse.y
            keyboard.handlePressed(createPointArray(mouse.x, mouse.y))
        }
        onPositionChanged: keyboard.handleUpdated(createPointArray(mouse.x, mouse.y))
        onReleased: keyboard.handleReleased(createPointArray(mouse.x, mouse.y))
        onCanceled: keyboard.cancelAllTouchPoints()

        property real startX
        property real startY

        function createPointArray(pointX, pointY) {
            var pointArray = new Array
            pointArray.push({"pointId": 1, "x": pointX, "y": pointY,
                             "startX": startX, "startY": startY })
            return pointArray
        }
    }

    MultiPointTouchArea {
        anchors.fill: parent
        enabled: !useMouseEvents.value

        // Position this below the PagedView contentItem so it doesn't intercept events that would
        // have been handled by an interactive item in a keyboard layout.
        z: -1

        onPressed: keyboard.handlePressed(touchPoints)
        onUpdated: keyboard.handleUpdated(touchPoints)
        onReleased: keyboard.handleReleased(touchPoints)
        onCanceled: keyboard.handleCanceled(touchPoints)

        onGestureStarted: {
            if (mouseArea.preventStealing) {
                // QTBUG-48314&QTBUG-44372
                // MultiPointTouchArea onGestureStarted: gesture.grab() does not get released on a touch release
                // gesture.grab()
                keyboard.interactive = false
            }
        }
    }

    function cancelGesture() {
        if (ActivePoints.array.length > 0) {
            mouseArea.preventStealing = true
        }
    }

    function handlePressed(touchPoints) {
        if (languageSelectionPopup.visible) {
            return
        }

        closeSwipeActive = true
        silenceFeedback = false
        pressTimer.start()

        /*
        for (var i = 0; i < touchPoints.length; i++) {
            var point = ActivePoints.addPoint(touchPoints[i])
            updatePressedKey(point)
        }
        */
        okbHandlePressed(touchPoints); // okboard


        if (ActivePoints.array.length > 1) {
            keyboard.interactive = false // disable keyboard drag until all the touchpoints are released
        }
    }

    function handleUpdated(touchPoints) {
        if (languageSelectionPopup.visible) {
            languageSelectionPopup.handleMove(touchPoints[0])
            return
        }

	okbHandleUpdated(touchPoints); // okboard

        for (var i = 0; i < touchPoints.length; i++) {
            var incomingPoint = touchPoints[i]
            var point = ActivePoints.findById(incomingPoint.pointId)
            if (point === null)
                continue

            point.x = incomingPoint.x
            point.y = incomingPoint.y

            if (ActivePoints.array.length === 1 && closeSwipeActive && pressTimer.running) {
                var yDiff = point.y - point.startY
                silenceFeedback = (yDiff > Math.abs(point.x - point.startX))

                if (yDiff >= Theme.startDragDistance) {
                    mouseArea.preventStealing = true
                }

                if (yDiff > closeSwipeThreshold && !MInputMethodQuick.extensions.keyboardClosingDisabled) {
                    // swiped down to close keyboard
                    MInputMethodQuick.userHide()
                    if (point.pressedKey) {
                        inputHandler._handleKeyRelease()
                        point.pressedKey.pressed = false
                    }
                    lastPressedKey = null
                    pressTimer.stop()
                    languageSwitchTimer.stop()
                    ActivePoints.remove(point)
                    return
                }
            } else {
                silenceFeedback = false
            }

            if (popper.expanded && point.pressedKey === lastPressedKey) {
                popper.setActiveCell(point.x, point.y)
            } else {
                updatePressedKey(point)
            }
        }
    }

    function updatePressedKey(point) {
        var key = keyAt(point.x, point.y)
        if (point.pressedKey === key)
            return

        if (!silenceFeedback) buttonPressEffect.play()

        if (key && !silenceFeedback) {
            if (typeof key.keyType !== 'undefined' && key.keyType === KeyType.CharacterKey && key.text !== " ") {
                SampleCache.play("/usr/share/sounds/jolla-ambient/stereo/keyboard_letter.wav")
            } else {
                SampleCache.play("/usr/share/sounds/jolla-ambient/stereo/keyboard_option.wav")
            }
        }

        if (point.pressedKey !== null) {
            inputHandler._handleKeyRelease()
            point.pressedKey.pressed = false
        }

        point.pressedKey = key
        if (!point.initialKey) {
            point.initialKey = point.pressedKey
            lastInitialKey = point.initialKey
        }

        languageSwitchTimer.stop()
        lastPressedKey = point.pressedKey

        if (point.pressedKey !== null) {
            // when typing fast with two finger, one finger might be still pressed when the other hits screen.
            // on that case, trigger input from previous character
            releasePreviousCharacterKey(point)
            point.pressedKey.pressed = true
            inputHandler._handleKeyPress(point.pressedKey)
            if (point.pressedKey.key === Qt.Key_Space && layoutChangeAllowed)
                languageSwitchTimer.start()
        }
    }

    function handleReleased(touchPoints) {
        releaseTimer.restart()

        if (languageSelectionPopup.visible) {
            if (languageSelectionPopup.opening) {
                languageSelectionPopup.hide()
            } else {
                cancelAllTouchPoints()
                languageSelectionPopup.hide()
                canvas.switchLayout(languageSelectionPopup.activeCell)

		okbHandleReleased1(touchPoints); // okboard

                return
            }
        }

        for (var i = 0; i < touchPoints.length; i++) {
            var point = ActivePoints.findById(touchPoints[i].pointId)
            if (point === null)
                continue

            if (point.pressedKey === null) {
                ActivePoints.remove(point)
                continue
            }

            if (popper.expanded && point.pressedKey === lastPressedKey) {
                popper.release()
                point.pressedKey.pressed = false
            } else {
                triggerKey(point.pressedKey)
            }

            if (point.pressedKey.keyType !== KeyType.ShiftKey && !isPressed(KeyType.DeadKey)) {
                deadKeyAccent = ""
            }
            if (point.pressedKey === lastPressedKey) {
                lastPressedKey = null
            }

            ActivePoints.remove(point)
        }

        if (ActivePoints.array.length === 0) {
            characterKeyCounter = 0
        }
        languageSwitchTimer.stop()

        if (ActivePoints.array.length === 0) {
            keyboard.interactive = true
            mouseArea.preventStealing = false
        }

        okbHandleReleased2(touchPoints); // okboard
    }

    function handleCanceled(touchPoints) {
        for (var i = 0; i < touchPoints.length; i++) {
            cancelTouchPoint(touchPoints[i].pointId)
        }

        okbHandleCanceled(touchPoints); // okboard
    }

    function keyAt(x, y) {
        if (layout === null)
            return null

        var item = layout
        var current = currentItem

        if (current && current.loadedLayout === layout) {
            x -= current.x + current.loader.x
            y -= current.y + current.loader.y
        } else {
            x -= item.x
            y -= item.y
        }

        while ((item = item.childAt(x, y)) != null) {
            if (typeof item.keyType !== 'undefined' && item.enabled === true) {
                return item
            }

            // Cheaper mapToItem, assuming we're not using anything fancy.
            x -= item.x
            y -= item.y
        }

        return null
    }

    function cancelTouchPoint(pointId) {
        var point = ActivePoints.findById(pointId)
        if (point) {
            if (point.pressedKey) {
                inputHandler._handleKeyRelease()
                point.pressedKey.pressed = false
                if (lastPressedKey === point.pressedKey) {
                    lastPressedKey = null
                }
            }
            if (lastInitialKey === point.initialKey) {
                lastInitialKey = null
            }

            languageSwitchTimer.stop()
            languageSelectionPopup.hide()

            ActivePoints.remove(point)
        }

        if (ActivePoints.array.length === 0) {
            mouseArea.preventStealing = false
        }
    }

    function cancelAllTouchPoints() {
        while (ActivePoints.array.length > 0) {
            cancelTouchPoint(ActivePoints.array[0].pointId)
        }
    }

    function resetKeyboard() {
        cancelAllTouchPoints()

        inSymView = false
        inSymView2 = false

        resetShift()
        if (inputHandler) {
            inputHandler._reset()
        }

        lastPressedKey = null
        lastInitialKey = null
        deadKeyAccent = ""
    }

    function shouldUseAutocaps(layout) {
        if (MInputMethodQuick.surroundingTextValid
                && MInputMethodQuick.contentType === Maliit.FreeTextContentType
                && MInputMethodQuick.autoCapitalizationEnabled
                && !MInputMethodQuick.hiddenText
                && layout && layout.type === "") {

            var position = MInputMethodQuick.cursorPosition
            var text = MInputMethodQuick.surroundingText.substring(0, position)

            if (position == 0
                    || (position == 1 && text[0] === " ")
                    || (position >= 2 && text[position - 1] === " "
                        && ".?!".indexOf(text[position - 2]) >= 0)) {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }

    function applyAutocaps() {
        autocaps = shouldUseAutocaps(layout)
    }

    function cycleShift() {
        if (shiftState === ShiftState.NoShift) {
            shiftState = ShiftState.LatchedShift
        } else if (shiftState === ShiftState.LatchedShift) {
            if (layout && layout.capsLockSupported) {
                shiftState = ShiftState.LockedShift
            } else {
                shiftState = ShiftState.NoShift
            }
        } else if (shiftState === ShiftState.LockedShift) {
            shiftState = ShiftState.NoShift
        } else {
            // exiting automatic shift state
            if (autocaps) {
                shiftState = ShiftState.NoShift
            } else {
                shiftState = ShiftState.LatchedShift
            }
        }
    }

    function resetShift() {
        if (!shiftKeyPressed) {
            shiftState = ShiftState.AutoShift
        }
    }

    function toggleSymbolMode() {
        // Cancel everything else except one symbol key point.
        while (ActivePoints.array.length > 1) {
            var point = ActivePoints.array[0]
            if (point.pressedKey && point.pressedKey.keyType === KeyType.SymbolKey) {
                 point = ActivePoints.array[1]
            }
            cancelTouchPoint(point.pointId)
        }

        inSymView = !inSymView
        if (!inSymView) {
            inSymView2 = false
        }
    }

    function existingCharacterKey(ignoredPoint) {
        for (var i = 0; i < ActivePoints.array.length; i++) {
            var point = ActivePoints.array[i]
            if (point !== ignoredPoint
                    && point.pressedKey
                    && point.pressedKey.keyType === KeyType.CharacterKey) {
                return point
            }
        }
    }

    function releasePreviousCharacterKey(ignoredPoint) {
        var existing = existingCharacterKey(ignoredPoint)
        if (existing) {
            triggerKey(existing.pressedKey)
            ActivePoints.remove(existing)
        }
    }

    function triggerKey(key) {
	okbTriggerKey(key); // okboard

        if (key.keyType !== KeyType.DeadKey) {
            inputHandler._handleKeyClick(key)
        }
        key.clicked()
        inputHandler._handleKeyRelease()
        quickPick.handleInput(key)
        key.pressed = false
    }

    function isPressed(keyType) {
        return ActivePoints.findByKeyType(keyType) !== null
    }

    function updatePopper() {
        if (!popper.expanded) {
            var pressedKey = lastPressedKey
            lastPressedKey = null
            lastPressedKey = pressedKey
        }
    }

    /* --- okboard begin --- */
    // reset curve typing
    function resetCurve() {
        curve.reset()
        inCurve = false
    }


    // send information about layout to curve component
    function updateCurveContext(layout, mode) {
        curve.updateContext(layout, mode);
    }

    // as name implies, found on the internet https://newbedev.com/qml-mouse-absolute-position-in-mousearea
    function getAbsolutePosition(node) {
        var returnPos = {};
        returnPos.x = 0;
        returnPos.y = 0;
        if(node !== undefined && node !== null) {
            var parentValue = getAbsolutePosition(node.parent);
            if ('autocaps' in node) {
                // position of KeyboardBase seems to contain strange values
                // and we can assume it's zero related to its parent
                returnPos.x = parentValue.x;
                returnPos.y = parentValue.y;
            } else {
                returnPos.x = parentValue.x + node.x;
                returnPos.y = parentValue.y + node.y;
            }
        }
        return returnPos;
    }

    // curvekb: dump text keys to c++ plugin
    function dumpKeys() {
        if (layout) {
            var abs = getAbsolutePosition(layout);
            curve.setOffset(abs.x, abs.y);
        }
        var lst = keyboard.getTextKeys();
        curve.loadKeys(lst);
    }

    // compute keys list w/ coordinates
    function getTextKeys(item) {
        if (typeof(item) === 'undefined') { item = layout; }
        if (! item) { return; }
        var array_out = new Array;

        if (typeof item.keyType !== 'undefined' && item.enabled === true &&
	    item.caption && item.caption.length == 1) {

            var key_info = new Object;
            key_info.x = item.x;
            key_info.y = item.y;
            key_info.width = item.width;
            key_info.height = item.height;
            key_info.caption = item.caption;
            array_out.push(key_info);
            return array_out;
        }

        for (var i = 0; i < item.children.length; i ++) {
            var child = item.children[i];
            var keys = getTextKeys(child);
            for (var j = 0; j < keys.length; j ++) {
                var key_info = keys[j];
                key_info.x += item.x;
                key_info.y += item.y;
                array_out.push(key_info);
            }
        }

        return array_out;
    }

    function get_predict_words(callback) {
        curve.get_predict_words(callback);
    }

    function commitWord(word) {
        curve.commitWord(word, true, undefined);
    }

    function clearError() {
	curve.clearError();
    }

    /* additional processings for event handlers */

    function okbHandlePressed(touchPoints) {
        if (! inCurve) {
            // curve typing: take over multi-touch operations

            for (var i = 0; i < touchPoints.length; i++) {
                var point = ActivePoints.addPoint(touchPoints[i])
                updatePressedKey(point, true)
            }
        }

        if (curve.is_ready() && ! inSymView) {
            if (! curve.keys_ok) {
                dumpKeys();
            }

            for(var i = 0; i < touchPoints.length; i++) {
                if (! inCurve) {
                    curveCount = 0;
                    curveIndex = 0;
                    inCurve = true;
                    curve.start()

                    disablePopper = false;
                    curveDisableTimer.stop();
                    curveDisableTimer.start();
                }

                var id = touchPoints[i].pointId;

                var cur = {}
                cur.curveIndex = curveIndex;
                cur.curveStartX = cur.curveLastX = touchPoints[i].x;
                cur.curveStartY = cur.curveLastY = touchPoints[i].y;
                InProgress.set(id, cur);

                curveIndex++;
                curveCount++;

                curve.addPoint(touchPoints[i], cur.curveIndex);
                // var s = "==> Curve start #" + id + " " + touchPoints[i].x + "," + touchPoints[i].y; curve.log(s);

            }

        } else {
            resetCurve();
        }
    }

    function okbHandleUpdated(touchPoints) {
	if (inCurve) {
            for(var i = 0; i < touchPoints.length; i++) {
                var id = touchPoints[i].pointId;

                var point = touchPoints[i];
                var cur = InProgress.get(id);

                if (Math.abs(point.x - cur.curveLastX) >= 10 * scaling_ratio
		    || Math.abs(point.y - cur.curveLastY) >= 10 * scaling_ratio) {
                    curve.addPoint(point, cur.curveIndex);
                    cur.curveLastX = point.x;
                    cur.curveLastY = point.y;
                    InProgress.set(id, cur); // needed ?
                }
                if (! disablePopper) {
                    if (Math.abs(point.x - cur.curveStartX) >= 50 * scaling_ratio
			|| Math.abs(point.y - cur.curveStartY) >= 50 * scaling_ratio
			|| curveCount >= 2) {
                        disablePopper = true;
                        cancelAllTouchPoints();
                        curveDisableTimer.stop();
                    }
                }
            }
            if (disablePopper) { return; }
        }
    }

    function okbHandleReleased1(touchPoints) {
	// if (languageSelectionPopup.activeCell > 0) {
        //     curve.updateContext(canvas.layoutModel.get(languageSelectionPopup.activeCell).layout);
        // }
    }

    function okbHandleReleased2(touchPoints) {
        if (inCurve) {
            for(var i = 0; i < touchPoints.length; i++) {
                var id = touchPoints[i].pointId;
                var point = touchPoints[i];
                var cur = InProgress.get(id);

                // var s = "==> Curve end #" + id + " " + touchPoints[i].x + "," + touchPoints[i].y; curve.log(s);
                curve.endCurve(cur.curveIndex);
                curveCount --;
                InProgress.remove(id);
            }
            if (curveCount == 0) {
                // curve.log("==> Curve completed");
                curve.done(disablePopper);
                inCurve = false;
            }
        }
    }

    function okbHandleCanceled(touchPoints) {
        if (inCurve) {
            resetCurve();
        }
    }

    function okbTriggerKey(key) {
	if (curve.is_ready()) {
            if (curve.curvepreedit) {
		if (key.key === Qt.Key_Backspace) {
                    // backspace erases a full word inserted by curve typing
		    curve.backspace();
		} else if (key.text.length > 0 && key.text >= 'a' && key.text <= 'z') {
                    // if we type a single letter when in preedit mode caused by curve typing, we insert a space because it's the beginning of a new word
                    autocaps = false // if the first word was autocaps the new one is not
                    curve.insertSpace();
		}
            }
	}
        curve.curvepreedit = false;
    }

    function log(message) { curve.log(message); }

    /* --- okboard end --- */
}
