import QtQuick 2.0
import Sailfish.Silica 1.0
import com.jolla.settings.system 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    name: "volte " + volteStatus
    icon.source: "image://theme/icon-m-media-radio"
    showOnOffLabel: false
    onToggled: {
      busy = true
      var cmdStr = "udo sudo volte --toggle"
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          updateVolteStatus();
        },
        on_error: function(e) {
          console.log("ERROR: " + cmdStr + " failed", e);
          setCurState("error");
          busy = false
        }
      });
    }
    property var volteStatus: "?"
    checked: false
    busy: false

    CutesActor {
      id: readProcActor
      source: "file:///usr/share/cutes/read_proc_actor.js"
    }

    Component.onCompleted: updateVolteStatus();

    onVisibleChanged: {
      if(visible){
        updateVolteStatus();
      }
    }

    function updateVolteStatus() {
      var cmdStr = "volte --summary"
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          setCurState(val);
          busy = false;
        },
        on_error: function(e) {
          console.log("ERROR: " + cmdStr + " failed", e);
          setCurState("error");
          busy = false;
        }
      });
    }

    function setCurState(status){
      status = status.replace(/(\n|\r)+$/, '');
      volteStatus = status
    }

    function runProc(cmdStr) {
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          console.log("OK: " + cmdStr);
        },
        on_error: function(e) {
          console.log("ERROR: " + cmdStr + " failed", e);
        }
      });
    }
}
