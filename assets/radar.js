// Reports: select text on a docs page, right-click, and copy the `pull cpull report`
// command that files it (a cpull issue anchored to that source line, in its repo). Rendered markdown carries data-sourcepos ("line:col-line:col",
// src/markdown.rs); <main> carries the repo and file and the menu markup is
// templates/partials/radar.html.
import Dropdown from "bootstrap/js/dist/dropdown";
import ClipboardJS from "clipboard";

const radar = document.querySelector("#radar-menu");
if (radar) {
  const quote = (text) => `'${text.replaceAll("'", `'\\''`)}'`;
  let cursor = new DOMRect();
  let command = "";
  const menu = new Dropdown(radar.querySelector("[data-bs-toggle]"), {
    reference: { getBoundingClientRect: () => cursor },
    // The cursor rect is in viewport coordinates.
    popperConfig: { strategy: "fixed" },
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

  document.addEventListener("contextmenu", (event) => {
    const selection = getSelection();
    const text = selection.toString().trim();
    const page = selection.anchorNode?.parentElement?.closest("[data-radar-file]");
    const line = text && page && sourceLine(selection.getRangeAt(0));
    if (!line) return;
    event.preventDefault();
    const { radarRepo, radarFile } = page.dataset;
    command = `pull cpull report ${quote(radarRepo)} ${quote(radarFile)} ${line} --source wiki --quote ${quote(text)}`;
    radar.querySelector("[data-radar-command]").textContent = command;
    cursor = new DOMRect(event.clientX, event.clientY, 0, 0);
    menu.show();
    menu.update();
  });

  new ClipboardJS("[data-radar-copy]", {
    text: (button) => (button.dataset.radarCopy === "note" ? `${command} --note ''` : command),
  }).on("success", () => menu.hide());
}
