import QtQuick 2.0
import Sailfish.Silica 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    name: "fix"
    icon.source: "image://theme/icon-m-diagnostic"
    checked: false

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
        var fixNames = getFixNames()
        fixNameModel.clear()
        for (var i = 0; i < fixNames.length; i++) {
            var fixName = fixNames[i]
            fixNameModel.append({"fixName": fixName})
        }
    }

    function getFixNames(){
        var csv = readProc(["sh", "-c", "/usr/local/bin/fix --csv"])
        console.log("fix names: " + csv)
        return csv.trim().split(",")
    }

    function runFix(fixName) {
      console.log("FIX: " + fixName)
      readProc(["sh", "-c", "/usr/local/bin/fix --daemon " + fixName])
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
