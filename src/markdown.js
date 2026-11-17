// markdown-it configured for docs from many repos: anchors, {#id} attrs,
// highlight.js at build time (no client JS), and link rewriting so that
// .md links become pages and links leaving docs/ point at GitHub.
import MarkdownIt from "markdown-it";
import anchor from "markdown-it-anchor";
import attrs from "markdown-it-attrs";
import replaceLink from "markdown-it-replace-link";
import hljs from "highlight.js";

const SCHEME = /^[a-z][a-z0-9+.-]*:|^\/\/|^#/i;

export function createMarkdown({ resolveLink }) {
  const md = new MarkdownIt({
    html: true,
    linkify: true,
    typographer: true,
    highlight(code, info) {
      const lang = (info || "").trim().split(/\s+/)[0];
      if (lang && hljs.getLanguage(lang)) {
        return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
      }
      return "";
    },
  });
  md.use(attrs, { allowedAttributes: ["id", "class"] });
  md.use(anchor, { tabIndex: false, failOnNonUnique: false, permalink: anchor.permalink.headerLink() });
  md.use(replaceLink, {
    processHTML: true,
    replaceLink(link, env, token) {
      if (!env?.repo || !link || SCHEME.test(link)) return link;
      return resolveLink(link, env, token);
    },
  });
  // Bootstrap look for plain markdown tables.
  md.renderer.rules.table_open = () => '<table class="table table-sm table-striped">\n';
  return md;
}

// mdBook preprocessor commands used by the zed docs: {#kb action} / {#action action}.
// Emitted as markdown code spans: inline HTML would be re-serialized tag by
// tag by replace-link's processHTML and lose its closing tags.
export function preprocess(source) {
  return source.replace(/\{#(?:kb|action)\s+([^}]+)\}/g, (_, action) => `\`${action.trim()}\``);
}
