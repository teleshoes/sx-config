import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import com.jolla.settings.system 1.0
import com.jolla.settings 1.0
import Mer.Cutes 1.1

SettingsToggle {
    property var hrmonState: "off" //'off', 'waiting', 'error' or '###'

    name: "hr:" + hrmonState
    icon.source: "image://theme/icon-m-watch"
    showOnOffLabel: true

    checked: hrmonState != "off" && hrmonState != "error"
    busy: false

    onToggled: {
      if(hrmonState == "off"){
        setHrmonEnabled(true);
      }else{
        setHrmonEnabled(false);
      }
    }

    Component.onCompleted: retrieveHrmonState();

    onVisibleChanged: {
      if(visible){
        retrieveHrmonState();
      }
    }

    function retrieveHrmonState() {
      var curState = readProc(["sh", "-c", "udo /usr/local/bin/hrmon -g"]);
      curState = curState.replace(/(\n|\r)+$/, '');
      console.log(curState);

      var ptrn = /^(off|waiting|[0-9]+)$/;
      var match = curState.match(ptrn);
      if(match){
        hrmonState = match[0];
      }else{
        hrmonState = "error"
      }
    }

    function setHrmonEnabled(isEnabled) {
      var hrmonArg = isEnabled ? "--start" : "--stop"
      readProc(["sh", "-c", "udo /usr/local/bin/hrmon " + hrmonArg]);
      retrieveHrmonState();
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
