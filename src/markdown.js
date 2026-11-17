/**
 * markdown-it configured for docs from many repos: anchors, {#id} attrs,
 * highlight.js at build time (no client JS), and link rewriting so that
 * .md links become pages and links to other repo files point at GitHub.
 * @module markdown
 */
import MarkdownIt from "markdown-it";
import anchor from "markdown-it-anchor";
import attrs from "markdown-it-attrs";
import replaceLink from "markdown-it-replace-link";
import hljs from "highlight.js";

const SCHEME = /^[a-z][a-z0-9+.-]*:|^\/\/|^#/i;

/**
 * Create the markdown-it instance used for every page.
 * @param {object} options
 * @param {function(string, object, object): string} options.resolveLink
 *   Rewrites relative links (link, env, token); `env` is the render env ({repo, base, from}).
 * @returns {MarkdownIt}
 */
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

/**
 * Replace the mdBook preprocessor commands used by the zed docs
 * (`{#kb action}` / `{#action action}`) with code spans.
 * Code spans, not inline HTML: replace-link's processHTML re-serializes
 * HTML tag by tag and would lose the closing tags.
 * @param {string} source markdown
 * @returns {string}
 */
export function preprocess(source) {
  return source.replace(/\{#(?:kb|action)\s+([^}]+)\}/g, (_, action) => `\`${action.trim()}\``);
}
