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
