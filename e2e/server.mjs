import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";

const MIME = {
  ".html": "text/html",
  ".mjs": "text/javascript",
  ".js": "text/javascript",
  ".json": "application/json",
};

export function startServer(rootDir) {
  const received = [];
  const server = createServer(async (req, res) => {
    if (req.method === "POST" && req.url === "/submit") {
      let body = "";
      for await (const chunk of req) body += chunk;
      received.push(JSON.parse(body));
      res.writeHead(200, { "content-type": "application/json" });
      res.end('{"ok":true}');
      return;
    }
    if (req.method === "POST" && req.url === "/submit-fail") {
      res.writeHead(500, { "content-type": "text/plain" });
      res.end("boom");
      return;
    }
    try {
      const path = req.url === "/" ? "/e2e/harness.html" : req.url;
      const data = await readFile(join(rootDir, normalize(path)));
      res.writeHead(200, {
        "content-type": MIME[extname(path)] ?? "application/octet-stream",
      });
      res.end(data);
    } catch {
      res.writeHead(404);
      res.end();
    }
  });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () =>
      resolve({ server, received, port: server.address().port }),
    );
  });
}
