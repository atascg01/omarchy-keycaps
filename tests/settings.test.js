const test = require('node:test')
const assert = require('node:assert/strict')
const { normalize, fromConfig } = require('../Settings.js')

test('missing settings preserve the original appearance and timing', () => {
  assert.deepEqual(normalize(), { hideAfter: 1200, keycapScale: 1, bottomOffset: 64 })
  for (const config of [null, {}, { version: 2 }, { version: 1, plugins: [] }]) {
    assert.deepEqual(fromConfig(config, 'omarchy-keycaps'), normalize())
  }
})

test('reads only the matching plugin entry, supports zero delay and bottom offset', () => {
  const settings = { hideAfter: 0, keycapScale: 1.25, bottomOffset: 0 }
  const config = { version: 1, plugins: [null, { id: 'unrelated', hideAfter: 999 }, { id: 'omarchy-keycaps', ...settings }] }
  assert.deepEqual(fromConfig(config, 'omarchy-keycaps'), settings)
  assert.deepEqual(fromConfig(config, 'missing'), normalize())
})

test('clamps numeric values and rejects coercion of invalid types', () => {
  assert.deepEqual(normalize({ hideAfter: -100, keycapScale: 10, bottomOffset: 2000 }),
    { hideAfter: 0, keycapScale: 2, bottomOffset: 1000 })
  assert.deepEqual(normalize({ hideAfter: 10001, keycapScale: 0, bottomOffset: -1 }),
    { hideAfter: 10000, keycapScale: 0.5, bottomOffset: 0 })
  for (const value of [null, true, '2', NaN, Infinity, {}, []]) {
    assert.deepEqual(normalize({ hideAfter: value, keycapScale: value, bottomOffset: value }), normalize())
  }
})
