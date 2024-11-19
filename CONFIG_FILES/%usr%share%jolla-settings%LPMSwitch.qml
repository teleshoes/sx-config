import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
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

    Component.onCompleted: retrieveLpmEnabled();

    onVisibleChanged: {
      if(visible){
        retrieveLpmEnabled();
      }
    }

    function retrieveLpmEnabled() {
      var lpmStr = readProc(["sh", "-c", "lock --is-lpm-enabled"]);
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
      if(isEnabled){
        readProc(["sh", "-c", "lock --lpm-enable"]);
      }else{
        readProc(["sh", "-c", "lock --lpm-disable"]);
      }
      retrieveLpmEnabled()
      busy = false;
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
