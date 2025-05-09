import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
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

    Component.onCompleted: retrieveNgfdStatus();

    onVisibleChanged: {
      if(visible){
        retrieveNgfdStatus();
      }
    }

    function retrieveNgfdStatus() {
      var activeStr = readProc(["sh", "-c", "systemctl --user is-active ngfd"]);
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
        readProc(["sh", "-c", "systemctl --user restart ngfd"]);
        soundSettings.touchscreenToneLevel = 1
      }else{
        readProc(["sh", "-c", "systemctl --user stop ngfd"]);
        soundSettings.touchscreenToneLevel = 0
      }
      retrieveNgfdStatus()
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
