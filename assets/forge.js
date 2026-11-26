// The wiki and the forge: when `wiki serve` serves the wiki live, it adds
// <meta name="cpull-wiki" content="/_forge"> to every page, and this script
// shows on each repo page its cpull repo page, open issues and CI status, on
// doc pages the open reports anchored to that file, with their lines
// highlighted, and on the home page each repo's open issues. The static site
// (GitHub Pages) has no such meta tag, so nothing here runs there. Server
// side: src/forge.zig, which asks cpull, radar and idlci; every link it
// returns is absolute (another tool's server), and a tool that isn't running
// answers 503, which reads here as "no forge".
const api = document.querySelector('meta[name="cpull-wiki"]')?.content;
const main = document.querySelector("main[data-wiki-repo]");

const el = (tag, attrs = {}, ...children) => {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, value);
  node.append(...children);
  return node;
};
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

// The block whose source lines hold `line`: the innermost one, so a list item's
// paragraph wins over the list. A fenced block's code starts one line later.
const blockFor = (line) => {
  let best = null;
  // document order: an ancestor comes before what it contains
  for (const node of main.querySelectorAll("p, li, h1, h2, h3, h4, h5, h6, pre, blockquote, tr, dt, dd")) {
    const pos = node.dataset.sourcepos?.match(/^(\d+):\d+-(\d+):\d+$/);
    if (!pos) continue;
    const start = Number(pos[1]) + (node.matches("pre") ? 1 : 0);
    if (line < start || line > Number(pos[2])) continue;
    if (!best || best.node.contains(node)) best = { node, start };
  }
  return best;
};

// The text of line `index` (0-based) inside `node`, as a Range: soft breaks and
// code lines are "\n" in the rendered text, as radar.js counts them.
const lineRange = (node, index) => {
  const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
  const range = document.createRange();
  let seen = 0;
  let started = index === 0;
  if (started) range.setStart(node, 0);
  for (let text = walker.nextNode(); text; text = walker.nextNode()) {
    const value = text.nodeValue;
    for (let i = 0; i < value.length; i++) {
      if (value[i] !== "\n") continue;
      if (started) {
        range.setEnd(text, i);
        return range;
      }
      seen++;
      if (seen === index) {
        range.setStart(text, i + 1);
        started = true;
      }
    }
  }
  if (!started) return null;
  range.setEnd(node, node.childNodes.length);
  return range;
};

let flags = [];
const showReports = (reports) => {
  for (const flag of flags) flag.remove();
  flags = [];
  const ranges = [];
  for (const report of reports) {
    const block = blockFor(report.line);
    if (!block) continue;
    const range = lineRange(block.node, report.line - block.start);
    if (!range) continue;
    ranges.push(range);
    report.range = range;
    report.block = block.node;
  }
  if (globalThis.Highlight && CSS.highlights) CSS.highlights.set("cpull-report", new Highlight(...ranges));
  placeFlags(reports);
};

// A flag in the sheet's left margin beside each reported line, linking to its issue.
const placeFlags = (reports) => {
  for (const flag of flags) flag.remove();
  flags = [];
  const origin = main.getBoundingClientRect();
  for (const report of reports) {
    if (!report.range) continue;
    const rect = report.range.getClientRects()[0] ?? report.range.getBoundingClientRect();
    const flag = el("a", { class: "wiki-report-flag", href: report.url, title: `${report.title} (line ${report.line})` });
    flag.style.top = `${rect.top - origin.top}px`;
    main.append(flag);
    flags.push(flag);
  }
};

const ciBadges = async (repo) => {
  const response = await fetch(`${api}/ci/projects`).catch(() => null);
  if (!response?.ok) return [];
  const projects = (await response.json()).filter((p) => p.repo === repo);
  return projects.map((p) => {
    const status = p.running ? "running" : (p.last_build?.status ?? "no builds");
    const label = projects.length > 1 ? `CI ${p.name}: ${status}` : `CI: ${status}`;
    const dot = el("span", { class: `wiki-ci-dot wiki-ci-${status.replace(/\W+/g, "-")}`, "aria-hidden": "true" });
    return el("a", { class: "badge text-bg-secondary text-decoration-none", href: p.url }, dot, label);
  });
};

const load = async () => {
  const repo = main.dataset.wikiRepo;
  const file = main.dataset.radarFile;
  const params = new URLSearchParams({ repo });
  if (file) params.set("file", file);
  const response = await fetch(`${api}/page?${params}`).catch(() => null);
  if (!response?.ok) return;
  const page = await response.json();
  if (!page.repo) return;

  // keep the reports list open across the reload after filing a report
  const wasOpen = main.querySelector(".wiki-forge-reports")?.open ?? false;
  main.querySelector(".wiki-forge")?.remove();
  const bar = el("div", { class: "wiki-forge d-flex flex-wrap align-items-center gap-2 small mb-3" },
    el("a", { class: "btn btn-sm btn-outline-secondary", href: page.repo.url }, `${page.repo.name} in cpull`),
    el("a", { class: "badge text-bg-secondary text-decoration-none", href: page.repo.issues_url }, plural(page.repo.open_issues, "open issue", "open issues")),
  );
  if (page.repo.open_reports) bar.append(el("a", { class: "badge text-bg-secondary text-decoration-none", href: page.repo.issues_url }, plural(page.repo.open_reports, "report", "reports")));
  bar.append(...(await ciBadges(repo)));

  if (page.reports.length) {
    // folded by default: the count, and the list (line, title) on demand
    const list = el("ul");
    for (const report of page.reports) {
      const jump = el("a", { href: "#", class: "wiki-forge-line" }, `line ${report.line}`);
      jump.addEventListener("click", (event) => {
        event.preventDefault();
        report.block?.scrollIntoView({ behavior: "smooth", block: "center" });
      });
      list.append(el("li", {}, jump, " · ", el("a", { href: report.url }, report.title)));
    }
    const summary = el("summary", {}, el("span", { class: "wiki-flag-dot", "aria-hidden": "true" }, "\u2691 "),
      plural(page.reports.length, "open report on this page", "open reports on this page"));
    const details = el("details", { class: "wiki-forge-reports w-100" }, summary, list);
    details.open = wasOpen;
    // opening it moves the page down: the margin flags follow
    details.addEventListener("toggle", () => placeFlags(page.reports));
    bar.append(details);
  }
  main.prepend(bar);
  showReports(page.reports);
  window.onresize = () => placeFlags(page.reports);
};

if (api && main) {
  load();
  // radar.js files reports through the api; show the new one
  document.addEventListener("cpull:report-filed", load);
}

// the home page: each repo card gets its open issues, linking to cpull
const cards = document.querySelectorAll(".card[data-wiki-repo]");
if (api && cards.length) {
  fetch(`${api}/repos`)
    .then((response) => (response.ok ? response.json() : []))
    .then((repos) => {
      const byName = new Map(repos.map((r) => [r.name, r]));
      for (const card of cards) {
        const repo = byName.get(card.dataset.wikiRepo);
        if (!repo?.cloned) continue;
        const body = card.querySelector(".card-body");
        let row = body.querySelector(".mt-auto");
        if (!row) body.append((row = el("p", { class: "card-text small mt-auto d-flex flex-wrap gap-1" })));
        // above the card's stretched link, so it stays clickable
        row.append(el("a", { class: "badge text-bg-secondary text-decoration-none position-relative z-2", href: repo.issues_url, title: `${repo.name} in cpull` }, plural(repo.open_issues, "open issue", "open issues")));
      }
    })
    .catch(() => {});
}
