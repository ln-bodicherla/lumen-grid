const $ = (id) => document.getElementById(id);
chrome.storage.sync.get({ auto: true, wall: true, lumen: true, dim: 0.1, style: 'inplace', bypass: [], scrTop: 12, scrBottom: 0 }, (s) => {
  $('scrTop').value = s.scrTop; $('scrBottom').value = s.scrBottom;
  $('bypass').value = s.bypass.join('\n');
  refreshSite();
  $('style').value = s.style;
  $('auto').checked = s.auto; $('wall').checked = s.wall; $('lumen').checked = s.lumen; $('dim').value = s.dim;
});
$('style').onchange = (e) => chrome.storage.sync.set({ style: e.target.value });
$('wall').onchange = (e) => chrome.storage.sync.set({ wall: e.target.checked });
$('auto').onchange = (e) => chrome.storage.sync.set({ auto: e.target.checked });
$('lumen').onchange = (e) => chrome.storage.sync.set({ lumen: e.target.checked });
for (const k of ['scrTop', 'scrBottom']) $(k).oninput = (e) => chrome.storage.sync.set({ [k]: Math.max(0, Math.min(80, +e.target.value || 0)) });
$('dim').oninput = (e) => chrome.storage.sync.set({ dim: +e.target.value });
$('go').onclick = async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  chrome.tabs.sendMessage(tab.id, { cmd: 'focus' }).catch(() => {});
  window.close();
};

// ---------- bypass list ----------
let tabUrl = null;
const rules = () => $('bypass').value.split('\n').map((r) => r.trim()).filter(Boolean);
const saveRules = (list) => chrome.storage.sync.set({ bypass: list });
let saveTimer = 0;
$('bypass').oninput = () => { clearTimeout(saveTimer); saveTimer = setTimeout(() => { saveRules(rules()); refreshSite(); }, 300); };

async function refreshSite() {
  if (!tabUrl) {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    tabUrl = tab?.url && /^https?:/.test(tab.url) ? tab.url : '';
  }
  const btn = $('site');
  if (!tabUrl) { btn.disabled = true; btn.textContent = 'NO WEBSITE IN THIS TAB'; return; }
  const host = new URL(tabUrl).hostname.replace(/^www\./, '');
  const hits = rules().filter((r) => tfMatchRule(r, tabUrl));
  btn.classList.toggle('on', hits.length > 0);
  btn.textContent = hits.length ? 'APPLY THEME HERE AGAIN' : 'BYPASS ' + host.toUpperCase();
  $('status').textContent = hits.length ? 'Bypassed by: ' + hits.join(', ') : '';
}

$('site').onclick = () => {
  if (!tabUrl) return;
  const host = new URL(tabUrl).hostname.replace(/^www\./, '');
  const list = rules();
  const hits = list.filter((r) => tfMatchRule(r, tabUrl));
  // un-bypass removes every rule that matches this page; bypass adds the bare domain
  const next = hits.length ? list.filter((r) => !hits.includes(r)) : [...list, host];
  $('bypass').value = next.join('\n');
  saveRules(next);
  refreshSite();
};
