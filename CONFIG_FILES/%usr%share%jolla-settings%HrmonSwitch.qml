import QtQuick 2.0
import Sailfish.Silica 1.0
import com.jolla.settings.system 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    property var hrmonState: "off" //'off', 'waiting', 'error' or '###'

    property var delayMillisOff: 5000
    property var delayMillisOn: 1000

    name: "hr:" + hrmonState
    icon.source: "image://theme/icon-m-watch"
    showOnOffLabel: true

    checked: hrmonState != "off" && hrmonState != "error"
    busy: false

    CutesActor {
      id: readProcActor
      source: "file:///usr/share/cutes/read_proc_actor.js"
    }

    onToggled: {
      if(hrmonState == "off"){
        setHrmonEnabled(true);
      }else{
        setHrmonEnabled(false);
      }
    }

    Component.onCompleted: retrieveHrmonState();

    onVisibleChanged: {
      if(visible){
        retrieveHrmonState();
        updateTimer.start();
      }else{
        updateTimer.stop();
      }
    }

    Timer {
      id: updateTimer

      interval: delayMillisOff
      repeat: true
      onTriggered: retrieveHrmonState()
    }

    function retrieveHrmonState() {
      var cmdStr = "udo /usr/local/bin/hrmon -g"
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          setCurState(val);
        },
        on_error: function(e) {
          console.log("ERROR: 'hrmon -g' failed", e);
          setCurState("error");
        }
      });
    }

    function setCurState(curState){
      curState = curState.replace(/(\n|\r)+$/, '');
      console.log(curState);

      var ptrn = /^(off|waiting|[0-9]+!?)$/;
      var match = curState.match(ptrn);
      if(match){
        hrmonState = match[0];
      }else{
        hrmonState = "error"
      }

      if(hrmonState == "off" || hrmonState == "waiting"){
        updateTimer.interval = delayMillisOff;
      }else{
        updateTimer.interval = delayMillisOn;
      }
    }

    function setHrmonEnabled(isEnabled) {
      var hrmonArg = isEnabled ? "--start" : "--stop"
      var cmdStr = "udo /usr/local/bin/hrmon " + hrmonArg
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          console.log("OK: hrmon " + hrmonArg)
          retrieveHrmonState();
        },
        on_error: function(e) {
          console.log("ERROR: " + "'hrmon " + hrmonArg + "' failed", e);
          setCurState("error");
        }
      });
    }
}
