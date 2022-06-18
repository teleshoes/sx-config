import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import com.jolla.settings.system 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    name: "volte " + volteStatus
    icon.source: "image://theme/icon-m-media-radio"
    showOnOffLabel: false
    onToggled: {
      readProc(["sudo", "volte", "--toggle"])
      updateVolteStatus();
    }
    property var volteStatus: "?"
    checked: false
    busy: false

    Component.onCompleted: updateVolteStatus();

    onVisibleChanged: {
      if(visible){
        updateVolteStatus();
      }
    }

    function updateVolteStatus() {
      var status = readProc(["volte", "--summary"])
      status = status.replace(/(\n|\r)+$/, '');
      volteStatus = status
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
