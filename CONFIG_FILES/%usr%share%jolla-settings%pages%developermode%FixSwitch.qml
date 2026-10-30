import QtQuick 2.0
import Sailfish.Silica 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    name: "fix"
    icon.source: "image://theme/icon-m-diagnostic"
    checked: false

    CutesActor {
      id: readProcActor
      source: "file:///usr/share/cutes/read_proc_actor.js"
    }

    ListModel {
        id: fixNameModel
    }

    menu: ContextMenu {
        Repeater {
            model: fixNameModel
            MenuItem {
               text: fixName
               onClicked: runFix(fixName)
            }
        }
    }

    onToggled: {
        openMenu()
    }

    Component.onCompleted: {
        buildFixNameMenu()
    }

    function buildFixNameMenu(){
      var cmdStr = "/usr/local/bin/fix --csv"
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          setFixNamesCsv(val);
        },
        on_error: function(e) {
          console.log("ERROR: " + cmdStr + " failed", e);
          setCurState("error");
        }
      });
    }

    function setFixNamesCsv(csvStr){
        console.log("fix names csv: " + csvStr)
        var fixNames = csvStr.trim().split(",")

        fixNameModel.clear()
        for (var i = 0; i < fixNames.length; i++) {
            var fixName = fixNames[i]
            fixNameModel.append({"fixName": fixName})
        }
    }

    function runFix(fixName) {
      console.log("FIX: " + fixName)
      runProc("/usr/local/bin/fix --daemon " + fixName)
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
