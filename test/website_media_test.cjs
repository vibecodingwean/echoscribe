'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

class Element {
  constructor(tag = 'div', dataset = {}) {
    this.tagName = tag;
    this.dataset = dataset;
    this.children = [];
    this.listeners = {};
    this.attributes = {};
    this.paused = true;
    this.currentTime = 0;
  }
  append(...nodes) { this.children.push(...nodes); }
  replaceChildren(...nodes) { this.children = nodes; }
  addEventListener(name, listener) { (this.listeners[name] ||= []).push(listener); }
  emit(name, event = {}) { for (const listener of this.listeners[name] || []) listener(event); }
  hasAttribute(name) { return Object.hasOwn(this.attributes, name); }
  setAttribute(name, value) { this.attributes[name] = value; }
  removeAttribute(name) { delete this.attributes[name]; delete this[name]; }
  contains(target) { return this.children.some(child => child === target || child.contains?.(target)); }
  querySelector(selector) { return selector === '.close' ? this.closeButton : this.image; }
  querySelectorAll(selector) { return selector === 'video' ? this.children.flatMap(child => child.tagName === 'video' ? [child] : child.querySelectorAll(selector)) : []; }
  focus() { this.focused = true; }
  showModal() { this.open = true; }
  close() { this.open = false; this.emit('close'); }
  play() { this.paused = false; return Promise.resolve(); }
  pause() { this.paused = true; }
  load() { this.loaded = true; }
}
const dialog = new Element();
dialog.closeButton = new Element('button');
const content = new Element();
const caption = new Element();
const title = new Element();
const native = new Element('a', {title: 'iPhone sharing', videoSrc: '/tutorial.mp4', captions: '/tutorial.vtt', start: '82.733333', end: '128.833333'});
native.href = '/tutorial.mp4#t=82.733333,128.833333';
native.attributes['data-video-src'] = '';
const archive = new Element('a', {title: 'Realtime', videoSrc: '/original-realtime.mp4', captions: '/original-realtime.vtt', start: '0', end: '23.7'});
archive.attributes['data-video-src'] = '';
archive.href = '/original-realtime.mp4#t=0,23.7';
const chapterLink = new Element('a');
chapterLink.hash = '#recording';
const section = {id: 'recording', getBoundingClientRect: () => ({top: 0})};
const image = new Element('a', {title: 'Screenshot'});
image.href = '/image.webp';
image.image = {alt: 'Actual app'};
const document = {
  body: {style: {}},
  querySelector: selector => ({'#media-dialog': dialog, '#media-content': content, '#media-title': title, '#media-caption': caption})[selector],
  querySelectorAll: selector => selector.includes('data-video-src') ? [native, archive, image] : selector === 'nav[aria-label="Feature guides"] a' ? [chapterLink] : selector === '.feature' ? [section] : [],
  createElement: tag => new Element(tag),
  createTextNode: text => ({textContent: text})
};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../website/site.js'), 'utf8'), {document, URL, innerHeight: 800, addEventListener() {}, requestAnimationFrame(fn) {fn();}});
function click(link) { link.emit('click', {button: 0, preventDefault() {}}); }
click(native);
const video = content.querySelectorAll('video')[0];
assert.ok(video, 'Native tutorial link must open a video');
assert.equal(video.src, '/tutorial.mp4#t=82.733333');
assert.equal(video.controls, true);
assert.equal(video.playsInline, true);
assert.equal(video.preload, 'metadata');
const track = video.children.find(child => child.tagName === 'track');
assert.equal(track.src, '/tutorial.vtt');
assert.equal(track.srclang, 'en');
assert.equal(video.paused, false, 'The click must authorize playback before async metadata, including on iPhone Safari');
video.emit('loadedmetadata');
assert.equal(video.currentTime, 82.733333, 'Seek must preserve fractional chapter time');
assert.equal(video.paused, false);
video.currentTime = 129;
video.emit('timeupdate');
assert.equal(video.paused, true, 'Chapter playback must stop at its end');
dialog.close();
assert.equal(video.paused, true);
assert.equal(video.src, undefined, 'Close must remove the media request source');
assert.equal(video.loaded, true, 'Close must cancel media loading');
assert.equal(content.children.length, 0);
assert.equal(native.focused, true);
assert.equal(document.body.style.overflow, '');
video.emit('loadedmetadata');
assert.equal(video.paused, true, 'Late metadata must not restart a closed video');
click(archive);
const archiveVideo = content.querySelectorAll('video')[0];
assert.equal(archiveVideo.src, '/original-realtime.mp4#t=0');
archiveVideo.emit('loadedmetadata');
assert.equal(archiveVideo.currentTime, 0);
archiveVideo.currentTime = 23.7;
archiveVideo.emit('timeupdate');
assert.equal(archiveVideo.paused, true);
assert.equal(chapterLink.attributes['aria-current'], 'true', 'Feature navigation highlights the visible feature');
dialog.close();
click(image);
assert.equal(content.children[0].src, '/image.webp');
assert.equal(content.children[0].alt, 'Actual app');
console.log('PASS: native captions/seek/end/cleanup/focus and self-hosted original chapters/image paths');
