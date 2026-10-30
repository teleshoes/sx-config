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

    property int maxVolumeStep: 100 /* set onVisible */

    property bool initializing

    CutesActor {
      id: readProcActor
      source: "file:///usr/share/cutes/read_proc_actor.js"
    }

    onVisibleChanged: {
        if(visible){
            updateSliderValue()
        }
    }

    function updateSliderValue() {
      var cmdStr = "/usr/local/bin/vol --read"
      initializing = true
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          setSliderVolStr(val);
          initializing = false
        },
        on_error: function(e) {
          console.log("ERROR: " + cmdStr + " failed", e);
          initializing = false
        }
      });
    }

    function setSliderVolStr(volStr){
      var stepArr = volStr.split("/")
      var volStep = 0
      var maxVolStep = 0
      if(stepArr.length == 2){
        volStep = Math.floor(stepArr[0])
        maxVolStep = Math.floor(stepArr[1])
      }

      slider.color = "#009955"

      slider.value = volStep
      maxVolumeStep = maxVolStep
    }

    function setVolume(volStep) {
      runProc("/usr/local/bin/vol --set " + volStep)
    }

    state: "default"

    states: State {
        name: "default"

        PropertyChanges {
            id: sliderPropertyChanges
            target: slider
            height: slider.implicitHeight + valueLabel.height + Theme.paddingSmall
            label: "Media volume"

            maximumValue: maxVolumeStep
            minimumValue: 0
            stepSize: 1

            onValueChanged: {
                if(!initializing){
                    setVolume(slider.value)
                }
            }
        }
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

    function runProc(cmdStr) {
      readProcActor.send(cmdStr, {
        on_reply: function(val) {
          console.log("OK: " + cmdStr);
        },
        on_error: function(e) {
          console.log("ERROR: " + cmdStr + " failed", e);
        }
      });
    }
}
