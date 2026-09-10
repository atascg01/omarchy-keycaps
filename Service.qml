import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "KeyModel.js" as KeyModel
import "ShortcutState.js" as ShortcutState
import "Settings.js" as Settings

Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "omarchy-keycaps"
  readonly property var shortcutState: ShortcutState.create(KeyModel)
  property var heldModel: []
  property var settings: Settings.normalize(null)
  readonly property int hideAfter: settings.hideAfter
  readonly property real keycapScale: settings.keycapScale
  readonly property int bottomOffset: settings.bottomOffset

  // The host does not inject settings into service entry points. Read its
  // existing config without rewriting it or maintaining a second settings file.
  FileView {
    id: configFile
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadSettings()
  }

  onPluginIdChanged: if (configFile.loaded) loadSettings()

  function loadSettings() {
    try {
      settings = Settings.fromConfig(JSON.parse(configFile.text()), pluginId)
    } catch (e) {
      // Editors may briefly leave a partial document. Keep the last valid values.
      console.warn("Keycaps: could not read shell.json settings: " + e)
    }
  }

  function showPanel() {
    if (shell && typeof shell.summon === "function") shell.summon(pluginId, "")
  }

  function hidePanel() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  function present(action) {
    if (action === "invalid" || action === "stale") return action
    heldModel = shortcutState.model
    if (action === "show") {
      hideTimer.stop()
      cleanupTimer.stop()
      showPanel()
    } else if (action === "linger") {
      hideTimer.restart()
    } else if (action === "hide") {
      hideTimer.stop()
      cleanupTimer.stop()
      hidePanel()
    }
    return "ok"
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var prefix = "omarchy-keycaps,"
      if (event.name !== "custom" || event.data.indexOf(prefix) !== 0) return
      try {
        root.present(root.shortcutState.stream(JSON.parse(event.data.slice(prefix.length))))
      } catch (e) {
        console.warn("Keycaps: invalid bridge snapshot: " + e)
      }
    }
  }

  Timer {
    id: hideTimer
    interval: root.hideAfter
    repeat: false
    onTriggered: {
      root.hidePanel()
      cleanupTimer.restart()
    }
  }

  Timer {
    id: cleanupTimer
    interval: 250 // Keep delegates alive through the panel's 180 ms exit animation.
    repeat: false
    onTriggered: {
      root.shortcutState.cleanup()
      root.heldModel = root.shortcutState.model
    }
  }

  // Diagnostic IPC remains available; the live bridge uses ordered socket2
  // snapshots instead of spawning a separate IPC process for each key event.
  IpcHandler {
    target: root.pluginId

    function keyEvent(code: string, pressed: string): string {
      var key = String(code || "").trim().toUpperCase()
      if (/^[0-9]+$/.test(key)) key = Number(key)
      if (pressed !== "1" && pressed !== "0" && pressed !== "true" && pressed !== "false") return "invalid"
      return root.present(root.shortcutState.event(key, pressed === "1" || pressed === "true"))
    }

    function snapshot(codes: string): string {
      try {
        return root.present(root.shortcutState.snapshot(JSON.parse(codes)))
      } catch (e) { return "invalid" }
    }

    function clear(): string { return root.present(root.shortcutState.clear()) }
    function ping(): string { return "ok" }
    function getSettings(): string { return JSON.stringify(root.settings) }
  }
}
