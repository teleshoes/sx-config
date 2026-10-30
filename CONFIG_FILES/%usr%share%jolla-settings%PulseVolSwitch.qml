import QtQuick 2.0
import Sailfish.Silica 1.0
import com.jolla.settings.system 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    property var pulseVol: 0

    property var defaultTarget: 150

    name: "pv" + pulseVol
    icon.source: "image://theme/icon-m-sounds"
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

    CutesActor {
      id: readProcActor
      source: "file:///usr/share/cutes/read_proc_actor.js"
    }

    Component.onCompleted: retrievePulseVol();

    onVisibleChanged: {
      if(visible){
        retrievePulseVol();
      }
    }

    function retrievePulseVol() {
      var cmdStr = "/usr/local/bin/pulse-vol -g"
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          setCurPulseVolStr(val);
        },
        on_error: function(e) {
          console.log("ERROR: " + cmdStr + " failed", e);
          setCurState("error");
        }
      });
    }

    function setCurPulseVolStr(curVolStr){
      console.log("pulse vol: " + curVolStr)
      curVolStr = curVolStr.replace(/(\n|\r)+$/, '');
      pulseVol = parseInt(curVolStr, 10);
    }

    function setPulseVol(targetVol) {
      var cmdStr = "/usr/local/bin/pulse-vol " + targetVol
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          console.log("OK: " + cmdStr);
          retrievePulseVol();
        },
        on_error: function(e) {
          console.log("ERROR: " + cmdStr + " failed", e);
        }
      });
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
}
