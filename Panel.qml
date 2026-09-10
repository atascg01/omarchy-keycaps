import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

// Keycaps panel: a bottom-centered row of Omarchy-styled keycaps. Rendered
// from the keys service's heldModel.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  readonly property var targetScreen: {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "") === name) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function open(payloadJson) { opened = true }
  function close() { opened = false }

  readonly property var keys: service ? service.heldModel : []
  readonly property bool active: opened && keys.length > 0

  readonly property real keycapScale: service ? service.keycapScale : 1
  readonly property int bottomOffset: service ? service.bottomOffset : 64
  readonly property int capMinWidth: Style.space(38 * keycapScale)
  readonly property int capPaddingX: Style.space(12 * keycapScale)
  readonly property int capHeight: Style.space(42 * keycapScale)
  readonly property int capLip: Math.max(1, Style.space(3 * keycapScale))
  readonly property int gap: Style.space(8 * keycapScale)

  PanelWindow {
    id: panel
    screen: root.targetScreen
    visible: root.active || capsContainer.opacity > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-keycaps"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    Item {
      id: capsContainer
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(root.bottomOffset)
      width: capsRow.width
      height: capsRow.height

      opacity: root.active ? 1.0 : 0.0
      scale: root.active ? 1.0 : 0.95
      transform: Translate {
        y: root.active ? 0 : Style.space(8)
        Behavior on y {
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
      }

      Behavior on opacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
      }
      Behavior on scale {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
      }

      Row {
        id: capsRow
        spacing: root.gap

        Repeater {
          model: root.keys

          delegate: Item {
            id: keycapDelegate
            required property var modelData

            readonly property bool isHeld: modelData.held === true
            readonly property int baseWidth: Math.max(
              modelData.wide ? Style.space(52 * root.keycapScale) : root.capMinWidth,
              labelText.implicitWidth + root.capPaddingX * 2
            )

            width: baseWidth
            height: root.capHeight
            scale: isHeld ? 0.97 : 1.0

            Behavior on scale {
              NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
            }

            // Keycap 3D base / shadow bottom bevel (only visible at the bottom when unpressed)
            Rectangle {
              id: keycapBase
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: parent.height - root.capLip
              radius: Style.cornerRadius * root.keycapScale
              color: Qt.darker(Color.popups.background, 1.3)
              border.width: 1
              border.color: Util.alpha(Color.popups.border, 0.4)
            }

            // Keycap top face that depresses when pressed
            Rectangle {
              id: keycapTop
              x: 0
              y: keycapDelegate.isHeld ? root.capLip : 0
              width: parent.width
              height: parent.height - root.capLip
              radius: Style.cornerRadius * root.keycapScale

              // Solid opaque popup background tinted with theme accent when pressed
              color: keycapDelegate.isHeld
                ? Qt.tint(Color.popups.background, Util.alpha(Color.accent, 0.22))
                : Color.popups.background

              border.width: keycapDelegate.isHeld ? Math.max(1.5, Style.space(1.5)) : 1
              border.color: keycapDelegate.isHeld
                ? Color.accent
                : Util.alpha(Color.popups.border, 0.65)

              Behavior on y {
                NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
              }
              Behavior on color {
                ColorAnimation { duration: 80 }
              }
              Behavior on border.color {
                ColorAnimation { duration: 80 }
              }

              // Subtle top edge highlight
              Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                height: 1
                radius: parent.radius
                color: Util.alpha(Color.foreground, keycapDelegate.isHeld ? 0.25 : 0.12)
              }

              Text {
                id: labelText
                anchors.centerIn: parent
                text: modelData.label
                textFormat: Text.PlainText
                color: Color.popups.text
                font.family: Style.font.family
                font.bold: true
                font.pixelSize: Math.max(1, Math.round(Style.font.body * root.keycapScale))
              }
            }
          }
        }
      }
    }
  }
}
