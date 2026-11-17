// Render every repo's docs/ (plus pages/*.ejs) into plain HTML.
// Usage: node src/render.js MANIFEST OUT_DIR  (manifest from bin/collect.sh)
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
const [MANIFEST, OUT] = process.argv.slice(2).map((p) => path.resolve(p));
const TEMPLATES = path.join(WIKI, "templates");
const PAGES = path.join(WIKI, "pages");
const posix = path.posix;

const SITE_TITLE = process.env.WIKI_TITLE ?? "jbisfun wiki";

// mdBook projects keep pages in book.toml's `src` (default "src").
async function docsRoot(docsDir) {
  const bookToml = path.join(docsDir, "book.toml");
  if (!existsSync(bookToml)) return { root: docsDir, title: null };
  const book = parseToml(await readFile(bookToml, "utf8")).book ?? {};
  return { root: path.join(docsDir, book.src ?? "src"), title: book.title ?? null };
}

async function loadRepos() {
  const manifest = JSON.parse(await readFile(MANIFEST, "utf8"));
  const repos = [];
  for (const repo of manifest.repos) {
    const { root, title } = await docsRoot(path.join(repo.path, "docs"));
    const files = (await glob(["**/*"], { cwd: root, ignore: ["**/node_modules/**"] })).sort();
    if (!files.some((f) => /\.(md|ejs)$/.test(f))) continue;
    repos.push({ ...repo, root, files, title: title ?? repo.name, blob: repo.web ? `${repo.web}/blob/${repo.branch}/` : null });
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

// Nested {name, page, children} tree of a repo's pages, for repos without SUMMARY.md.
function pageTree(pages) {
  const root = { name: "", children: new Map() };
  for (const page of pages) {
    const parts = page.rel.split("/");
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

const markActive = (html, from) =>
  html.replaceAll(`href="${posix.basename(from)}"`, `class="active" aria-current="page" href="${posix.basename(from)}"`);

async function main() {
  await rm(OUT, { recursive: true, force: true });
  await mkdir(OUT, { recursive: true });

  const repos = await loadRepos();
  const pages = [];

  for (const repo of repos) {
    repo.pages = [];
    repo.byRel = new Map();
    for (const rel of repo.files) {
      const out = `${repo.name}/${outName(rel)}`;
      repo.byRel.set(rel, out);
      if (rel === "SUMMARY.md") continue;
      if (rel.endsWith(".md") || rel.endsWith(".ejs")) {
        const src = path.join(repo.root, rel);
        const { data, content } = frontMatter(await readFile(src, "utf8"));
        const page = { repo, rel, src, out, data, body: content, title: titleOf(data, content, rel) };
        repo.pages.push(page);
        pages.push(page);
      } else {
        await mkdir(path.dirname(path.join(OUT, out)), { recursive: true });
        await cp(path.join(repo.root, rel), path.join(OUT, out));
      }
    }
    repo.summary = repo.files.includes("SUMMARY.md")
      ? await readFile(path.join(repo.root, "SUMMARY.md"), "utf8")
      : null;
    repo.tree = pageTree(repo.pages);
    repo.index = `${repo.name}/index.html`;
    if (!repo.pages.some((p) => p.out === repo.index)) {
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
      for (const candidate of [target, `${target}/README.md`, `${target}/index.md`]) {
        const out = repo.byRel.get(candidate);
        if (out) return url(from, out) + suffix;
      }
      // Outside docs/ (source files, missing pages): link to the repo on GitHub.
      const inRepo = path.relative(repo.path, path.join(repo.root, target));
      if (repo.blob && !inRepo.startsWith("..")) return repo.blob + inRepo.split(path.sep).join("/") + suffix;
      return link;
    },
  });

  const site = { title: SITE_TITLE, repos: repos, pages };
  const renderMd = (source, env) => md.render(preprocess(source), env);

  function sidebar(repo, from) {
    if (!repo) return "";
    const html = repo.summary
      ? renderMd(repo.summary, { repo, base: ".", from })
      : ejs.render('<%- include("partials/tree", { node: tree, url }) %>', { tree: repo.tree, url: (to) => url(from, to) }, { views: [TEMPLATES], filename: path.join(TEMPLATES, "sidebar.ejs") });
    return markActive(html, from);
  }

  for (const page of pages) {
    const from = page.out;
    const env = { repo: page.repo, base: posix.dirname(page.rel || "."), from };
    const data = {
      site,
      page,
      repo: page.repo,
      url: (to) => url(from, to),
      md: (source) => (page.repo ? renderMd(source, env) : md.render(source)),
      sidebar: () => sidebar(page.repo, from),
    };
    const ejsOpts = { views: [TEMPLATES], filename: page.src ?? path.join(TEMPLATES, "layout.ejs") };

    let content;
    if (page.synthetic) content = await ejs.renderFile(path.join(TEMPLATES, "repo-index.ejs"), data, ejsOpts);
    else if (page.ejs || page.rel.endsWith(".ejs")) content = ejs.render(page.body, data, ejsOpts);
    else content = data.md(page.data.ejs ? ejs.render(page.body, data, ejsOpts) : page.body);

    const html =
      page.data.layout === false
        ? content
        : await ejs.renderFile(path.join(TEMPLATES, page.data.layout ?? "layout.ejs"), { ...data, content }, ejsOpts);

    const dest = path.join(OUT, page.out);
    await mkdir(path.dirname(dest), { recursive: true });
    await writeFile(dest, html);
  }

  console.log(`wiki: ${pages.length} pages from ${repos.map((r) => r.name).join(", ")}`);
}

await main();
