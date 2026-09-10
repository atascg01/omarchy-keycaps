// UI-independent shortcut state, shared by the QML service and regression tests.
function validKey(key) {
  if (typeof key === "number") return isFinite(key) && key % 1 === 0 && key > 0 && key < 768
  return typeof key === "string" && /^(SUPER|CTRL|ALT|SHIFT)$/.test(key)
}

function validKeys(keys) {
  return Array.isArray(keys) && keys.length <= 256 && keys.every(validKey)
}

function create(keyModel) {
  return {
    rawKeys: [],
    active: ({}),
    displayed: ({}),
    counter: 0,
    model: [],
    session: "",
    sequence: -1,
    retiredSessions: Object.create(null),

    hasShortcut: function(keys) {
      return !!(keys.SUPER || keys.CTRL || keys.ALT)
    },

    rebuild: function() {
      var self = this
      this.model = Object.keys(this.displayed).map(function(key) {
        return {
          code: key,
          ord: self.displayed[key],
          label: keyModel.labelFor(key),
          wide: keyModel.isWide(key),
          held: !!self.active[key]
        }
      }).sort(function(a, b) { return keyModel.compare(a.code, a.ord, b.code, b.ord) })
    },

    snapshot: function(keys) {
      if (!validKeys(keys)) return "invalid"
      this.rawKeys = keys.slice()
      var next = ({})
      var ordered = []
      for (var i = 0; i < keys.length; i++) {
        // Keep physical identities in rawKeys, but show one cap per modifier.
        var key = keyModel.isModifier(keys[i]) ? keyModel.labelFor(keys[i]) : String(keys[i])
        if (!next[key]) ordered.push(key)
        next[key] = true
      }
      var wasShortcut = this.hasShortcut(this.active)
      if (!this.hasShortcut(next)) {
        // A combo ends with its final shortcut modifier, even if Shift or a
        // regular key remains physically down. Ordinary typing cannot extend it.
        this.active = ({})
        this.rawKeys = this.rawKeys.filter(function(key) { return keyModel.isModifier(key) })
        this.rebuild()
        return wasShortcut ? "linger" : "none"
      }

      if (!wasShortcut) this.displayed = ({})
      var newRegular = ordered.some(function(key) {
        return !keyModel.isModifier(key) && !this.active[key]
      }, this)
      if (newRegular) {
        for (var old in this.displayed) {
          if (!keyModel.isModifier(old) && !next[old]) delete this.displayed[old]
        }
      }
      for (var j = 0; j < ordered.length; j++) {
        var current = ordered[j]
        if (this.displayed[current] === undefined) this.displayed[current] = ++this.counter
      }
      this.active = next
      this.rebuild()
      return "show"
    },

    event: function(key, pressed) {
      if (!validKey(key) || typeof pressed !== "boolean") return "invalid"
      var keys = this.rawKeys.filter(function(k) { return k !== key })
      if (pressed) {
        // Repeats must not reorder keys or restart a combination.
        if (this.rawKeys.indexOf(key) !== -1) return "none"
        keys.push(key)
      }
      return this.snapshot(keys)
    },

    stream: function(message) {
      if (!message || message.version !== 1
          || typeof message.session !== "string" || !/^[a-zA-Z0-9:-]{1,80}$/.test(message.session)
          || typeof message.sequence !== "number" || !isFinite(message.sequence)
          || message.sequence < 0 || message.sequence > 9007199254740991 || message.sequence % 1 !== 0
          || (message.reset !== undefined && typeof message.reset !== "boolean")
          || !validKeys(message.keys)) return "invalid"
      if (this.retiredSessions[message.session]) return "stale"
      var changedSession = message.session !== this.session
      if (!changedSession && message.sequence <= this.sequence) return "stale"
      if (changedSession) {
        if (this.session) this.retiredSessions[this.session] = true
        this.session = message.session
      }
      this.sequence = message.sequence
      // Socket2 delivers sessions in order. A new bridge session (Lua reload)
      // clears the previous combo; subsequent heartbeats can restore held keys.
      if (changedSession || message.reset) this.clear()
      var action = this.snapshot(message.keys)
      return (changedSession || message.reset) && action === "none" ? "hide" : action
    },

    clear: function() {
      this.rawKeys = []
      this.active = ({})
      this.displayed = ({})
      this.counter = 0
      this.rebuild()
      // Keep the stream watermark so late packets cannot resurrect cleared keys.
      return "hide"
    },

    cleanup: function() {
      if (!this.hasShortcut(this.active)) {
        this.displayed = ({})
        this.counter = 0
        this.rebuild()
      }
    }
  }
}

if (typeof module !== "undefined") module.exports = { create: create, validKey: validKey, validKeys: validKeys }
