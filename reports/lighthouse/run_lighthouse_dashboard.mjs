import fs from "fs";
import { pathToFileURL } from "url";

const G = "C:/Users/Admin/AppData/Roaming/npm/node_modules";
const { default: lighthouse } = await import(
  pathToFileURL(`${G}/lighthouse/core/index.js`).href
);
const chromeLauncher = await import(
  pathToFileURL(
    `${G}/lighthouse/node_modules/chrome-launcher/dist/chrome-launcher.js`,
  ).href
);
const puppeteer = await import(
  pathToFileURL(
    `${G}/lighthouse/node_modules/puppeteer-core/lib/cjs/puppeteer/puppeteer-core.js`,
  ).href
);

const DASHBOARD_URL = "http://localhost:8000";

const chrome = await chromeLauncher.launch({
  chromeFlags: ["--headless", "--no-sandbox", "--disable-gpu"],
});

try {
  // Connect puppeteer to get a session cookie
  const browserURL = `http://127.0.0.1:${chrome.port}`;
  const browser = await puppeteer.default.connect({
    browserURL,
    defaultViewport: null,
  });

  const page = await browser.newPage();

  // Login to get session cookie
  await page.goto(`${DASHBOARD_URL}/login`, { waitUntil: "networkidle2" });
  await page.type('input[name="username"]', "admin");
  await page.type('input[name="password"]', "admin123");
  await page.click('button[type="submit"]');
  await page.waitForNavigation({ waitUntil: "networkidle2" });
  console.log("Logged in successfully, running Lighthouse...\n");

  // Get cookies for Lighthouse
  const cookies = await page.cookies();
  await page.close();

  // Run Lighthouse with the authenticated session
  const result = await lighthouse(DASHBOARD_URL + "/", {
    port: chrome.port,
    preset: "desktop",
    onlyCategories: ["performance", "accessibility", "best-practices", "seo"],
    output: ["html", "json"],
    // Pass cookies so Lighthouse is authenticated
    extraHeaders: {
      Cookie: cookies.map((c) => `${c.name}=${c.value}`).join("; "),
    },
  });

  const outDir = "testing";
  fs.writeFileSync(`${outDir}/dashboard-lighthouse.html`, result.report[0]);
  fs.writeFileSync(`${outDir}/dashboard-lighthouse.json`, result.report[1]);

  // Print scores
  const cats = result.lhr.categories;
  console.log("═══════════════════════════════════════════");
  console.log("  LIGHTHOUSE SCORES — Tree Manager Dashboard");
  console.log("═══════════════════════════════════════════");
  for (const [key, val] of Object.entries(cats)) {
    const score = (val.score * 100).toFixed(0);
    const bar =
      "█".repeat(Math.round(val.score * 20)) +
      "░".repeat(20 - Math.round(val.score * 20));
    console.log(`  ${val.title.padEnd(20)} ${bar} ${score}/100`);
  }

  // Print failed audits
  const audits = result.lhr.audits;
  console.log("\n─── FAILED / WARNING AUDITS ───");
  for (const [id, audit] of Object.entries(audits)) {
    if (
      audit.score !== null &&
      audit.score < 0.9 &&
      audit.scoreDisplayMode !== "notApplicable"
    ) {
      const score =
        audit.score !== null ? `${(audit.score * 100).toFixed(0)}` : "N/A";
      console.log(`  ⚠ [${score}] ${audit.title}`);
      if (audit.description) {
        const desc = audit.description.split(".")[0];
        if (desc.length < 120) console.log(`        ${desc}`);
      }
    }
  }

  console.log(`\nReports saved to ${outDir}/dashboard-lighthouse.html & .json`);
} finally {
  try {
    await chrome.kill();
  } catch {}
}
