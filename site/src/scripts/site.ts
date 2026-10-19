interface FeedAsset {
  url?: string;
}

interface Feed {
  version?: string;
  notes?: string;
  assets?: Record<string, FeedAsset>;
}

async function applyFeed(): Promise<void> {
  try {
    const response = await fetch('/latest.json', { cache: 'no-cache' });
    if (!response.ok) return;
    const feed: Feed = await response.json();

    document.querySelectorAll<HTMLElement>('[data-latest-version]').forEach((element) => {
      if (feed.version) element.textContent = feed.version;
    });

    document.querySelectorAll<HTMLAnchorElement>('[data-download]').forEach((element) => {
      const asset = feed.assets?.[`Remige-macos.${element.dataset.download === 'dmg' ? 'dmg' : 'zip'}`];
      if (asset?.url) element.href = asset.url;
    });

    const notes = document.getElementById('latest-notes');
    if (notes && feed.notes) {
      notes.textContent = feed.notes;
      notes.hidden = false;
    }
  } catch {
    // Static fallbacks already point at GitHub Releases.
  }
}

function wireCopyButtons(): void {
  document.addEventListener('click', async (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const button = target.closest<HTMLButtonElement>('[data-copy]');
    if (!button) return;
    event.preventDefault();
    const code = button.closest('[data-copy-source]')?.querySelector('code');
    const text = code?.textContent?.trim();
    if (!text) return;
    const original = button.textContent;
    try {
      await navigator.clipboard.writeText(text);
      button.textContent = button.dataset.copiedLabel ?? original;
      window.setTimeout(() => {
        button.textContent = original;
      }, 1400);
    } catch {
      window.prompt(button.dataset.copyPrompt ?? 'Copy this command:', text);
    }
  });
}

function wireMobileMenu(): void {
  document.querySelectorAll<HTMLDetailsElement>('[data-mobile-menu]').forEach((menu) => {
    menu.querySelectorAll('a').forEach((link) => {
      link.addEventListener('click', () => menu.removeAttribute('open'));
    });
  });
}

applyFeed();
wireCopyButtons();
wireMobileMenu();
