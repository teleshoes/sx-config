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

import QtQuick 2.0
import Sailfish.Silica 1.0
import com.meego.maliitquick 1.0
import com.jolla.keyboard 1.0
import org.nemomobile.configuration 1.0
import "touchpointarray.js" as ActivePoints

import eu.cpbm.okboard 1.0 // okboard
import com.jolla 1.0 // okboard
import "curves.js" as InProgress // okboard

Item { // <- okboard replace SwipeGestureArea (we are doing our own swipe handling)
    id: keyboard

    property Item layout
    property bool portraitMode

    property Item lastPressedKey
    property Item lastInitialKey

    property int shiftState: ShiftState.NoShift
    readonly property bool isShifted: shiftKeyPressed
                                      || shiftState === ShiftState.LatchedShift
                                      || shiftState === ShiftState.LockedShift
    readonly property bool isShiftLocked: shiftState === ShiftState.LockedShift
    readonly property alias languageSelectionPopupVisible: languageSelectionPopup.visible

    property bool inSymView
    property bool inSymView2
    // allow chinese input handler to override enter key state
    property bool chineseOverrideForEnter

    property bool silenceFeedback
    property bool layoutChangeAllowed
    property string deadKeyAccent
    property bool shiftKeyPressed
    // counts how many character keys have been pressed since the ActivePoints array was empty
    property int characterKeyCounter
    property bool closeSwipeActive
    property int closeSwipeThreshold: Math.max(height*.3, Theme.itemSizeSmall)

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

    property QtObject nextLayoutAttributes: QtObject {
        property bool isShifted
        property bool inSymView
        property bool inSymView2
        property bool isShiftLocked
        property bool chineseOverrideForEnter

        function update(layout) {
            // Figure out what state we want to animate the next layout in
            isShifted = false
            inSymView = false
            inSymView2 = false
            isShiftLocked = false
            chineseOverrideForEnter = keyboard.chineseOverrideForEnter
        }
    }

    // Can be changed to PreeditTestHandler to have another mode of input
    property Item inputHandler: InputHandler {
    }

    readonly property bool swipeGestureIsSafe: !releaseTimer.running

    height: layout ? layout.height : 0
    onLayoutChanged: if (layout) layout.parent = keyboard
    onPortraitModeChanged: cancelAllTouchPoints()

    // if height changed while touch point was being held
    // we can't rely on point values anymore
    onHeightChanged: closeSwipeActive = false

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
                if (shiftState !== ShiftState.LockedShift) {
                    resetShift()
                }
            }
        }
        onFocusTargetChanged: {
            if (activeEditor) {
                resetKeyboard()
            }
        }
        onInputMethodReset: {
            inputHandler._reset()
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
        enabled: useMouseEvents.value
        anchors.fill: parent

        onPressed: keyboard.handlePressed(createPointArray(mouse.x, mouse.y))
        onPositionChanged: keyboard.handleUpdated(createPointArray(mouse.x, mouse.y))
        onReleased: keyboard.handleReleased(createPointArray(mouse.x, mouse.y))
        onCanceled: keyboard.cancelAllTouchPoints()

        function createPointArray(pointX, pointY) {
            var pointArray = new Array
            pointArray.push({"pointId": 1, "x": pointX, "y": pointY,
                             "startX": pointX, "startY": pointY })
            return pointArray
        }
    }

    MultiPointTouchArea {
        anchors.fill: parent
        enabled: !useMouseEvents.value

        onPressed: keyboard.handlePressed(touchPoints)
        onUpdated: keyboard.handleUpdated(touchPoints)
        onReleased: keyboard.handleReleased(touchPoints)
        onCanceled: keyboard.handleCanceled(touchPoints)
    }

    function handlePressed(touchPoints) {
        if (languageSelectionPopup.visible) {
            return
        }

        closeSwipeActive = true
        silenceFeedback = false
        pressTimer.start()

	/* okboard remove
        for (var i = 0; i < touchPoints.length; i++) {
            var point = ActivePoints.addPoint(touchPoints[i])
            updatePressedKey(point)
        }
	*/
	okbHandlePressed(touchPoints); // okboard
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

                if (yDiff > closeSwipeThreshold) {
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

        x -= layout.x
        y -= layout.y

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
        if (!point)
            return

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
        inputHandler._reset()

        lastPressedKey = null
        lastInitialKey = null
        deadKeyAccent = ""
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
            shiftState = ShiftState.LatchedShift
        }
    }

    function resetShift() {
        if (!shiftKeyPressed) {
            shiftState = ShiftState.NoShift
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
    function updateCurveContext() {
        curve.updateContext(canvas.layoutModel.get(layoutRow.loader.index).layout, mode);
    }

    // curvekb: dump text keys to c++ plugin
    function dumpKeys() {
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

    function cancelGesture() {
	// expose this function because it is called from LanguageSelectionPopup
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

        if (curve.is_ready()) {
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
                    // var s = "==> Curve point #" + id + " " + touchPoints[i].x + "," + touchPoints[i].y; curve.log(s);
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
	if (languageSelectionPopup.activeCell > 0) {
            curve.updateContext(canvas.layoutModel.get(languageSelectionPopup.activeCell).layout);
        }
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
                    curve.insertSpace();
		}
            }
	}
        curve.curvepreedit = false;
    }

    function log(message) { curve.log(message); }

    /* --- okboard end --- */
}
