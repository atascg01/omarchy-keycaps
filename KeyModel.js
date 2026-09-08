// Keycode -> label / ordering / width for the keycap panel.
// Uses XKB keycodes (evdev + 8) as reported by Wayland/Hyprland,
// plus string names for semantic modifiers ("SUPER", "CTRL", "ALT", "SHIFT").

var MODIFIER_ORDER = { SUPER: 0, CTRL: 1, SHIFT: 2, ALT: 3 }

var XKB_LABEL = {
  9: "ESC",
  10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8", 18: "9", 19: "0",
  20: "-", 21: "=", 22: "BKSP",
  23: "TAB",
  24: "Q", 25: "W", 26: "E", 27: "R", 28: "T", 29: "Y", 30: "U", 31: "I", 32: "O", 33: "P",
  34: "[", 35: "]", 36: "ENTER",
  37: "CTRL",
  38: "A", 39: "S", 40: "D", 41: "F", 42: "G", 43: "H", 44: "J", 45: "K", 46: "L",
  47: ";", 48: "'", 49: "`",
  50: "SHIFT",
  51: "\\",
  52: "Z", 53: "X", 54: "C", 55: "V", 56: "B", 57: "N", 58: "M",
  59: ",", 60: ".", 61: "/",
  62: "SHIFT",
  63: "*",
  64: "ALT",
  65: "SPACE",
  66: "CAPS",
  67: "F1", 68: "F2", 69: "F3", 70: "F4", 71: "F5", 72: "F6",
  73: "F7", 74: "F8", 75: "F9", 76: "F10", 95: "F11", 96: "F12",
  77: "NUM", 78: "SCROLL",
  79: "KP7", 80: "KP8", 81: "KP9", 82: "KP-",
  83: "KP4", 84: "KP5", 85: "KP6", 86: "KP+",
  87: "KP1", 88: "KP2", 89: "KP3",
  90: "KP0", 91: "KP.",
  94: "<",
  104: "KPENTER",
  105: "CTRL",
  106: "KP/",
  107: "PSCR",
  108: "ALT",
  110: "HOME",
  111: "UP",
  112: "PGUP",
  113: "LEFT",
  114: "RIGHT",
  115: "END",
  116: "DOWN",
  117: "PGDN",
  118: "INS",
  119: "DEL",
  127: "PAUSE",
  133: "SUPER",
  134: "SUPER",
  135: "MENU"
}

var WIDE = {
  CTRL: true, SHIFT: true, ALT: true, SUPER: true, BKSP: true,
  ENTER: true, TAB: true, CAPS: true, SPACE: true, MENU: true,
  PSCR: true, SCROLL: true, PAUSE: true, INS: true, HOME: true,
  PGUP: true, DEL: true, END: true, PGDN: true, RIGHT: true,
  LEFT: true, DOWN: true, NUM: true, KPENTER: true
}

function labelFor(key) {
  if (typeof key === "string") {
    var u = key.toUpperCase()
    if (MODIFIER_ORDER[u] !== undefined) return u
  }
  var code = Number(key)
  if (XKB_LABEL[code] !== undefined) return XKB_LABEL[code]
  if (typeof key === "string" && key.length > 0) return key
  return "?"
}

function isWide(key) {
  var l = labelFor(key)
  return WIDE[l] === true
}

function isModifier(key) {
  var l = labelFor(key)
  return MODIFIER_ORDER[l] !== undefined
}

function modifierOrder(key) {
  var l = labelFor(key)
  return MODIFIER_ORDER[l] !== undefined ? MODIFIER_ORDER[l] : 99
}

function compare(keyA, ordA, keyB, ordB) {
  var modA = isModifier(keyA)
  var modB = isModifier(keyB)
  if (modA && modB) {
    var oa = modifierOrder(keyA)
    var ob = modifierOrder(keyB)
    if (oa !== ob) return oa - ob
    return ordA - ordB
  }
  if (modA && !modB) return -1
  if (!modA && modB) return 1
  return ordA - ordB
}

if (typeof module !== "undefined") {
  module.exports = {
    labelFor: labelFor,
    isWide: isWide,
    isModifier: isModifier,
    compare: compare
  }
}
