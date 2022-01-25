import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import com.jolla.settings.system 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    name: "resolv " + resolvConfName
    icon.source: "image://theme/icon-m-download"
    showOnOffLabel: false
    onToggled: {
      readProc(["sudo", "resolv", "--cycle", "f", "m"])
      updateResolvConfName();
    }
    property var resolvConfName: "?"
    checked: false
    busy: false

    Component.onCompleted: updateResolvConfName();

    onVisibleChanged: {
      if(visible){
        updateResolvConfName();
      }
    }

    function updateResolvConfName() {
      var confName = readProc(["cat", "/etc/resolv.conf.confname"])
      confName = confName.replace(/(\n|\r)+$/, '');
      resolvConfName = confName
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
