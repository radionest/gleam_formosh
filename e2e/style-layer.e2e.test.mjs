// Browser checks for formosh's stylesheet layer (spec: style-layer). Kept
// apart from formosh.e2e.test.mjs: these tests inject page stylesheets,
// emulate media features and mount extra <formosh-form> elements, none of
// which may leak into that file's shared page.
import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import puppeteer from "puppeteer-core";
import { startServer } from "./server.mjs";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("..", import.meta.url));

let browser;
let page;
let srv;

before(async () => {
  srv = await startServer(ROOT);
  browser = await puppeteer.launch({
    executablePath: process.env.CHROME_PATH ?? "/usr/bin/google-chrome",
    headless: "new",
    args: ["--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"],
  });
  page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${srv.port}/`);
  await page.waitForFunction(() => window.__ready === true);
});

after(async () => {
  await browser?.close();
  srv?.server.close();
});

const ROW_SCHEMA = JSON.stringify({
  type: "object",
  properties: {
    a: { type: "string", title: "A" },
    b: { type: "string", title: "B" },
    c: { type: "string", title: "C" },
  },
});
const ROW_UI = JSON.stringify({
  "ui:layout": [{ type: "Row", elements: ["a", "b", "c"] }],
});

const LONG = "An answer option far wider than any column of a narrow form row";
const SELECT_SCHEMA = JSON.stringify({
  type: "object",
  properties: {
    // More than five options renders a <select>.
    pick: {
      type: "string",
      title: "Pick",
      enum: [1, 2, 3, 4, 5, 6].map((n) => `${LONG} ${n}`),
    },
    note: { type: "string", title: "Note" },
  },
});
const SELECT_UI = JSON.stringify({
  "ui:layout": [{ type: "Row", elements: ["pick", "note"] }],
});

const FOLD_SCHEMA = JSON.stringify({
  type: "object",
  properties: {
    visits: {
      type: "array",
      title: "Visits",
      items: {
        type: "object",
        properties: { note: { type: "string", title: "Note" } },
        required: ["note"],
      },
    },
  },
});
const FOLD_UI = JSON.stringify({
  visits: { "ui:options": { collapseCompleted: true } },
});
// Row 0 complete (folds), row 1 missing its required note (stays open).
const FOLD_VALUES = JSON.stringify({ visits: [{ note: "seen" }, {}] });

// Mounts a schema on the harness's shared #form, `width` px wide, and waits
// until its shadow root matches `readySelector`. The form patches a tick
// after `formosh-ready`, so the selector must be specific to this schema.
// Resetting cssText also drops any token a previous test set on the host.
async function mount({ schema, uiSchema, initialValues, width, readySelector }) {
  await page.evaluate(
    (s, u, v, w) => {
      const form = document.getElementById("form");
      form.style.cssText = `display:block;width:${w}px`;
      form.setAttribute("ui-schema", u);
      if (v) form.setAttribute("initial-values", v);
      else form.removeAttribute("initial-values");
      form.setAttribute("schema", s);
    },
    schema,
    uiSchema,
    initialValues ?? null,
    width,
  );
  await page.waitForFunction(
    (sel) => document.getElementById("form").shadowRoot?.querySelector(sel),
    {},
    readySelector,
  );
}

async function rowMetrics() {
  return page.evaluate(() => {
    const row = document
      .getElementById("form")
      .shadowRoot.querySelector("[part~=row]");
    return {
      display: getComputedStyle(row).display,
      tops: [...row.children].map((c) =>
        Math.round(c.getBoundingClientRect().top),
      ),
      gap: getComputedStyle(row).columnGap,
    };
  });
}

// Lustre copies page stylesheets once, right after a component is created
// (if it is in the document by then), so a rule added after #form was created
// never reaches it. Inject `css`, mount a fresh form — created and appended in
// one task, so the copy sees it — wait up to 5s for its Row's first column to
// become `expected`, clean up,
// and return what the column resolved to — the caller's assertion reports a
// mismatch with the real value.
async function firstColumnWithPageCss(css, expected) {
  await page.evaluate(
    (rule, schema, ui) => {
      const style = document.createElement("style");
      style.id = "consumer-css";
      style.textContent = rule;
      document.head.append(style);
      const form = document.createElement("formosh-form");
      form.id = "fresh-form";
      form.style.cssText = "display:block;width:900px";
      form.setAttribute("ui-schema", ui);
      form.setAttribute("schema", schema);
      document.body.append(form);
    },
    css,
    ROW_SCHEMA,
    ROW_UI,
  );
  const firstColumn = () => {
    const row = document
      .getElementById("fresh-form")
      .shadowRoot?.querySelector("[part~=row]");
    return row ? getComputedStyle(row).gridTemplateColumns.split(" ")[0] : "";
  };
  await page
    .waitForFunction(
      (want) => {
        const row = document
          .getElementById("fresh-form")
          .shadowRoot?.querySelector("[part~=row]");
        return (
          !!row && getComputedStyle(row).gridTemplateColumns.split(" ")[0] === want
        );
      },
      { timeout: 5000 },
      expected,
    )
    .catch(() => {}); // the caller's assertion reports the resolved value
  const first = await page.evaluate(firstColumn);
  await page.evaluate(() => {
    document.getElementById("fresh-form")?.remove();
    document.getElementById("consumer-css")?.remove();
  });
  return first;
}

test("a Row is a grid with no page CSS and keeps three fields on one line", async () => {
  await mount({
    schema: ROW_SCHEMA,
    uiSchema: ROW_UI,
    width: 900,
    readySelector: '[part~=row] > [data-name="c"]',
  });
  const { display, tops, gap } = await rowMetrics();
  assert.equal(display, "grid");
  assert.equal(new Set(tops).size, 1, `expected one line, got tops ${tops}`);
  assert.equal(gap, "16px");
  await page.evaluate(() =>
    document.getElementById("form").style.setProperty("--formosh-row-gap", "6px"),
  );
  assert.equal((await rowMetrics()).gap, "6px");
});

test("--formosh-row-min lets three fields share a 320px Row", async () => {
  await mount({
    schema: ROW_SCHEMA,
    uiSchema: ROW_UI,
    width: 320,
    readySelector: '[part~=row] > [data-name="c"]',
  });
  const stacked = await rowMetrics();
  assert.equal(
    new Set(stacked.tops).size,
    3,
    "control: the 12rem default stacks three fields at 320px",
  );
  await page.evaluate(() =>
    document
      .getElementById("form")
      .style.setProperty("--formosh-row-min", "4rem"),
  );
  const tuned = await rowMetrics();
  assert.equal(
    new Set(tuned.tops).size,
    1,
    `expected one line, got tops ${tuned.tops}`,
  );
});

test("an adopted page rule overrides the Row grid without !important", async () => {
  const first = await firstColumnWithPageCss(
    '[part="row"] { grid-template-columns: 4.5rem 1fr; }',
    "72px",
  );
  assert.equal(first, "72px");
});

test("a layered page rule overrides the Row grid", async () => {
  // clarinet's main.css declares its own layers; `formosh` is declared first
  // in the shadow tree, so a consumer layer still wins.
  const first = await firstColumnWithPageCss(
    '@layer app { [part="row"] { grid-template-columns: 5rem 1fr; } }',
    "80px",
  );
  assert.equal(first, "80px");
});

test("an fr-track override keeps a wide <select> cell inside the Row", async () => {
  await mount({
    schema: SELECT_SCHEMA,
    uiSchema: SELECT_UI,
    width: 500,
    readySelector: "[part~=row] select",
  });
  // A host ::part() rule applies at once — no adoption involved.
  await page.evaluate(() => {
    const style = document.createElement("style");
    style.id = "consumer-fr";
    style.textContent = "#form::part(row) { grid-template-columns: 2fr 1fr; }";
    document.head.append(style);
  });
  const m = await page.evaluate(() => {
    const row = document
      .getElementById("form")
      .shadowRoot.querySelector("[part~=row]");
    const rowRight = row.getBoundingClientRect().right;
    const cells = [...row.children];
    return {
      columns: getComputedStyle(row).gridTemplateColumns,
      minWidth: getComputedStyle(cells[0]).minWidth,
      overflow: cells.map((c) =>
        Math.round(c.getBoundingClientRect().right - rowRight),
      ),
    };
  });
  await page.evaluate(() => document.getElementById("consumer-fr").remove());
  assert.equal(m.minWidth, "0px");
  for (const px of m.overflow) {
    assert.ok(px <= 0, `a cell ends ${px}px past the Row: ${m.overflow}`);
  }
  // The default grid also has two tracks at 500px, so only a 2:1 split proves
  // the override is in effect — without it this test guards nothing.
  const [first, second] = m.columns.split(" ").map(parseFloat);
  assert.ok(Math.abs(first - 2 * second) < 1, `2fr 1fr override not applied: ${m.columns}`);
});

test("a collapsed row folds to zero height; an open one does not", async () => {
  await mount({
    schema: FOLD_SCHEMA,
    uiSchema: FOLD_UI,
    initialValues: FOLD_VALUES,
    width: 600,
    readySelector: ".array-item[data-collapsed] > .array-item-body",
  });
  const h = await page.evaluate(() => {
    const root = document.getElementById("form").shadowRoot;
    const height = (sel) => root.querySelector(sel).getBoundingClientRect().height;
    return {
      folded: height(".array-item[data-collapsed] > .array-item-body"),
      open: height(".array-item:not([data-collapsed]) > .array-item-body"),
      styled: root.querySelectorAll(".array-item-body[style], .array-item-fields[style]").length,
      clip: getComputedStyle(root.querySelector(".array-item[data-collapsed] > .array-item-body")).overflow,
    };
  });
  assert.equal(h.folded, 0);
  assert.ok(h.open > 0, `open body height ${h.open}`);
  assert.equal(h.clip, "hidden");
  assert.equal(h.styled, 0, "folding elements must carry no inline style");
});

test("the fold follows its duration token and drops to 0s under reduced motion", async () => {
  await mount({
    schema: FOLD_SCHEMA,
    uiSchema: FOLD_UI,
    initialValues: FOLD_VALUES,
    width: 600,
    readySelector: ".array-item-body",
  });
  const duration = () =>
    page.evaluate(
      () =>
        getComputedStyle(
          document.getElementById("form").shadowRoot.querySelector(".array-item-body"),
        ).transitionDuration,
    );
  assert.equal(await duration(), "0.18s");
  await page.evaluate(() =>
    document
      .getElementById("form")
      .style.setProperty("--formosh-collapse-duration", "300ms"),
  );
  assert.equal(await duration(), "0.3s");
  await page.emulateMediaFeatures([
    { name: "prefers-reduced-motion", value: "reduce" },
  ]);
  try {
    assert.equal(await duration(), "0s");
  } finally {
    await page.emulateMediaFeatures([
      { name: "prefers-reduced-motion", value: "no-preference" },
    ]);
  }
});

test("the stylesheet node survives a re-render", async () => {
  await mount({
    schema: ROW_SCHEMA,
    uiSchema: ROW_UI,
    width: 900,
    readySelector: '[part~=row] > [data-name="c"]',
  });
  await page.evaluate(() => {
    window.__reset();
    const root = document.getElementById("form").shadowRoot;
    root.querySelector("[part=container] > style").dataset.e2eProbe = "kept";
    root.querySelector('input[name="a"]').focus();
  });
  await page.keyboard.type("x");
  await page.waitForFunction(() =>
    window.__events.some(
      (e) => e.name === "formosh-change" && e.detail?.values?.a === "x",
    ),
  );
  // Lustre patches on the next animation frame, after formosh-change fires; without this wait the probe reads the un-patched node.
  await page.evaluate(() => new Promise((r) => requestAnimationFrame(r)));
  const probe = await page.evaluate(
    () =>
      document
        .getElementById("form")
        .shadowRoot.querySelector("[part=container] > style").dataset.e2eProbe,
  );
  assert.equal(probe, "kept", "a re-created <style> re-parses the stylesheet on every render");
});
