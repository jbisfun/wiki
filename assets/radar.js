// Reports: select text on a docs page, right-click, and report that source line
// (a cpull issue anchored to it, in its repo). Rendered markdown carries
// data-sourcepos ("line:col-line:col", cpull src/wiki/markdown.zig); <main> carries the repo
// and file and the menu markup is templates/partials/radar.html.
//
// On the static site the menu copies the `pull cpull report` command that files
// it. When cpull serves the wiki live (the page has <meta name="cpull-wiki">,
// see forge.js), the menu also takes a note and files the report right away
// through cpull's wiki api, with a toast linking to the new issue.
import Dropdown from "bootstrap/js/dist/dropdown";
import Toast from "bootstrap/js/dist/toast";
import ClipboardJS from "clipboard";

const radar = document.querySelector("#radar-menu");
const api = document.querySelector('meta[name="cpull-wiki"]')?.content;
if (radar) {
  const quote = (text) => `'${text.replaceAll("'", `'\\''`)}'`;
  let cursor = new DOMRect();
  let command = "";
  let target = null;
  const menu = new Dropdown(radar.querySelector("[data-bs-toggle]"), {
    reference: { getBoundingClientRect: () => cursor },
    // The cursor rect is in viewport coordinates.
    popperConfig: { strategy: "fixed" },
    // typing a note mustn't close it
    autoClose: "outside",
  });

  // Line of the selection start: the element's start line plus the breaks before it
  // (a fenced block's code starts one line after its ``` line).
  const sourceLine = (range) => {
    const node = range.startContainer;
    const block = (node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement)?.closest("[data-sourcepos]");
    if (!block) return null;
    const before = document.createRange();
    before.setStart(block, 0);
    before.setEnd(node, range.startOffset);
    const fence = block.matches("pre") ? 1 : 0;
    return parseInt(block.dataset.sourcepos, 10) + fence + before.toString().split("\n").length - 1;
  };

  const make = (tag, props = {}) => Object.assign(document.createElement(tag), props);

  let form = null;
  if (api) {
    // the live menu: a note, a button that files the report and one that
    // copies the command instead (the menu follows the page's light/dark scheme)
    form = make("form", { className: "px-3 pb-2" });
    const actions = make("div", { className: "wiki-report-actions" });
    const copy = make("button", { type: "button", className: "btn btn-outline-secondary btn-sm", textContent: "Copy command" });
    copy.dataset.radarCopy = "";
    actions.append(make("button", { type: "submit", className: "btn btn-primary btn-sm", textContent: "File report" }), copy);
    form.append(
      make("textarea", { className: "form-control form-control-sm mb-2", name: "note", rows: 3, placeholder: "Note (optional)", ariaLabel: "Note" }),
      actions,
    );
    radar.querySelector("[data-radar-command]").after(form);
    for (const item of radar.querySelectorAll(".dropdown-item[data-radar-copy]")) item.remove();
  }

  const toast = (body) => {
    let holder = document.querySelector("#cpull-toasts");
    if (!holder) {
      // under the global bar, clear of the page's footer (style.css .tool-toasts)
      holder = make("div", { id: "cpull-toasts", className: "toast-container position-fixed end-0 p-3 tool-toasts" });
      document.body.append(holder);
    }
    const node = make("div", { className: "toast", role: "status", ariaLive: "polite" });
    const close = make("button", { type: "button", className: "btn-close ms-auto", ariaLabel: "Close" });
    close.dataset.bsDismiss = "toast";
    const inner = make("div", { className: "toast-body d-flex align-items-start gap-2" });
    inner.append(body, close);
    node.append(inner);
    holder.append(node);
    node.addEventListener("hidden.bs.toast", () => node.remove());
    new Toast(node, { delay: 6000 }).show();
  };

  form?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!target) return;
    const button = form.querySelector("button[type=submit]");
    button.disabled = true;
    const response = await fetch(`${api}/report`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...target, note: form.note.value }),
    }).catch((error) => ({ ok: false, status: String(error), json: async () => ({}) }));
    const result = await response.json().catch(() => ({}));
    button.disabled = false;
    menu.hide();
    const message = make("div");
    if (response.ok) {
      message.append("Filed ", make("a", { href: result.url, textContent: result.title }), ` (${target.file}:${target.line})`);
      form.reset();
      document.dispatchEvent(new CustomEvent("cpull:report-filed", { detail: result }));
    } else {
      message.append(`Couldn't file the report: ${result.error ?? response.status}`);
    }
    toast(message);
  });

  document.addEventListener("contextmenu", (event) => {
    const selection = getSelection();
    const text = selection.toString().trim();
    const page = selection.anchorNode?.parentElement?.closest("[data-radar-file]");
    const line = text && page && sourceLine(selection.getRangeAt(0));
    if (!line) return;
    event.preventDefault();
    const { radarRepo, radarFile } = page.dataset;
    target = { repo: radarRepo, file: radarFile, line, quote: text };
    command = `pull cpull report ${quote(radarRepo)} ${quote(radarFile)} ${line} --source wiki --quote ${quote(text)}`;
    radar.querySelector("[data-radar-command]").textContent = api ? `${radarRepo}/${radarFile}:${line}` : command;
    cursor = new DOMRect(event.clientX, event.clientY, 0, 0);
    menu.show();
    menu.update();
    form?.note.focus();
  });

  new ClipboardJS("[data-radar-copy]", {
    text: (button) => (button.dataset.radarCopy === "note" ? `${command} --note ''` : command),
  }).on("success", () => menu.hide());
}
