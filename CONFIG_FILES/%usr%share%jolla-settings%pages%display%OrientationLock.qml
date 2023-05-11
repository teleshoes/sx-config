import QtQuick 2.0
import Sailfish.Silica 1.0
import com.jolla.settings 1.0
import org.nemomobile.systemsettings 1.0
import Nemo.Configuration 1.0

SettingsToggle {
    // Lock mode from user point of view
    readonly property bool portraitLock: displaySettings.orientationLock == "portrait" || displaySettings.orientationLock == "portrait-inverted"
    readonly property bool landscapeLock: displaySettings.orientationLock == "landscape" || displaySettings.orientationLock == "landscape-inverted"

    property var lastToggledMillis: 0
    property string lastToggledOrigLock: ""

    name: portraitLock
          ? //% "Portrait"
            qsTrId("settings_system-orientation_portrait")
          : landscapeLock
            ? //% "Landscape"
              qsTrId("settings_system-orientation_landscape")
            : //: Abbreviated form of settings_system-orientation_lock
              //% "Orientation"
              qsTrId("settings_system-orientation_lock_short")

    icon.source: portraitLock
                 ? "image://theme/icon-m-device-portrait"
                 : landscapeLock
                    ? "image://theme/icon-m-device-landscape"
                    : "image://theme/icon-m-orientation-lock"

    checked: displaySettings.orientationLock !== "dynamic"

    onToggled: {
        var nowMillis = Date.now();
        var dblClick = nowMillis - lastToggledMillis < 500 ? true : false;
        var orient = __silica_applicationwindow_instance.orientation;

        var targetLock;
        if (dblClick) {
            if (lastToggledOrigLock == "portrait") {
                targetLock = "landscape";
            } else if (lastToggledOrigLock == "landscape") {
                targetLock = "portrait"
            } else if (orient === Orientation.Portrait) {
                targetLock = "landscape";
            } else {
                targetLock = "portrait";
            }
        } else if (checked) {
            targetLock = "dynamic"
        } else if (orient === Orientation.Portrait) {
            targetLock = "portrait"
        } else if (orient === Orientation.PortraitInverted) {
            targetLock = "portrait-inverted"
        } else if (orient === Orientation.Landscape) {
            targetLock = "landscape"
        } else if (orient === Orientation.LandscapeInverted) {
            targetLock = "landscape-inverted"
        }

        lastToggledMillis = nowMillis;
        lastToggledOrigLock = displaySettings.orientationLock;
        displaySettings.orientationLock = targetLock;

        updateForceOrientation()
    }


    ConfigurationValue {
        id: forceOrientation
        key: "/desktop/sailfish/silica/force_orientation"
        defaultValue: false
    }

    function updateForceOrientation(){
      forceOrientation.value = checked;
    }

    menu: ContextMenu {
        MenuItem {
            text: qsTrId("settings_system-orientation_portrait")
            onClicked: {
              displaySettings.orientationLock = "portrait"
              updateForceOrientation()
            }
        }
        MenuItem {
            text: qsTrId("settings_system-orientation_landscape")
            onClicked: {
              displaySettings.orientationLock = "landscape"
              updateForceOrientation()
            }
        }
        MenuItem {
            text: "Inverted " + qsTrId("settings_system-orientation_portrait")
            onClicked: {
              displaySettings.orientationLock = "portrait-inverted"
              updateForceOrientation()
            }
        }
        MenuItem {
            text: "Inverted " + qsTrId("settings_system-orientation_landscape")
            onClicked: {
              displaySettings.orientationLock = "landscape-inverted"
              updateForceOrientation()
            }
        }
        MenuItem {
            text: "Dynamic"
            onClicked: {
              displaySettings.orientationLock = "dynamic"
              updateForceOrientation()
            }
        }
    }

    DisplaySettings { id: displaySettings }
}
