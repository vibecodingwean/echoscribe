const HOST = '(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}';
const PATH = '(?:[/?#][^\\s<>"\']*)?';
const WEB_ADDRESS = new RegExp([
  `\\b(?:https?|ftp):\\/\\/[^\\s<>"']+`,
  `\\bfile:\\/\\/[^\\s<>"']+`,
  `\\b(?:mailto|data|javascript):[^\\s<>"']+`,
  `\\b[a-z0-9.!#$%&'*+/=?^_\u0060{|}~-]+@${HOST}\\b`,
  `\\/\\/${HOST}${PATH}`,
  `\\bwww\\.${HOST}${PATH}`,
  `\\b${HOST}${PATH}`
].join('|'), 'gi');

const SIMPLE_TRAILING = new Set(['.', ',', ';', ':', '!', '?']);
const PAIRS = { ')': '(', ']': '[', '}': '{' };

function detachTrailingPunctuation(candidate) {
  let address = candidate;
  let trailing = '';
  while (address) {
    const last = address.at(-1);
    if (SIMPLE_TRAILING.has(last)) {
      address = address.slice(0, -1);
      trailing = last + trailing;
      continue;
    }
    const opener = PAIRS[last];
    if (!opener) break;
    const opens = [...address].filter((character) => character === opener).length;
    const closes = [...address].filter((character) => character === last).length;
    if (closes <= opens) break;
    address = address.slice(0, -1);
    trailing = last + trailing;
  }
  return `[link removed]${trailing}`;
}

export function stripWebAddresses(value) {
  return String(value || '').replace(WEB_ADDRESS, detachTrailingPunctuation);
}
