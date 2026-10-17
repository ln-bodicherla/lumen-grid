chrome.commands.onCommand.addListener(async (command) => {
  if (command === 'toggle-lumen') {
    const { lumen = true } = await chrome.storage.sync.get('lumen');
    return chrome.storage.sync.set({ lumen: !lumen });
  }
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab?.id) chrome.tabs.sendMessage(tab.id, { cmd: 'focus' }).catch(() => {});
});

// dark Lumen theme is the default; turn it back on after installs/updates
chrome.runtime.onInstalled.addListener(() => chrome.storage.sync.set({ lumen: true, dim: 0.1 }));
