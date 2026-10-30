import QtQuick 2.0
import Sailfish.Silica 1.0
import com.jolla.settings.system 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    property var camLensState: "unknown"

    name: "cam-" + camLensState
    icon.source: "image://theme/icon-m-camera"
    showOnOffLabel: false

    checked: false
    busy: false

    CutesActor {
      id: readProcActor
      source: "file:///usr/share/cutes/read_proc_actor.js"
    }

    onToggled: {
    }

    Component.onCompleted: retrieveCamLensState();

    onVisibleChanged: {
      if(visible){
        retrieveCamLensState();
      }
    }

    function retrieveCamLensState() {
      var cmdStr = "/usr/local/bin/cam -g"
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          setCurState(val);
        },
        on_error: function(e) {
          console.log("ERROR: " + cmdStr + " failed", e);
          setCurState("error");
        }
      });
    }

    function setCurState(curState){
      console.log("cam: " + curState)
      curState = curState.replace(/(\n|\r)+$/, '');
      camLensState = curState
    }

    function setCamLensState(state) {
      if(state == "single"){
        runProc("/usr/local/bin/cam --single");
      }else{
        runProc("/usr/local/bin/cam --multi");
      }
      retrieveCamLensState();
    }

    function killCam() {
      runProc("/usr/local/bin/cam --kill");
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

    menu: ContextMenu {
        MenuItem {
            text: "single"
            onClicked: { setCamLensState("single") }
        }
        MenuItem {
            text: "multi"
            onClicked: { setCamLensState("multi") }
        }
        MenuItem {
            text: "kill"
            onClicked: { killCam() }
        }
    }
}
