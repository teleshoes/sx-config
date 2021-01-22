import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0
import Nemo.Ngf 1.0
import com.jolla.settings 1.0
import com.jolla.settings.system 1.0
import org.nemomobile.systemsettings 1.0

import Mer.Cutes 1.1

Item {
    id: root

    property QtObject slider

    property bool initializing

    function updateSliderValue() {
        var volStep = getVolume()
        slider.value = volStep
    }
    function getVolume() {
      var volStep = Math.floor(readProc(["/usr/local/bin/vol", "--read"]))
      if (volStep < 0) {
        volStep = 0
      }
      if (volStep > 11) {
        volStep = 11
      }
      return volStep
    }
    function setVolume(volStep) {
      readProc(["/usr/local/bin/vol", "--set", volStep])
    }

    state: "default"

    states: State {
        name: "default"

        PropertyChanges {
            target: slider
            height: slider.implicitHeight + valueLabel.height + Theme.paddingSmall
            label: "Media volume"

            maximumValue: 11
            minimumValue: 0
            stepSize: 1

            onValueChanged: {
                if(!initializing){
                    setVolume(slider.value)
                }
            }
        }
    }

    Component.onCompleted: {
        root.initializing = true
        slider.animateValue = false

        slider.color = "#009955"
        root.updateSliderValue()

        root.initializing = false
        slider.animateValue = true
    }

    SliderValueLabel {
        id: valueLabel

        parent: root.slider
        slider: root.slider

        text: slider.value > 0 ? slider.value : ""
        scale: slider.pressed ? Theme.fontSizeLarge / Theme.fontSizeMedium : 1.0
        font.pixelSize: Theme.fontSizeMedium
    }

    HighlightImage {
        x: valueLabel.x + (valueLabel.width / 2) - (width / 2)
        y: valueLabel.y + (valueLabel.height / 2) - (height / 2)
        source: "image://theme/icon-status-silent"
        highlighted: slider.highlighted
        visible: slider.value === 0
        scale: slider.down ? Theme.fontSizeLarge / Theme.fontSizeMedium : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }
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
