const test = require('node:test')
const assert = require('node:assert/strict')
const KeyModel = require('../KeyModel.js')
const { create } = require('../ShortcutState.js')
const state = () => create(KeyModel)
const caps = s => s.model.map(({ label, held }) => [label, held])
const packet = (sequence, keys, extra = {}) => ({ version: 1, session: 'session-a', sequence, keys, ...extra })

test('ordinary typing and Shift alone stay hidden; Shift-first shortcuts retain Shift', () => {
  const s = state()
  assert.equal(s.event(50, true), 'none')
  assert.deepEqual(s.model, [])
  assert.equal(s.event(133, true), 'show')
  s.event(65, true)
  assert.deepEqual(caps(s), [['SUPER', true], ['SHIFT', true], ['SPACE', true]])
})

test('ordinary typing before a modifier is not carried into the next combo', () => {
  const s = state()
  s.event(38, true)
  s.event('CTRL', true)
  assert.deepEqual(caps(s), [['CTRL', true]])
})

test('both sides of every modifier produce one cap until both are released', () => {
  for (const [left, right, label] of [[37, 105, 'CTRL'], [133, 134, 'SUPER'], [64, 108, 'ALT'], [50, 62, 'SHIFT']]) {
    const s = state()
    if (label === 'SHIFT') s.event(37, true)
    s.event(left, true)
    s.event(right, true)
    s.event(left, false)
    assert.deepEqual(s.model.filter(c => c.label === label).map(c => c.held), [true])
    s.event(right, false)
    assert.deepEqual(s.model.filter(c => c.label === label).map(c => c.held), [false])
  }
})

test('Super+1 to Super+2 replaces the released key and preserves held chords', () => {
  const s = state()
  s.snapshot(['SUPER', 10])
  s.snapshot(['SUPER'])
  assert.deepEqual(caps(s), [['SUPER', true], ['1', false]])
  s.snapshot(['SUPER', 11])
  assert.deepEqual(caps(s), [['SUPER', true], ['2', true]])
  s.snapshot(['SUPER', 11, 10])
  assert.deepEqual(caps(s), [['SUPER', true], ['2', true], ['1', true]])
})

test('last modifier release releases every cap immediately, before dismissal', () => {
  const s = state()
  s.snapshot(['CTRL', 'SHIFT', 9])
  assert.equal(s.snapshot(['SHIFT', 9]), 'linger')
  assert.deepEqual(caps(s), [['CTRL', false], ['SHIFT', false], ['ESC', false]])
  assert.equal(s.snapshot([]), 'none')
  s.cleanup()
  assert.deepEqual(s.model, [])
})

test('empty snapshot rebuilds released caps; heartbeats do not postpone dismissal', () => {
  const s = state()
  s.stream(packet(1, ['SUPER', 65]))
  assert.equal(s.stream(packet(2, [])), 'linger')
  assert.deepEqual(caps(s), [['SUPER', false], ['SPACE', false]])
  for (let seq = 3; seq < 10; seq++) assert.equal(s.stream(packet(seq, [])), 'none')
  s.cleanup()
  assert.deepEqual(s.model, [])
})

test('a fresh shortcut cancels lingering state, including before exit cleanup', () => {
  const s = state()
  s.snapshot(['SUPER', 65])
  s.snapshot([])
  s.snapshot(['CTRL', 9])
  s.cleanup()
  assert.deepEqual(caps(s), [['CTRL', true], ['ESC', true]])
})

test('duplicate and out-of-order snapshots cannot resurrect released keys', () => {
  const s = state()
  s.stream(packet(1, ['SUPER', 65]))
  s.stream(packet(3, []))
  assert.equal(s.stream(packet(2, ['SUPER', 65])), 'stale')
  assert.equal(s.stream(packet(3, ['SUPER'])), 'stale')
  assert.deepEqual(caps(s), [['SUPER', false], ['SPACE', false]])
})

test('a later snapshot recovers a skipped press and a service starting mid-combo', () => {
  const s = state()
  assert.equal(s.stream(packet(20, ['CTRL', 'SHIFT', 9])), 'show')
  assert.deepEqual(caps(s), [['CTRL', true], ['SHIFT', true], ['ESC', true]])
})

test('reload clears old state and accepts a new session with restarted sequence', () => {
  const s = state()
  s.stream(packet(10, ['SUPER', 65]))
  assert.equal(s.stream(packet(1, [], { session: 'session-b', reset: true })), 'hide')
  assert.deepEqual(s.model, [])
  assert.equal(s.stream(packet(11, ['SUPER'])), 'stale')
  s.stream(packet(2, ['CTRL'], { session: 'session-b' }))
  assert.deepEqual(caps(s), [['CTRL', true]])
})

test('reload within the same session clears state and preserves the watermark', () => {
  const s = state()
  s.stream(packet(10, ['SUPER']))
  assert.equal(s.stream(packet(11, [], { reset: true })), 'hide')
  assert.equal(s.stream(packet(10, ['SUPER'])), 'stale')
  assert.deepEqual(s.model, [])
})

test('malformed snapshots and events leave the current combo intact', () => {
  const s = state()
  s.snapshot(['CTRL', 9])
  const before = caps(s)
  for (const keys of [null, {}, 'CTRL', [null], ['__proto__'], [NaN], [1.5], [768]]) {
    assert.equal(s.snapshot(keys), 'invalid')
    assert.equal(s.stream(packet(2, keys)), 'invalid')
    assert.deepEqual(caps(s), before)
  }
  for (const change of [{ version: 2 }, { sequence: -1 }, { sequence: Infinity }, { session: '' }, { reset: 'true' }]) {
    assert.equal(s.stream(packet(2, [], change)), 'invalid')
  }
  assert.equal(s.event('__proto__', true), 'invalid')
  assert.equal(s.event(9, 'false'), 'invalid')
  assert.deepEqual(caps(s), before)
})

test('repeated diagnostic presses do not change key order', () => {
  const s = state()
  s.event('SUPER', true)
  s.event(11, true)
  s.event(10, true)
  assert.equal(s.event(11, true), 'none')
  assert.deepEqual(caps(s), [['SUPER', true], ['2', true], ['1', true]])
})
