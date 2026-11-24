// The site header embedded in rustdoc/LDoc pages (partials/apidoc-header.html) sits in
// a shadow root so the site CSS and the doc tool's CSS never meet. Bootstrap's
// data-api listens on document and can't see into it, so wire it up here: theme,
// dropdowns, the small-screen menu, and room at the top of the page for the header.
import Collapse from "bootstrap/js/dist/collapse";
import Dropdown from "bootstrap/js/dist/dropdown";

const host = document.querySelector("wiki-header");
const root = host?.shadowRoot;
if (root) {
  const shell = root.querySelector(".wiki-shadow");
  if (!host.dataset.theme) {
    const scheme = matchMedia("(prefers-color-scheme: dark)");
    const applyScheme = () => (shell.dataset.bsTheme = scheme.matches ? "dark" : "light");
    applyScheme();
    scheme.addEventListener("change", applyScheme);
  }

  for (const toggle of root.querySelectorAll('[data-bs-toggle="collapse"]')) {
    const target = root.querySelector(toggle.dataset.bsTarget);
    if (!target) continue;
    const collapse = new Collapse(target, { toggle: false });
    toggle.addEventListener("click", () => collapse.toggle());
    target.addEventListener("shown.bs.collapse", () => toggle.setAttribute("aria-expanded", "true"));
    target.addEventListener("hidden.bs.collapse", () => toggle.setAttribute("aria-expanded", "false"));
  }

  const toggles = [...root.querySelectorAll('[data-bs-toggle="dropdown"]')];
  for (const toggle of toggles) {
    toggle.addEventListener("click", (event) => {
      event.preventDefault();
      for (const other of toggles) if (other !== toggle) Dropdown.getInstance(other)?.hide();
      Dropdown.getOrCreateInstance(toggle).toggle();
    });
  }
  // Clicks outside the header reach document retargeted to the host, which
  // Bootstrap's own outside-click handling doesn't recognise.
  document.addEventListener("click", (event) => {
    if (event.composedPath().includes(host)) return;
    for (const toggle of toggles) Dropdown.getInstance(toggle)?.hide();
  });

  const reserve = () =>
    document.documentElement.style.setProperty("--wiki-header-height", `${host.offsetHeight}px`);
  new ResizeObserver(reserve).observe(host);
  reserve();
}
