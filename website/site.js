'use strict';
const dialog = document.querySelector('#media-dialog');
const content = document.querySelector('#media-content');
const title = document.querySelector('#media-title');
const caption = document.querySelector('#media-caption');
let trigger;
function openMedia(link) {
  trigger = link;
  title.textContent = link.dataset.title;
  content.replaceChildren();
  caption.replaceChildren();
  if (link.hasAttribute('data-video')) {
    const frame = document.createElement('div');
    frame.className = 'media-frame';
    const player = document.createElement('iframe');
    const url = new URL('https://www.youtube-nocookie.com/embed/ktm5KKzvA5A');
    url.searchParams.set('start', link.dataset.start || '0');
    if (link.dataset.end) url.searchParams.set('end', link.dataset.end);
    url.searchParams.set('autoplay', '1');
    url.searchParams.set('playsinline', '1');
    url.searchParams.set('rel', '0');
    player.src = url.href;
    player.title = `EchoScribe — ${link.dataset.title}`;
    player.allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share';
    player.allowFullscreen = true;
    player.referrerPolicy = 'strict-origin-when-cross-origin';
    frame.append(player);
    content.append(frame);
    caption.append(document.createTextNode('Playing via YouTube. Its privacy policies apply. '));
    const fallback = document.createElement('a');
    fallback.href = link.href;
    fallback.target = '_blank';
    fallback.rel = 'noopener';
    fallback.textContent = 'Open on YouTube ↗';
    caption.append(fallback);
  } else {
    const img = document.createElement('img');
    img.src = link.href;
    img.alt = link.querySelector('img').alt;
    img.className = 'media-image';
    content.append(img);
    caption.textContent = 'Actual app capture. Shown in its original Pixel proportions.';
  }
  dialog.showModal();
  document.body.style.overflow = 'hidden';
  dialog.querySelector('.close').focus();
}
document.querySelectorAll('[data-video], [data-image]').forEach(link => {
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
  content.replaceChildren();
  caption.replaceChildren();
  document.body.style.overflow = '';
  trigger?.focus({preventScroll: true});
});
const chapterLinks = [...document.querySelectorAll('nav[aria-label="Feature chapters"] a')];
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
