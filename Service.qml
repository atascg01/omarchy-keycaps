import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "KeyModel.js" as KeyModel

// Keycaps service. Receives key press/release events from the Hyprland Lua
// bridge over IPC, tracks the currently-held keys, and summons/hides the
// panel. Only displays for shortcut modifier combinations.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "omarchy-keycaps"

  // Ordered list of currently-displayed keys as { code, ord, label, wide }.
  // The panel binds to it.
  property var heldModel: []

  property var activeKeys: ({})   // key -> true (keys physically held right now)
  property var displayState: ({}) // key -> { ord, label, wide } (keys displayed on screen)
  property int counter: 0
  property int hideAfter: 1200    // ms of inactivity after release before the panel hides

  function activeCount() {
    return Object.keys(activeKeys).length
  }

  function activeShortcutModifierCount() {
    var count = 0
    for (var k in activeKeys) {
      var l = KeyModel.labelFor(k)
      if (l === "SUPER" || l === "CTRL" || l === "ALT") count++
    }
    return count
  }

  function hasShortcutModifier() {
    for (var k in displayState) {
      var l = KeyModel.labelFor(k)
      if (l === "SUPER" || l === "CTRL" || l === "ALT") return true
    }
    return false
  }

  function rebuild() {
    var arr = []
    for (var k in displayState) {
      arr.push({
        code: k,
        ord: displayState[k].ord,
        label: displayState[k].label,
        wide: displayState[k].wide,
        held: !!activeKeys[k]
      })
    }
    arr.sort(function (a, b) { return KeyModel.compare(a.code, a.ord, b.code, b.ord) })
    heldModel = arr
  }

  function applyEvent(key, pressed) {
    if (pressed) {
      // If all shortcut modifiers were released or hideTimer was running, start a fresh combo.
      if (hideTimer.running || activeShortcutModifierCount() === 0) {
        hideTimer.stop()
        cleanupTimer.stop()
        displayState = ({})
        activeKeys = ({})
      } else if (!KeyModel.isModifier(key)) {
        // If modifiers are held and a new non-modifier is pressed, remove any
        // non-modifier that is no longer physically held (e.g. Super+1 -> Super+2).
        for (var k in displayState) {
          if (!KeyModel.isModifier(k) && !activeKeys[k]) {
            delete displayState[k]
          }
        }
      }

      activeKeys[key] = true
      if (displayState[key] === undefined) {
        counter = counter + 1
        displayState[key] = { ord: counter, label: KeyModel.labelFor(key), wide: KeyModel.isWide(key) }
      }
      rebuild()

      // Only show the panel if a shortcut modifier (Super, Ctrl, Alt) is part of the combo
      if (hasShortcutModifier()) {
        showPanel()
        hideTimer.stop()
        cleanupTimer.stop()
      }
    } else {
      if (activeKeys[key] !== undefined) delete activeKeys[key]
      rebuild()

      if (activeShortcutModifierCount() === 0) {
        // All shortcut modifiers released: keep them visible for hideAfter ms before dismissing
        if (heldModel.length > 0 && hasShortcutModifier()) {
          hideTimer.restart()
        } else {
          hideTimer.stop()
          cleanupTimer.stop()
          activeKeys = ({})
          displayState = ({})
          rebuild()
          hidePanel()
        }
      }
    }
  }

  function showPanel() {
    if (shell && typeof shell.summon === "function") shell.summon(pluginId, "")
  }

  function hidePanel() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  Timer {
    id: hideTimer
    interval: root.hideAfter
    repeat: false
    onTriggered: {
      activeKeys = ({})
      root.hidePanel()
      cleanupTimer.restart()
    }
  }

  Timer {
    id: cleanupTimer
    interval: 250
    repeat: false
    onTriggered: {
      if (!hideTimer.running && activeCount() === 0) {
        displayState = ({})
        rebuild()
      }
    }
  }

  // The bridge batches a full state snapshot occasionally (on release), which
  // keeps the display accurate even if a key-up event races a reload.
  function applySnapshot(codes) {
    var list = Array.isArray(codes) ? codes : []
    var newActive = ({})
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (c !== undefined && c !== null && c !== "") newActive[c] = true
    }
    activeKeys = newActive
    if (Object.keys(activeKeys).length === 0) {
      hideTimer.restart()
    } else {
      hideTimer.stop()
      for (var k in activeKeys) {
        if (displayState[k] === undefined) {
          counter = counter + 1
          displayState[k] = { ord: counter, label: KeyModel.labelFor(k), wide: KeyModel.isWide(k) }
        }
      }
      rebuild()
      if (hasShortcutModifier()) showPanel()
    }
  }

  IpcHandler {
    target: root.pluginId

    function keyEvent(code: string, pressed: string): string {
      var trimmed = String(code || "").trim()
      if (trimmed === "") return "invalid"
      var num = parseInt(trimmed, 10)
      var key = isFinite(num) && String(num) === trimmed ? num : trimmed
      root.applyEvent(key, pressed === "1" || pressed === "true")
      return "ok"
    }

    function snapshot(codes: string): string {
      try {
        var arr = JSON.parse(codes || "[]")
        root.applySnapshot(arr)
        return "ok"
      } catch (e) { return "invalid" }
    }

    function clear(): string {
      activeKeys = ({})
      displayState = ({})
      rebuild()
      hideTimer.stop()
      cleanupTimer.stop()
      hidePanel()
      return "ok"
    }

    function ping(): string { return "ok" }
  }
}
