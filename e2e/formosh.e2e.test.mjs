import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import puppeteer from "puppeteer-core";
import { startServer } from "./server.mjs";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("..", import.meta.url));
const SCHEMA = JSON.stringify({
  type: "object",
  properties: { name: { type: "string", title: "Name" } },
  required: ["name"],
});

let browser;
let page;
let srv;
const consoleErrors = [];

before(async () => {
  srv = await startServer(ROOT);
  browser = await puppeteer.launch({
    executablePath: process.env.CHROME_PATH ?? "/usr/bin/google-chrome",
    headless: "new",
    args: ["--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"],
  });
  page = await browser.newPage();
  page.on("console", (m) => {
    if (m.type() === "error") consoleErrors.push(m.text());
  });
  await page.goto(`http://127.0.0.1:${srv.port}/`);
  await page.waitForFunction(() => window.__ready === true);
});

after(async () => {
  await browser?.close();
  srv?.server.close();
});

async function lastEvent(name, minCount = 1) {
  await page.waitForFunction(
    (n, c) => window.__events.filter((e) => e.name === n).length >= c,
    { timeout: 10_000 },
    name,
    minCount,
  );
  return page.evaluate(
    (n) => window.__events.filter((e) => e.name === n).at(-1),
    name,
  );
}

function shadowEval(fn, ...args) {
  return page.evaluate(fn, ...args);
}

test("mount renders fields and signals ready", async () => {
  await page.evaluate((s) => {
    window.__reset();
    window.__setSchema(s);
  }, SCHEMA);
  await lastEvent("formosh-ready");
  const inputCount = await shadowEval(
    () =>
      document
        .querySelector("formosh-form")
        .shadowRoot.querySelectorAll("input").length,
  );
  assert.ok(inputCount >= 1, "expected at least one rendered input");
});

async function typeInto(value) {
  await page.evaluate(() => {
    document.querySelector("formosh-form").shadowRoot.querySelector("input")
      .focus();
  });
  await page.keyboard.type(value);
}

// Wait for the named field to be present *and* reset to its fresh (empty)
// value before typing into it. "formosh-ready" fires as part of the update
// that commits a reinitialized model; the shadow-DOM patch (including
// clearing a previous test's leftover value on a same-named field, or
// swapping in a differently-named one) lands a tick later. Typing right
// after the ready event can land on a stale, not-yet-cleared input —
// observed concretely twice: a same-named "name" field still holding the
// prior test's "Ada" produced a doubled "AdaAda" value, and a differently
// -named leftover field ("email", from a schema swap) silently absorbed the
// keystrokes into a field the current model no longer has.
async function waitForField(name) {
  await page.waitForFunction(
    (n) => {
      const input = document
        .querySelector("formosh-form")
        .shadowRoot.querySelector(`input[name="${n}"]`);
      return input && input.value === "";
    },
    {},
    name,
  );
}

test("typing surfaces in formosh-change detail.values", async () => {
  await page.evaluate((s) => {
    window.__reset();
    window.__setSchema(s);
  }, SCHEMA);
  await lastEvent("formosh-ready");
  await waitForField("name");
  await typeInto("Ada");
  await page.waitForFunction(() =>
    window.__events.some(
      (e) => e.name === "formosh-change" && e.detail?.values?.name === "Ada",
    ),
  );
  const change = await lastEvent("formosh-change");
  assert.equal(typeof change.detail.isValid, "boolean");
  assert.equal(typeof change.detail.isDirty, "boolean");
});

test("invalid schema attribute keeps the previous form", async () => {
  await page.evaluate((s) => {
    window.__reset();
    window.__setSchema(s);
  }, SCHEMA);
  await lastEvent("formosh-ready");
  const errorsBefore = consoleErrors.length;
  await page.evaluate(() => window.__setSchema("{not json"));
  // the rejected attribute produces no event — wait for the logged error
  for (let i = 0; i < 20 && consoleErrors.length === errorsBefore; i++) {
    await new Promise((r) => setTimeout(r, 100));
  }
  const inputCount = await page.evaluate(
    () =>
      document
        .querySelector("formosh-form")
        .shadowRoot.querySelectorAll("input").length,
  );
  assert.ok(inputCount >= 1, "previous form should survive a bad schema");
  assert.ok(
    consoleErrors.length > errorsBefore,
    "a parse error should be logged",
  );
});

test("runtime schema swap reinitializes the form", async () => {
  await page.evaluate((s) => {
    window.__reset();
    window.__setSchema(s);
  }, SCHEMA);
  await lastEvent("formosh-ready");
  const swapped = JSON.stringify({
    type: "object",
    properties: { email: { type: "string", title: "Email" } },
  });
  await page.evaluate((s) => window.__setSchema(s), swapped);
  await lastEvent("formosh-ready", 2);
  // The "formosh-ready" event fires as part of the update that commits the
  // new model; the shadow-DOM patch lands a tick later, so poll instead of
  // reading the labels synchronously right after the event (observed as a
  // real race).
  await page.waitForFunction(() =>
    [...document
      .querySelector("formosh-form")
      .shadowRoot.querySelectorAll("label")].some((l) =>
      l.textContent.includes("Email"),
    ),
  );
  const labels = await page.evaluate(() =>
    [...document
      .querySelector("formosh-form")
      .shadowRoot.querySelectorAll("label")].map((l) => l.textContent),
  );
  assert.ok(labels.some((t) => t.includes("Email")));
});

