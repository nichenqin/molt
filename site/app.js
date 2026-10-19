(() => {
  const base = document.documentElement.dataset.base || "./";
  const feedURL = base + "latest.json";
  const fallback = "https://github.com/nichenqin/remige/releases/latest";

  async function loadFeed() {
    try {
      const response = await fetch(feedURL, { cache: "no-cache" });
      if (!response.ok) return;
      const feed = await response.json();
      const version = feed.version;
      if (!version) return;
      document.querySelectorAll("[data-latest-version]").forEach((el) => { el.textContent = version; });
      document.querySelectorAll('[data-download="dmg"]').forEach((el) => {
        const asset = feed.assets && feed.assets["Remige-macos.dmg"];
        if (asset && asset.url) el.href = asset.url;
      });
      document.querySelectorAll('[data-download="zip"]').forEach((el) => {
        const asset = feed.assets && feed.assets["Remige-macos.zip"];
        if (asset && asset.url) el.href = asset.url;
      });
      document.querySelectorAll('[data-download="cli"]').forEach((el) => {
        const asset = feed.assets && feed.assets["remige-cli"];
        if (asset && asset.url) el.href = asset.url;
      });
      const notes = document.getElementById("latest-notes");
      if (notes && feed.notes) {
        notes.textContent = feed.notes;
        notes.hidden = false;
      }
    } catch (_) {
      // Static fallback links already point at GitHub Releases.
    }
  }

  function wireCopyButtons() {
    document.querySelectorAll(".copy").forEach((button) => {
      button.addEventListener("click", async (event) => {
        event.preventDefault();
        const selector = button.dataset.copy;
        const source = selector && selector.startsWith("#")
          ? document.querySelector(selector)
          : button.closest(".install-line")?.querySelector("code")
            || button.parentElement?.querySelector("code");
        if (!source) return;
        const text = source.textContent.trim();
        try {
          await navigator.clipboard.writeText(text);
          const old = button.textContent;
          button.textContent = "Copied";
          setTimeout(() => { button.textContent = old; }, 1400);
        } catch (_) {
          window.prompt("Copy this command:", text);
        }
      });
    });
  }

  function wireMenu() {
    const toggle = document.getElementById("menu-toggle");
    const nav = document.getElementById("nav");
    if (!toggle || !nav) return;
    toggle.addEventListener("click", () => {
      const open = nav.classList.toggle("open");
      toggle.setAttribute("aria-expanded", String(open));
    });
    nav.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", () => {
        nav.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    loadFeed();
    wireCopyButtons();
    wireMenu();
    document.querySelectorAll('a[href="https://github.com/nichenqin/remige/releases/latest"]').forEach((link) => {
      if (!link.dataset.download) link.href = fallback;
    });
  });
})();
