import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import com.jolla.settings.system 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    property var pulseVol: 0

    property var defaultTarget: 150

    name: "Vibration"
    icon.source: "image://theme/icon-m-vibration"
    showOnOffLabel: false

    checked: pulseVol != 100
    busy: false

    onToggled: {
      var targetVol = 100;
      if(pulseVol == 100){
        targetVol = defaultTarget;
      }else{
        targetVol = 100;
      }

      setPulseVol(targetVol);
    }

    Component.onCompleted: retrievePulseVol();

    onVisibleChanged: {
      if(visible){
        retrievePulseVol();
      }
    }

    function retrievePulseVol() {
      var vol = readProc(["sh", "-c", "/usr/local/bin/pulse-vol -g"]);
      console.log(vol)
      vol = vol.replace(/(\n|\r)+$/, '');
      pulseVol = parseInt(vol, 10);
    }

    function setPulseVol(targetVol) {
      readProc(["sh", "-c", "/usr/local/bin/pulse-vol " + targetVol]);
      retrievePulseVol();
    }

    menu: ContextMenu {
        MenuItem {
            text: "pv200"
            onClicked: { setPulseVol(200) }
        }
        MenuItem {
            text: "pv175"
            onClicked: { setPulseVol(175) }
        }
        MenuItem {
            text: "pv150"
            onClicked: { setPulseVol(150) }
        }
        MenuItem {
            text: "pv125"
            onClicked: { setPulseVol(125) }
        }
        MenuItem {
            text: "pv100"
            onClicked: { setPulseVol(100) }
        }
        MenuItem {
            text: "pv50"
            onClicked: { setPulseVol(50) }
        }
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
