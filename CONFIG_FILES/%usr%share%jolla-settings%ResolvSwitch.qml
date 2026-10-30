import QtQuick 2.0
import Sailfish.Silica 1.0
import com.jolla.settings.system 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    name: "resolv " + resolvConfName
    icon.source: "image://theme/icon-m-downloads"
    showOnOffLabel: false
    onToggled: {
      runProc("sudo resolv --cycle")
      updateResolvConfName();
    }
    property var resolvConfName: "?"
    checked: false
    busy: false

    CutesActor {
      id: readProcActor
      source: "file:///usr/share/cutes/read_proc_actor.js"
    }

    Component.onCompleted: updateResolvConfName();

    onVisibleChanged: {
      if(visible){
        updateResolvConfName();
      }
    }

    function updateResolvConfName() {
      var cmdStr = "cat /etc/resolv.conf.confname"
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          setCurResolvConfName(val);
        },
        on_error: function(e) {
          console.log("ERROR: " + cmdStr + " failed", e);
          setCurState("error");
        }
      });
    }

    function setCurResolvConfName(confName){
      confName = confName.replace(/(\n|\r)+$/, '');
      resolvConfName = confName
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
