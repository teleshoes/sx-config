import QtQuick 2.0
import Sailfish.Silica 1.0
import com.jolla.settings.system 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    property var lpmEnabled: false

    name: "LPM"
    icon.source: "image://theme/custom-icon-m-lpm"
    showOnOffLabel: true

    checked: lpmEnabled
    busy: false

    onToggled: {
      setLpmEnabled(!lpmEnabled);
    }

    CutesActor {
      id: readProcActor
      source: "file:///usr/share/cutes/read_proc_actor.js"
    }

    Component.onCompleted: retrieveLpmEnabled();

    onVisibleChanged: {
      if(visible){
        retrieveLpmEnabled();
      }
    }

    function retrieveLpmEnabled() {
      var cmdStr = "lock --is-lpm-enabled"
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

    function setCurState(lpmStr){
      if(!lpmStr){
        lpmStr = "";
      }
      lpmStr = lpmStr.trim();
      if(lpmStr == "enabled"){
        lpmEnabled = true;
      }else{
        lpmEnabled = false;
      }
      console.log("lpm: " + lpmStr);
    }

    function setLpmEnabled(isEnabled) {
      busy = true;
      var lockArg = isEnabled ? "--lpm-enable" : "--lpm-disable"
      var cmdStr = "lock " + lockArg
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          console.log("OK: " + cmdStr)
          retrieveLpmEnabled();
          busy = false;
        },
        on_error: function(e) {
          console.log("ERROR: " + cmdStr + " failed", e);
          setCurState("error");
          busy = false;
        }
      });
    }
}
