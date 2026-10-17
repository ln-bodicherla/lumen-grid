// Bypass rules, shared by the content script and the popup.
// "example.com" (or "*.example.com") covers the domain and its subdomains.
// Anything with "/" is a URL pattern where "*" means anything; the https:// and www. parts are optional.
// Lines starting with "#" are comments.
globalThis.tfMatchRule = (rule, href) => {
  rule = rule.trim();
  if (!rule || rule.startsWith('#')) return false;
  if (!rule.includes('/')) rule = rule.replace(/^\*\./, '');  // "*.site.com" is just a domain
  if (/[/*]/.test(rule)) {
    const re = new RegExp('^' + rule.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$');
    const url = href.split('#')[0];
    return re.test(url) || re.test(url.replace(/^https?:\/\//, '')) || re.test(url.replace(/^https?:\/\/(www\.)?/, ''));
  }
  rule = rule.replace(/^www\./, '').toLowerCase();
  const h = new URL(href).hostname.toLowerCase();
  return h === rule || h.endsWith('.' + rule);
};
