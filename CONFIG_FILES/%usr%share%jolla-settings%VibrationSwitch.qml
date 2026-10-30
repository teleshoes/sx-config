import QtQuick 2.0
import Sailfish.Silica 1.0
import com.jolla.settings.system 1.0
import com.jolla.settings 1.0
import org.nemomobile.systemsettings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    ProfileControl { id: soundSettings }

    property var ngfdActive: false

    name: "Tap+Vibe"
    icon.source: "image://theme/icon-m-vibration"
    showOnOffLabel: true

    checked: ngfdActive
    busy: false

    onToggled: {
      setNgfdActive(!ngfdActive);
    }

    CutesActor {
      id: readProcActor
      source: "file:///usr/share/cutes/read_proc_actor.js"
    }

    Component.onCompleted: retrieveNgfdStatus();

    onVisibleChanged: {
      if(visible){
        retrieveNgfdStatus();
      }
    }

    function retrieveNgfdStatus() {
      var cmdStr = "systemctl --user is-active ngfd"
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          setCurNgfdStatus(val);
        },
        on_error: function(e) {
          console.log("ERROR: " + cmdStr + " failed", e);
          setCurState("error");
        }
      });
    }

    function setCurNgfdStatus(activeStr){
      if(!activeStr){
        activeStr = "";
      }
      activeStr = activeStr.trim();
      console.log("vibration ngfd: " + activeStr);
      if(activeStr == "active"){
        ngfdActive = true;
      }else{
        ngfdActive = false;
      }
    }

    function setNgfdActive(isActive) {
      busy = true;
      if(isActive){
        runProc("systemctl --user restart ngfd");
        soundSettings.touchscreenToneLevel = 1
      }else{
        runProc("systemctl --user stop ngfd");
        soundSettings.touchscreenToneLevel = 0
      }
      retrieveNgfdStatus()
      busy = false;
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
