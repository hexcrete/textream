const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function text(value) { return {nodeType: 3, nodeValue: value}; }
function element(tag = 'SPAN', children = [], color = '') {
  const classes = new Set();
  const node = {
    nodeType: 1, tagName: tag, childNodes: children, style: {color}, dataset: {}, listeners: {},
    classList: {toggle(name, enabled) { if (enabled) classes.add(name); else classes.delete(name); }, contains(name) { return classes.has(name); }}, getAttribute() { return null; }, setAttribute() {},
    addEventListener(type, action) { this.listeners[type] = action; },
    appendChild(child) { this.childNodes.push(child); },
    replaceChildren(fragment) { this.childNodes = fragment?.childNodes || []; },
    contains() { return false; }, focus() {},
  };
  Object.defineProperty(node, 'textContent', {
    get() { return this.childNodes.map(child => child.nodeValue || child.textContent).join(''); },
    set(value) { this.childNodes = [text(value)]; }
  });
  return node;
}
const nodes = {'edit-text': element('DIV'), 'read-text': element('DIV'), 'read-divider': element('DIV'), 'color-palette': element('DIV')};
const context = vm.createContext({
  Node: {TEXT_NODE: 3, ELEMENT_NODE: 1, DOCUMENT_FRAGMENT_NODE: 11},
  document: {
    getElementById: id => nodes[id], querySelectorAll: () => [], addEventListener() {},
    createDocumentFragment: () => ({nodeType: 11, childNodes: [], appendChild(child) { this.childNodes.push(child); }}),
    createElement: tag => element(tag.toUpperCase()), execCommand() {},
  },
  window: {getSelection: () => ({rangeCount: 0})},
  getComputedStyle: node => ({color: node.style.color || ''}),
  isRunning: false, lastReadCount: 0, lockedReadText: '', editDebounce: null,
  setTimeout, clearTimeout, send() {},
});
const source = fs.readFileSync(path.join(__dirname, '../../Textream/Textream/DirectorFormatting.js'), 'utf8');
vm.runInContext(source, context);
function run(code) { return JSON.parse(JSON.stringify(vm.runInContext(code, context))); }
assert.equal(run("normalizeColor('rgb(168, 87, 247)')"), '#a857f7');
assert.equal(run("normalizeColor('#FF453A')"), '#ff453a');
vm.runInContext("renderRuns(editor, [{text:'black',color:'#000000'},{text:'white',color:'#ffffff'},{text:'red',color:'#ff453a'}])", context);
assert.equal(nodes['edit-text'].childNodes[0].classList.contains('default-text-color'), true);
assert.equal(nodes['edit-text'].childNodes[1].classList.contains('default-text-color'), true);
assert.equal(nodes['edit-text'].childNodes[2].classList.contains('default-text-color'), false);
assert.deepEqual(run('extractRuns(editor)'), [{text:'black',color:'#000000'},{text:'white',color:'#ffffff'},{text:'red',color:'#ff453a'}]);
nodes['edit-text'].childNodes[0].style.color = '#4f8cff';
nodes['edit-text'].listeners.input();
assert.equal(nodes['edit-text'].childNodes[0].classList.contains('default-text-color'), false, 'Recoloring must remove the default-color override');
assert.equal(run(String.raw`plain(normalizeDirectorRuns([{text:'A\u0085B\u00a0C\uFEFFD',color:'#ffffff'}]))`), 'A B C\uFEFFD');
assert.deepEqual(run(String.raw`normalizeDirectorRuns([{text:'  red  \r\n\n',color:'#ff453a'},{text:'blue \t ',color:'#4f8cff'}])`), [
  {text: 'red\n', color: '#ff453a'}, {text: 'blue', color: '#4f8cff'}
]);
assert.deepEqual(run("splitRunsAt([{text:'Red ',color:'#ff453a'},{text:'你好 👨‍👩‍👧‍👦 é',color:'#4f8cff'}],5)"), [
  [{text: 'Red ', color: '#ff453a'}, {text: '你', color: '#4f8cff'}],
  [{text: '好 👨‍👩‍👧‍👦 é', color: '#4f8cff'}]
]);
nodes['edit-text'].childNodes = [element('P', [text('Red')], '#ff453a'), element('P', [text('Blue')], '#4f8cff')];
assert.equal(run('plain(normalizeDirectorRuns(extractRuns(editor)))'), 'Red\nBlue');
assert.deepEqual(run('normalizeDirectorRuns(extractRuns(editor))'), [
  {text: 'Red\n', color: '#ff453a'}, {text: 'Blue', color: '#4f8cff'}
]);
nodes['edit-text'].childNodes = [element('SPAN', [text('Red ')], '#ff453a'), element('SPAN', [text('blue ')], '#4f8cff')];
vm.runInContext('updateFormattedBoundary(4)', context);
assert.equal(nodes['read-text'].textContent, 'Red ');
assert.equal(nodes['edit-text'].textContent, 'blue ', 'Boundary movement must retain unfinished typing whitespace');
assert.deepEqual(run('fullRuns()'), [{text: 'Red ', color: '#ff453a'}, {text: 'blue', color: '#4f8cff'}]);
nodes['edit-text'].childNodes = [text('still typing  ')];
vm.runInContext('updateFormattedBoundary(4)', context);
assert.equal(nodes['edit-text'].textContent, 'still typing  ', 'Unchanged progress must not rewrite the editor');
vm.runInContext("syncPalette(['#ffffff'])", context);
assert.equal(nodes['color-palette'].hidden, true);
vm.runInContext("syncPalette(['#ffffff','#ff453a','#4f8cff'])", context);
assert.equal(nodes['color-palette'].hidden, false);
assert.equal(nodes['color-palette'].childNodes.length, 3);
vm.runInContext("syncPalette(Array(12).fill('#ffffff'))", context);
assert.equal(nodes['color-palette'].childNodes.length, 9);
console.log('PASS: Director color/whitespace normalization, paragraph extraction, Unicode splitting, locked/read colors, unfinished typing, palette limits');
