const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function element() {
  const classes = new Set();
  const node = {
    style: {}, dataset: {}, children: [], listeners: {}, textContent: '',
    classList: {toggle(name, enabled) { if (enabled) classes.add(name); else classes.delete(name); }, contains(name) { return classes.has(name); }},
    appendChild(child) { this.children.push(child); },
    setAttribute() {}, addEventListener(name, action) { this.listeners[name] = action; },
    getBoundingClientRect() { return {top: 0, bottom: 20, height: 500}; },
    scrollIntoView() {},
  };
  Object.defineProperty(node, 'innerHTML', {set() { this.children = []; }});
  return node;
}
const nodes = Object.fromEntries(['waiting', 'main', 'done', 'text-container', 'prompter', 'waveform', 'spoken', 'mic-dot', 'mirror-btn', 'conn-status'].map(id => [id, element()]));
const body = element(), storage = new Map();
const context = vm.createContext({
  document: {body, getElementById: id => nodes[id], createElement: element},
  location: {hostname: 'localhost', search: ''}, URLSearchParams,
  localStorage: {getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value)},
  WebSocket: class {}, setTimeout, clearTimeout, console,
});
const html = fs.readFileSync(process.argv[2], 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
vm.runInContext(script, context);
function render(state) { context.state = state; vm.runInContext('render(state)', context); }
const state = {
  words: ['Red', 'blue', 'Black', '[pause]'],
  wordColors: ['#ff453a', '#4f8cff', '#000000', '#ff453a'],
  highlightedCharCount: 0, totalCharCount: 23, isActive: true, isDone: false,
  fontColor: '#ffffff', cueColor: '#ffd60a', highlightWords: true,
};
const spans = () => nodes['text-container'].children;
render(state);
assert.equal(spans()[0].style.color, 'rgba(255,69,58,0.6)');
assert.equal(spans()[1].style.color, '#4f8cff');
assert.equal(spans()[2].style.color, '#ffffff');
assert.equal(spans()[3].style.color, 'rgba(255,214,10,0.2)', 'Cues retain their own color');
render({...state, highlightedCharCount: 4});
assert.equal(spans()[0].style.color, 'rgba(255,69,58,0.3)');
assert.equal(spans()[1].style.color, 'rgba(79,140,255,0.6)');
render({...state, highlightWords: false});
assert.equal(spans()[0].style.color, '#ff453a');
assert.equal(spans()[1].style.color, '#4f8cff');
assert.equal(spans()[3].style.color, 'rgba(255,214,10,0.4)');
const firstSpan = spans()[0];
render({...state, highlightWords: false, wordColors: ['#33d64a']});
assert.equal(spans()[0], firstSpan, 'Color-only changes preserve the reading DOM');
assert.equal(spans()[0].style.color, '#33d64a');
assert.equal(spans()[1].style.color, '#ffffff', 'Missing colors use the legacy fallback');
render({...state, highlightWords: false, wordColors: undefined});
assert.equal(spans()[0].style.color, '#ffffff', 'Legacy states remain readable');
render({...state, words: ['Red', 'edit', 'Black', '[pause]']});
assert.equal(spans()[1].textContent, 'edit ', 'Middle-word changes rebuild the spans');
nodes['mirror-btn'].listeners.click();
assert.equal(body.classList.contains('mirrored'), true);
assert.equal(storage.get('textream.remote.mirror'), '1');
render({...state, isActive: false});
assert.equal(nodes.waiting.style.display, 'flex');
render({...state, isDone: true});
assert.equal(nodes.done.style.display, 'flex');
console.log('PASS: generated Remote reader HTML, per-word colors, dimming, cues, default black, live color/text updates, legacy states, mirror, inactive/done');
