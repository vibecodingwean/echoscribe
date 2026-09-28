'use strict';
const dialog = document.querySelector('#media-dialog');
const content = document.querySelector('#media-content');
const title = document.querySelector('#media-title');
const caption = document.querySelector('#media-caption');
let trigger;
function openMedia(link) {
  let videoPlayer;
  trigger = link;
  title.textContent = link.dataset.title;
  content.replaceChildren();
  caption.replaceChildren();
  if (link.hasAttribute('data-video-src')) {
    const frame = document.createElement('div');
    frame.className = 'media-frame';
    const player = document.createElement('video');
    player.controls = true;
    player.playsInline = true;
    player.preload = 'metadata';
    player.setAttribute('aria-label', `EchoScribe — ${link.dataset.title}`);
    const start = Number(link.dataset.start || 0);
    const end = link.dataset.end ? Number(link.dataset.end) : null;
    player.addEventListener('loadedmetadata', () => {
      if (!dialog.open || !content.contains(player)) return;
      player.currentTime = start;
    }, {once: true});
    if (end !== null) player.addEventListener('timeupdate', () => {
      if (player.currentTime >= end) player.pause();
    });
    if (link.dataset.captions) {
      const track = document.createElement('track');
      track.kind = 'captions';
      track.label = 'English';
      track.srclang = 'en';
      track.src = link.dataset.captions;
      player.append(track);
    }
    player.src = `${link.dataset.videoSrc}#t=${start}`;
    videoPlayer = player;
    frame.append(player);
    content.append(frame);
    caption.append(document.createTextNode('Video served by this website. English captions available. '));
    const fallback = document.createElement('a');
    fallback.href = link.href;
    fallback.textContent = 'Open video ↗';
    caption.append(fallback);
  } else {
    const img = document.createElement('img');
    img.src = link.href;
    img.alt = link.querySelector('img').alt;
    img.className = 'media-image';
    content.append(img);
    caption.textContent = 'Actual app capture. Shown in its original screen proportions.';
  }
  dialog.showModal();
  videoPlayer?.play().catch(() => {});
  document.body.style.overflow = 'hidden';
  dialog.querySelector('.close').focus();
}
document.querySelectorAll('[data-video-src], [data-image]').forEach(link => {
  link.addEventListener('click', event => {
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || event.button !== 0) return;
    event.preventDefault();
    openMedia(link);
  });
});
dialog.querySelector('.close').addEventListener('click', () => dialog.close());
dialog.addEventListener('click', event => {
  const rect = dialog.getBoundingClientRect();
  if (event.target === dialog && (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom)) dialog.close();
});
dialog.addEventListener('close', () => {
  for (const player of content.querySelectorAll('video')) {
    player.pause();
    player.removeAttribute('src');
    player.load();
  }
  content.replaceChildren();
  caption.replaceChildren();
  document.body.style.overflow = '';
  trigger?.focus({preventScroll: true});
});
const chapterLinks = [...document.querySelectorAll('nav[aria-label="Feature guides"] a')];
const chapters = [...document.querySelectorAll('.feature')];
if (chapters.length) {
  let scheduled = false;
  const markCurrent = () => {
    const current = chapters.filter(section => section.getBoundingClientRect().top < innerHeight * .45).at(-1) || chapters[0];
    for (const link of chapterLinks) {
      if (link.hash === `#${current.id}`) link.setAttribute('aria-current', 'true');
      else link.removeAttribute('aria-current');
    }
    scheduled = false;
  };
  addEventListener('scroll', () => {
    if (!scheduled) { scheduled = true; requestAnimationFrame(markCurrent); }
  }, {passive: true});
  markCurrent();
}