test("read-only toggle preserves entered values", async () => {
  await page.evaluate((s) => {
    window.__reset();
    window.__setSchema(s);
  }, SCHEMA);
  await lastEvent("formosh-ready");
  // The previous test left the "email" schema rendered — without waitForField,
  // typeInto could grab the still-present, now-orphaned `email` input instead
  // of the fresh `name` one (observed: shadowRoot still showed
  // `{"labels":["Email"],"inputs":[{"name":"email"}]}` right after the ready
  // event, and typing into it produced formosh-change events with an empty
  // `values: {}`).
  await waitForField("name");
  await typeInto("Ada");
  // Confirm the typed value actually landed in the model before flipping
  // read-only — unlike the submit scenarios (gated on the submit button's
  // disabled state, which implies validation already ran against the typed
  // value), toggling read-only has no such incidental sync point.
  await page.waitForFunction(() =>
    window.__events.some(
      (e) => e.name === "formosh-change" && e.detail?.values?.name === "Ada",
    ),
  );
  await page.evaluate(() =>
    document.querySelector("formosh-form").setAttribute("read-only", "true"),
  );
  await page.waitForFunction(() =>
    document
      .querySelector("formosh-form")
      .shadowRoot.querySelector('[part="readonly-value"]'),
  );
  const text = await page.evaluate(
    () =>
      document
        .querySelector("formosh-form")
        .shadowRoot.querySelector('[part="readonly-value"]').textContent,
  );
  assert.ok(text.includes("Ada"));
  await page.evaluate(() =>
    document.querySelector("formosh-form").setAttribute("read-only", "false"),
  );
  // Wait for the form to actually re-render editable inputs before the next
  // test runs — component `read_only` is independent Model state that
  // persists across schema swaps (it is not reset by `SchemaChanged`), so a
  // fire-and-forget toggle here leaks read-only mode into later tests
  // (observed as a real race).
  await page.waitForFunction(() =>
    document
      .querySelector("formosh-form")
      .shadowRoot.querySelector("input"),
  );
});

test("submit success round-trip", async () => {
  await page.evaluate(
    (s, url) => {
      window.__reset();
      const form = document.querySelector("formosh-form");
      form.setAttribute("submit-url", url);
      window.__setSchema(s);
    },
    SCHEMA,
    `http://127.0.0.1:${srv.port}/submit`,
  );
  await lastEvent("formosh-ready");
  await waitForField("name");
  await typeInto("Ada");
  await page.waitForFunction(() => {
    const btn = document
      .querySelector("formosh-form")
      .shadowRoot.querySelector('[part="submit"]');
    return btn && !btn.disabled;
  });
  await page.evaluate(() =>
    document
      .querySelector("formosh-form")
      .shadowRoot.querySelector('[part="submit"]')
      .click(),
  );
  await lastEvent("formosh-submitting");
  const submit = await lastEvent("formosh-submit");
  assert.equal(submit.detail.status, "success");
  assert.ok(srv.received.length >= 1, "server should have received a body");
  assert.equal(srv.received.at(-1).name, "Ada");
});

test("validator JS property patches without reinit and blocks submit", async () => {
  await page.evaluate((s) => {
    window.__reset();
    window.__setSchema(s);
  }, SCHEMA);
  await lastEvent("formosh-ready");
  await waitForField("name");
  await typeInto("Ada");
  await page.waitForFunction(() =>
    window.__events.some(
      (e) => e.name === "formosh-change" && e.detail?.values?.name === "Ada",
    ),
  );
  await page.evaluate(() => {
    // cross_validator.decode_errors decodes `{path: string, message, rule?}`
    // (dot-notation path string, e.g. "name" or "items.[0].title") — not a
    // `field` array. A `field` key is silently dropped as a malformed item
    // (observed: "formosh: dropping malformed validator error" on console.error).
    document.querySelector("formosh-form").validator = () => [
      { path: "name", message: "rejected by validator", rule: "custom" },
    ];
  });
  await page.waitForFunction(() => {
    const btn = document
      .querySelector("formosh-form")
      .shadowRoot.querySelector('[part="submit"]');
    return btn && btn.disabled;
  });
  const value = await page.evaluate(
    () =>
      document
        .querySelector("formosh-form")
        .shadowRoot.querySelector("input").value,
  );
  assert.equal(value, "Ada", "validator patch must not reinitialize the form");
  await page.evaluate(() => {
    document.querySelector("formosh-form").validator = () => [];
  });
});

test("submit failure reports the error shape", async () => {
  await page.evaluate(
    (s, url) => {
      window.__reset();
      const form = document.querySelector("formosh-form");
      form.setAttribute("submit-url", url);
      window.__setSchema(s);
    },
    SCHEMA,
    `http://127.0.0.1:${srv.port}/submit-fail`,
  );
  await lastEvent("formosh-ready");
  await waitForField("name");
  await typeInto("Bob");
  await page.waitForFunction(() => {
    const btn = document
      .querySelector("formosh-form")
      .shadowRoot.querySelector('[part="submit"]');
    return btn && !btn.disabled;
  });
  await page.evaluate(() =>
    document
      .querySelector("formosh-form")
      .shadowRoot.querySelector('[part="submit"]')
      .click(),
  );
  const submit = await lastEvent("formosh-submit");
  assert.equal(submit.detail.status, "error");
  assert.equal(typeof submit.detail.error, "string");
});
