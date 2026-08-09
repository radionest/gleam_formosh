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

// Wait for the named field to be present *and* holding `expected` (default:
// its fresh/empty value) before acting on it. "formosh-ready" fires as part
// of the update that commits a reinitialized model; the shadow-DOM patch
// (including clearing a previous test's leftover value on a same-named
// field, swapping in a differently-named one, or applying a schema
// `default`) lands a tick later. Acting right after the ready event can
// land on a stale input — observed concretely twice: a same-named "name"
// field still holding the prior test's "Ada" produced a doubled "AdaAda"
// value when typed into, and a differently-named leftover field ("email",
// from a schema swap) silently absorbed keystrokes into a field the
// current model no longer has.
async function waitForField(name, expected = "") {
  await page.waitForFunction(
    (n, v) => {
      const input = document
        .querySelector("formosh-form")
        .shadowRoot.querySelector(`input[name="${n}"]`);
      return input && input.value === v;
    },
    {},
    name,
    expected,
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

test("date and password formats render native input types and mask in read-only", async () => {
  const schema = JSON.stringify({
    type: "object",
    properties: {
      start_date: { type: "string", format: "date", title: "Start date" },
      secret: {
        type: "string",
        format: "password",
        title: "Secret",
        default: "hunter2",
      },
    },
  });
  await page.evaluate((s) => {
    window.__reset();
    window.__setSchema(s);
  }, schema);
  await lastEvent("formosh-ready");
  // The password field carries a schema `default` — wait for it to land
  // (same DOM-patch-lags-ready race documented on waitForField) before
  // reading input types off a possibly stale render.
  await waitForField("secret", "hunter2");

  const inputTypes = await shadowEval(() => {
    const root = document.querySelector("formosh-form").shadowRoot;
    return {
      date: root.querySelector('input[name="start_date"]').type,
      password: root.querySelector('input[name="secret"]').type,
    };
  });
  assert.equal(inputTypes.date, "date");
  assert.equal(inputTypes.password, "password");

  await page.evaluate(() =>
    document.querySelector("formosh-form").setAttribute("read-only", "true"),
  );
  await page.waitForFunction(() =>
    document
      .querySelector("formosh-form")
      .shadowRoot.querySelector('[part="readonly-value"]'),
  );
  const maskedText = await shadowEval(() => {
    const rows = [
      ...document
        .querySelector("formosh-form")
        .shadowRoot.querySelectorAll('[part="readonly-field"]'),
    ];
    const secretRow = rows.find((r) =>
      r
        .querySelector('[part="readonly-label"]')
        .textContent.includes("Secret"),
    );
    return secretRow.querySelector('[part="readonly-value"]').textContent;
  });
  assert.equal(maskedText, "••••••••");

  // Reset read-only so any test added after this one doesn't inherit the
  // state — matches the cleanup in "read-only toggle preserves entered
  // values".
  await page.evaluate(() =>
    document.querySelector("formosh-form").setAttribute("read-only", "false"),
  );
  await page.waitForFunction(() =>
    document.querySelector("formosh-form").shadowRoot.querySelector("input"),
  );
});

async function focusFieldInput(name) {
  await page.evaluate((n) => {
    document
      .querySelector("formosh-form")
      .shadowRoot.querySelector(`input[name="${n}"]`)
      .focus();
  }, name);
}

// The fold is a CSS transition on `grid-template-rows`, which only runs if
// the element carries a previous computed value — a node inserted already at
// `0fr` snaps shut instead. The row's children are unkeyed, so this comes
// down to node identity: the summary occupies a slot in every state
// (`element.none()` when the row is incomplete) precisely so completing a
// row does not shift its siblings and force a rebuild.
//
// Only a real browser can see this. The string-render tests in
// `test/array_collapse_render_test.gleam` compare markup, and the markup is
// identical either way — what differs is whether the body survives the
// patch. Marking the node and re-reading the mark after the fold is the
// assertion those tests structurally cannot make.
test("completing a row folds the body node it already had", async () => {
  const schema = JSON.stringify({
    type: "object",
    properties: {
      visits: {
        type: "array",
        minItems: 1,
        title: "Visits",
        items: {
          type: "object",
          properties: { note: { type: "string", title: "Note" } },
          required: ["note"],
        },
      },
    },
  });
  const uiSchema = JSON.stringify({
    visits: { "ui:options": { collapseCompleted: true } },
  });
  await page.evaluate(
    (s, u) => {
      window.__reset();
      const form = document.querySelector("formosh-form");
      form.setAttribute("ui-schema", u);
      window.__setSchema(s);
    },
    schema,
    uiSchema,
  );
  await lastEvent("formosh-ready");

  // `minItems: 1` makes the reconcile top the array up to one row, which
  // starts expanded and incomplete.
  await page.waitForFunction(() => {
    const root = document.querySelector("formosh-form").shadowRoot;
    const body = root.querySelector(".array-item-body");
    return body && !root.querySelector(".array-item[data-collapsed]");
  });
  await page.evaluate(() => {
    document
      .querySelector("formosh-form")
      .shadowRoot.querySelector(".array-item-body").dataset.e2eProbe = "kept";
  });

  // Filling the row's only required field completes it, which folds it
  // automatically — the exact moment the old code rebuilt the body.
  await page.evaluate(() => {
    document
      .querySelector("formosh-form")
      .shadowRoot.querySelector(".array-item-body input")
      .focus();
  });
  await page.keyboard.type("seen");
  await page.waitForFunction(() =>
    document
      .querySelector("formosh-form")
      .shadowRoot.querySelector(".array-item[data-collapsed]"),
  );

  const probe = await shadowEval(
    () =>
      document
        .querySelector("formosh-form")
        .shadowRoot.querySelector(".array-item-body").dataset.e2eProbe,
  );
  assert.equal(
    probe,
    "kept",
    "the collapsed row must fold the body element it already had; a replaced node has no value to transition from",
  );

  // Clean up so the shared page carries no collapse-enabled array into the
  // date/time test that follows.
  await page.evaluate(() => {
    document.querySelector("formosh-form").removeAttribute("ui-schema");
  });
});

// Formosh inputs are fully controlled (field_common.input_attributes sets
// both `value` and `on_input`), so every keystroke round-trips through the
// model and back into the element. A native date/time control fires `input`
// with value === "" whenever its segments are incomplete, which risks the
// model clearing mid-edit and the controlled re-render fighting the user's
// typing. This test drives real keystrokes (not `.value` assignment, which
// would bypass `input` entirely) to pin down what actually happens.
//
// Last in file order: it is the only test that types into a fresh "date"
// input and leaves nothing behind to guard against.
test("native date/time inputs round-trip typed values without clobbering", async () => {
  const schema = JSON.stringify({
    type: "object",
    properties: {
      start_date: { type: "string", format: "date", title: "Start date" },
      start_time: { type: "string", format: "time", title: "Start time" },
    },
  });
  await page.evaluate((s) => {
    window.__reset();
    window.__setSchema(s);
  }, schema);
  await lastEvent("formosh-ready");
  // "start_date" reuses a field name from the previous test, but
  // "start_time" does not — waiting for it existing rules out acting on a
  // stale render still holding the previous test's schema (the same race
  // documented on waitForField above).
  await page.waitForFunction(() =>
    document
      .querySelector("formosh-form")
      .shadowRoot.querySelector('input[name="start_time"]'),
  );
  await waitForField("start_date");

  // --- date: type a complete value via real keystrokes ---
  // The en-US date control's segments are month/day/year and auto-advance
  // as each segment fills, so typing all 8 digits with no separators lands
  // month=06, day=15, year=2026 in one continuous keystroke run.
  await focusFieldInput("start_date");
  await page.keyboard.type("06152026");
  await page.waitForFunction(() =>
    window.__events.some(
      (e) =>
        e.name === "formosh-change" &&
        e.detail?.values?.start_date === "2026-06-15",
    ),
  );
  const dateAfterType = await shadowEval(
    () =>
      document
        .querySelector("formosh-form")
        .shadowRoot.querySelector('input[name="start_date"]').value,
  );
  assert.equal(
    dateAfterType,
    "2026-06-15",
    "the controlled round-trip must not clobber the typed date",
  );

  // --- date: clear it and confirm the model reflects the cleared state ---
  // A native date control has no single key that empties every segment at
  // once — select-all + delete is how a user actually clears it.
  await page.keyboard.down("Control");
  await page.keyboard.press("KeyA");
  await page.keyboard.up("Control");
  await page.keyboard.press("Delete");
  await page.waitForFunction(() =>
    window.__events.some(
      (e) =>
        e.name === "formosh-change" && e.detail?.values?.start_date === "",
    ),
  );
  const dateAfterClear = await shadowEval(
    () =>
      document
        .querySelector("formosh-form")
        .shadowRoot.querySelector('input[name="start_date"]').value,
  );
  assert.equal(
    dateAfterClear,
    "",
    "the cleared date must show empty in the element too",
  );

  // --- time: same round-trip shape, kept in this test since it is cheap
  // and has shown no extra flakiness (verified over repeated local runs) ---
  await focusFieldInput("start_time");
  await page.keyboard.type("0130PM");
  await page.waitForFunction(() =>
    window.__events.some(
      (e) =>
        e.name === "formosh-change" &&
        e.detail?.values?.start_time === "13:30",
    ),
  );
  const timeAfterType = await shadowEval(
    () =>
      document
        .querySelector("formosh-form")
        .shadowRoot.querySelector('input[name="start_time"]').value,
  );
  assert.equal(
    timeAfterType,
    "13:30",
    "the controlled round-trip must not clobber the typed time",
  );

  await page.keyboard.down("Control");
  await page.keyboard.press("KeyA");
  await page.keyboard.up("Control");
  await page.keyboard.press("Delete");
  await page.waitForFunction(() =>
    window.__events.some(
      (e) =>
        e.name === "formosh-change" && e.detail?.values?.start_time === "",
    ),
  );
  const timeAfterClear = await shadowEval(
    () =>
      document
        .querySelector("formosh-form")
        .shadowRoot.querySelector('input[name="start_time"]').value,
  );
  assert.equal(
    timeAfterClear,
    "",
    "the cleared time must show empty in the element too",
  );
});
