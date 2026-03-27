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

const url = "http://localhost:3000/tree_report.html";

const chrome = await chromeLauncher.launch({
  chromeFlags: ["--headless", "--no-sandbox"],
});

try {
  const result = await lighthouse(url, {
    port: chrome.port,
    preset: "desktop",
    onlyCategories: ["performance", "accessibility", "best-practices"],
    output: ["html", "json"],
  });

  fs.writeFileSync("lighthouse-result.html", result.report[0]);
  fs.writeFileSync("lighthouse-result.json", result.report[1]);

  // Print scores
  const cats = result.lhr.categories;
  for (const [key, val] of Object.entries(cats)) {
    console.log(`${val.title}: ${(val.score * 100).toFixed(0)}/100`);
  }
  console.log("\nReport saved to lighthouse-result.html");
} finally {
  try {
    await chrome.kill();
  } catch {}
}
