import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import com.jolla.settings.system 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    name: "msg-fix " + pkgState
    icon.source: "image://theme/icon-m-message"
    showOnOffLabel: false
    onToggled: {
      readProc(["sudo", "jolla-messages-fix", "--toggle"])
      updatePkgState();
    }
    property var pkgState: "???"
    checked: false
    busy: false

    Component.onCompleted: updatePkgState();

    onVisibleChanged: {
      if(visible){
        updatePkgState();
      }
    }

    function updatePkgState() {
      var pkgStateOut = readProc(["sudo", "jolla-messages-fix", "--get"]);
      pkgStateOut = pkgStateOut.replace(/(\n|\r)+$/, '');
      pkgState = pkgStateOut;
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
