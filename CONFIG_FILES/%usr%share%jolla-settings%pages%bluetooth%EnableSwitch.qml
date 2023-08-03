import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Lipstick 1.0
import Sailfish.Bluetooth 1.0
import MeeGo.Connman 0.2
import Nemo.DBus 2.0
import com.jolla.settings 1.0
import Sailfish.Policy 1.0
import org.kde.bluezqt 1.0 as BluezQt

SettingsToggle {
    id: pwrSwitch

    property QtObject adapter: _bluetoothManager.usableAdapter
    readonly property QtObject _bluetoothManager: BluezQt.Manager

    //% "Bluetooth"
    name: qsTrId("settings_bluetooth-la-bluetooth")
    activeText: {
        if (!active) {
            return name
        } else {
            var deviceNames = bluetoothStatus.connectedDeviceNames
            switch (deviceNames.length) {
            case 0:
                return ""
            case 1:
                return deviceNames[0]
            default:
                //: Number of connected Bluetooth devices
                //% "%n connections"
                return qsTrId("settings_bluetooth-la-connection_count", deviceNames.length)
            }
        }
    }

    available: AccessPolicy.bluetoothToggleEnabled
    active: bluetoothStatus.connected
    icon.source: "image://theme/icon-m-bluetooth"
    checked: btTechModel.powered && bluetoothStatus.powered

    menu: ContextMenu {
        SettingsMenuItem {
            onClicked: pwrSwitch.goToSettings()
        }

        MenuItem {
            //% "Search for devices"
            text: qsTrId("settings_bluetooth-me-search-for-devices")
            enabled: AccessPolicy.bluetoothToggleEnabled || pwrSwitch.checked
            onClicked: settingsApp.call("findBluetoothDevices")
        }

        BluetoothDeviceColumnView {
            id: pairedDevices
            filters: BluezQt.DevicesModelPrivate.PairedDevices
            excludedDevices: []
            highlightSelectedDevice: false
            openMenuOnPressAndHold: false

            onDeviceItemClicked: {
              if (!adapter || !adapter.powered || address === "") {
                  return
              }
              var deviceObj = _bluetoothManager.deviceForAddress(address)
              if (!deviceObj) {
                  return
              }
              if (deviceObj.connected) {
                  deviceObj.disconnectFromDevice()
              } else {
                  addConnectingDevice(address);
                  var call = deviceObj.connectToDevice()
                  call.finished.connect(function(call) {
                    removeConnectingDevice(address);
                  })
              }
            }
        }
    }

    BluetoothStatus {
        id: bluetoothStatus
    }

    DBusInterface {
        id: settingsApp

        service: "com.jolla.settings"
        path: "/com/jolla/settings/ui"
        iface: "com.jolla.settings.ui"
    }

    TechnologyModel {
        id: btTechModel
        name: "bluetooth"

        onPoweredChanged: {
            busy = false
        }
    }

    onCheckedChanged: {
        busy = false
    }

    onToggled: {
        if (!AccessPolicy.bluetoothToggleEnabled) {
            errorNotification.notify(SettingsControlError.BlockedByAccessPolicy)
            return
        }
        btTechModel.powered = !btTechModel.powered
        busy = true
    }

}
