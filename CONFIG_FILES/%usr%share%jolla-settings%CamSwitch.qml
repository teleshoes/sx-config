import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
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

    onToggled: {
    }

    Component.onCompleted: retrieveCamLensState();

    onVisibleChanged: {
      if(visible){
        retrieveCamLensState();
      }
    }

    function retrieveCamLensState() {
      var state = readProc(["sh", "-c", "/usr/local/bin/cam -g"]);
      console.log("cam: " + state)
      state = state.replace(/(\n|\r)+$/, '');
      camLensState = state
    }

    function setCamLensState(state) {
      if(state == "single"){
        readProc(["sh", "-c", "/usr/local/bin/cam --single"]);
      }else{
        readProc(["sh", "-c", "/usr/local/bin/cam --multi"]);
      }
      retrieveCamLensState();
    }

    function killCam() {
      readProc(["sh", "-c", "/usr/local/bin/cam --kill"]);
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

    function readProc(cmdArr) {
      var cmdExec = cmdArr[0];
      var cmdArgs = cmdArr.slice(1);

      var proc = cutes.require('subprocess').process();
      var res = proc.popen_sync(cmdExec, cmdArgs);
      res.wait(-1);
      return res.stdout().toString();
    }
}
