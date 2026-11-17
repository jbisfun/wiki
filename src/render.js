// Render every repo's README.md (its entry page) and docs/ (plus
// pages/*.ejs) into plain HTML, and link the code docs from bin/apidoc.sh.
// Usage: node src/render.js MANIFEST API_JSON API_DIR OUT_DIR
//   MANIFEST from bin/collect.sh; API_JSON and API_DIR from bin/apidoc.sh.
import { existsSync } from "node:fs";
import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import ejs from "ejs";
import matter from "gray-matter";
import { glob } from "tinyglobby";
import { parse as parseToml } from "smol-toml";
import { createMarkdown, preprocess } from "./markdown.js";

const WIKI = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const [MANIFEST, API_JSON, API_DIR, OUT] = process.argv.slice(2).map((p) => path.resolve(p));
const TEMPLATES = path.join(WIKI, "templates");
const PAGES = path.join(WIKI, "pages");
const posix = path.posix;

const SITE_TITLE = process.env.WIKI_TITLE ?? "jbisfun wiki";
const IMAGE = /\.(png|jpe?g|gif|svg|webp|avif|ico)$/i;
const API_LABELS = { rust: "Rust", lua: "Lua", js: "JavaScript" };

// mdBook projects keep pages in book.toml's `src` (default "src").
async function docsRoot(docsDir) {
  const bookToml = path.join(docsDir, "book.toml");
  if (!existsSync(bookToml)) return { root: docsDir, title: null };
  const book = parseToml(await readFile(bookToml, "utf8")).book ?? {};
  return { root: path.join(docsDir, book.src ?? "src"), title: book.title ?? null };
}

// Per repo, `files` lists {rel (repo-relative), docRel, out}: the README is
// the repo's index page, docs/ files go under <repo>/docs/.
async function loadRepos(api) {
  const manifest = JSON.parse(await readFile(MANIFEST, "utf8"));
  const repos = [];
  for (const repo of manifest.repos) {
    const files = [];
    if (repo.readme) files.push({ rel: repo.readme, out: `${repo.name}/index.html` });
    let docsRel = null;
    let bookTitle = null;
    if (repo.docs) {
      const { root, title } = await docsRoot(path.join(repo.path, "docs"));
      docsRel = path.relative(repo.path, root).split(path.sep).join("/");
      bookTitle = title;
      for (const f of (await glob(["**/*"], { cwd: root, ignore: ["**/node_modules/**"] })).sort()) {
        files.push({ rel: `${docsRel}/${f}`, docRel: f, out: `${repo.name}/docs/${outName(f)}` });
      }
    }
    const apis = (api[repo.name] ?? []).map((a) => ({ ...a, label: API_LABELS[a.tool] ?? a.tool, out: `${repo.name}/api/${a.path}` }));
    if (!files.some((f) => /\.(md|ejs)$/.test(f.rel)) && !apis.length) continue;
    repos.push({
      ...repo,
      files,
      docsRel,
      bookTitle,
      apis,
      title: repo.name,
      blob: repo.web ? `${repo.web}/blob/${repo.branch}/` : null,
      raw: repo.web ? `${repo.web}/raw/${repo.branch}/` : null,
    });
  }
  return repos;
}

