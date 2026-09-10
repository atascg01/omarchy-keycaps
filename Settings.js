// Settings are inline on this plugin's entry in ~/.config/omarchy/shell.json.
function bounded(value, fallback, min, max) {
  if (typeof value !== "number" || !isFinite(value)) return fallback
  return Math.max(min, Math.min(max, value))
}

function normalize(entry) {
  entry = entry || {}
  return {
    hideAfter: Math.round(bounded(entry.hideAfter, 1200, 0, 10000)),
    keycapScale: bounded(entry.keycapScale, 1, 0.5, 2),
    bottomOffset: Math.round(bounded(entry.bottomOffset, 64, 0, 1000))
  }
}

function fromConfig(config, pluginId) {
  if (config && config.version === 1 && Array.isArray(config.plugins)) {
    for (var i = 0; i < config.plugins.length; i++) {
      var entry = config.plugins[i]
      if (entry && entry.id === pluginId) return normalize(entry)
    }
  }
  return normalize(null)
}

if (typeof module !== "undefined") module.exports = { normalize: normalize, fromConfig: fromConfig }