// Relative URL from one output page to another, both site-relative.
function url(from, to) {
  if (/^[a-z][a-z0-9+.-]*:|^\/\/|^#/i.test(to)) return to;
  to = to.replace(/^\//, "");
  if (to === "" || to.endsWith("/")) to += "index.html";
  return posix.relative(posix.dirname(from), to) || posix.basename(to);
}

function outName(rel) {
  const dir = posix.dirname(rel);
  const base = posix.basename(rel);
  let name;
  if (/^(readme|index)\.md$/i.test(base)) name = "index.html";
  else if (base.endsWith(".md")) name = base.slice(0, -3) + ".html";
  else if (base.endsWith(".ejs")) {
    name = base.slice(0, -4);
    if (!posix.extname(name)) name += ".html";
  } else name = base;
  return dir === "." ? name : `${dir}/${name}`;
}

function titleOf(data, body, rel) {
  if (data.title) return String(data.title);
  const h1 = body.match(/^#\s+(.+?)\s*(\{#[^}]*\})?\s*$/m);
  if (h1) return h1[1].replace(/[`*_]/g, "");
  return posix.basename(rel).replace(/\.(md|ejs)$/, "").replace(/[-_]/g, " ");
}

// Nested {name, page, children} tree of a repo's docs pages, for docs without SUMMARY.md.
function pageTree(pages) {
  const root = { name: "", children: new Map() };
  for (const page of pages) {
    const parts = page.docRel.split("/");
    let node = root;
    for (const part of parts.slice(0, -1)) {
      if (!node.children.has(part)) node.children.set(part, { name: part, children: new Map() });
      node = node.children.get(part);
    }
    const leaf = parts.at(-1);
    if (/^(readme|index)\.(md|ejs)$/i.test(leaf)) node.page = page;
    else node.children.set(leaf, { name: leaf, page, children: new Map() });
  }
  return root;
}

// gray-matter (YAML), falling back to `key: value` lines for the loose
// front matter mdBook accepts (e.g. unquoted colons in descriptions).
function frontMatter(source) {
  try {
    return matter(source);
  } catch {
    const m = source.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
    const data = {};
    for (const line of m[1].split(/\r?\n/)) {
      const at = line.indexOf(":");
      if (at > 0) data[line.slice(0, at).trim()] = line.slice(at + 1).trim();
    }
    return { data, content: source.slice(m[0].length) };
  }
}

// Plain text of a README's first paragraph with text (not just badges), for
// the home page cards.
function firstParagraph(md, source) {
  const tokens = md.parse(source, {});
  for (let at = 0; at < tokens.length; at++) {
    if (tokens[at].type !== "paragraph_open") continue;
    const text = tokens[at + 1].children
      .filter((t) => t.type === "text" || t.type === "code_inline" || t.type === "softbreak")
      .map((t) => (t.type === "softbreak" ? " " : t.content))
      .join("")
      .trim();
    if (text) return text;
  }
  return null;
}

const markActive = (html, from) =>
  html.replaceAll(`href="${posix.basename(from)}"`, `class="active" aria-current="page" href="${posix.basename(from)}"`);

async function main() {
  await rm(OUT, { recursive: true, force: true });
  await mkdir(OUT, { recursive: true });

  const api = existsSync(API_JSON) ? JSON.parse(await readFile(API_JSON, "utf8")) : {};
  const repos = await loadRepos(api);
  const pages = [];

  for (const repo of repos) {
    repo.pages = [];
    repo.byRel = new Map(repo.files.map((f) => [f.rel, f.out]));
    for (const { rel, docRel, out } of repo.files) {
      if (docRel === "SUMMARY.md") continue;
      const src = path.join(repo.path, rel);
      if (rel.endsWith(".md") || rel.endsWith(".ejs")) {
        const source = await readFile(src, "utf8");
        const { data, content } = frontMatter(source);
        // Source lines above the body (front matter), so rendered blocks map to file lines.
        const lineOffset = source.slice(0, source.lastIndexOf(content)).split("\n").length - 1;
        const page = { repo, rel, docRel, src, out, data, body: content, lineOffset, title: titleOf(data, content, rel), readme: rel === repo.readme };
        repo.pages.push(page);
        pages.push(page);
      } else {
        await mkdir(path.dirname(path.join(OUT, out)), { recursive: true });
        await cp(src, path.join(OUT, out));
      }
    }
    if (repo.apis.length) await cp(path.join(API_DIR, repo.name), path.join(OUT, repo.name, "api"), { recursive: true });
    repo.summary = repo.docsRel && repo.byRel.has(`${repo.docsRel}/SUMMARY.md`)
      ? (await readFile(path.join(repo.path, repo.docsRel, "SUMMARY.md"), "utf8")).replace(/^#\s+Summary\s*\n/i, "")
      : null;
    repo.docPages = repo.pages.filter((p) => p.docRel);
    repo.tree = pageTree(repo.docPages);
    repo.index = `${repo.name}/index.html`;
    repo.readmePage = repo.pages.find((p) => p.readme) ?? null;
    if (!repo.readmePage) {
      const page = { repo, rel: "", out: repo.index, data: {}, body: null, title: repo.title, synthetic: true };
      repo.pages.unshift(page);
      pages.push(page);
    }
  }

  for (const rel of await glob(["**/*.ejs"], { cwd: PAGES })) {
    const src = path.join(PAGES, rel);
    const { data, content } = frontMatter(await readFile(src, "utf8"));
    pages.push({ repo: null, rel, src, out: outName(rel), data, body: content, title: data.title ?? SITE_TITLE, ejs: true });
  }

  const md = createMarkdown({
    resolveLink(link, env) {
      const { repo, base, from } = env;
      const cut = link.search(/[?#]/);
      const pathPart = cut < 0 ? link : link.slice(0, cut);
      const suffix = cut < 0 ? "" : link.slice(cut);
      if (!pathPart) return link;
      if (pathPart.startsWith("/")) return url(from, pathPart);
      const target = posix.normalize(posix.join(base, decodeURI(pathPart))).replace(/\/$/, "");
      for (const candidate of [target, `${target}/README.md`, `${target}/readme.md`, `${target}/index.md`]) {
        const out = repo.byRel.get(candidate);
        if (out) return url(from, out) + suffix;
      }
      // Other files in the repo (source, images, missing pages): GitHub.
      if (repo.blob && target !== ".." && !target.startsWith("../")) {
        return (IMAGE.test(target) ? repo.raw : repo.blob) + (target === "." ? "" : target) + suffix;
      }
      return link;
    },
  });

  for (const repo of repos) repo.description = repo.readmePage ? firstParagraph(md, repo.readmePage.body) : null;

  const site = { title: SITE_TITLE, repos: repos, pages };
  const renderMd = (source, env) => md.render(preprocess(source), env);
  const ejsOpts = (filename) => ({ views: [TEMPLATES], filename });

  function sidebar(repo, from) {
    if (!repo) return "";
    const link = (to) => url(from, to);
    const docs = repo.summary
      ? renderMd(repo.summary, { repo, base: repo.docsRel, from })
      : ejs.render('<%- include("partials/tree", { node: tree, url }) %>', { tree: repo.tree, url: link }, ejsOpts(path.join(TEMPLATES, "sidebar.ejs")));
    const html = ejs.render('<%- include("partials/repo-nav") %>', { repo, docs, url: link }, ejsOpts(path.join(TEMPLATES, "sidebar.ejs")));
    return markActive(html, from);
  }

  for (const page of pages) {
    const from = page.out;
    const env = { repo: page.repo, base: posix.dirname(page.rel || "."), from, lineOffset: page.lineOffset ?? 0 };
    const data = {
      site,
      page,
      repo: page.repo,
      url: (to) => url(from, to),
      md: (source) => (page.repo ? renderMd(source, env) : md.render(source)),
      sidebar: () => sidebar(page.repo, from),
    };
    const opts = ejsOpts(page.src ?? path.join(TEMPLATES, "layout.ejs"));

    let content;
    if (page.synthetic) content = await ejs.renderFile(path.join(TEMPLATES, "repo-index.ejs"), data, opts);
    else if (page.ejs || page.rel.endsWith(".ejs")) content = ejs.render(page.body, data, opts);
    else content = data.md(page.data.ejs ? ejs.render(page.body, data, opts) : page.body);

    const html =
      page.data.layout === false
        ? content
        : await ejs.renderFile(path.join(TEMPLATES, page.data.layout ?? "layout.ejs"), { ...data, content }, opts);

    const dest = path.join(OUT, page.out);
    await mkdir(path.dirname(dest), { recursive: true });
    await writeFile(dest, html);
  }

  const apiCount = repos.reduce((n, r) => n + r.apis.length, 0);
  console.log(`wiki: ${pages.length} pages and ${apiCount} code references from ${repos.map((r) => r.name).join(", ")}`);
}

await main();
