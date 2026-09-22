#!/usr/bin/env node
// Render a JS-heavy page (React/SPA allergen/nutrition tools) and print its
// visible text to stdout. Built for ALRG's cloud Routine sandbox, which has
// Chromium + Playwright preinstalled at /opt/pw-browsers but does NOT route
// Playwright through the sandbox's egress proxy by default the way curl/
// WebFetch do — that mismatch (not a missing tool) is why raw WebFetch/curl
// see only an empty app shell on chains like McDonald's, Starbucks, Taco
// Bell, Burger King, Chick-fil-A, etc. This script fixes that by pointing
// Chromium explicitly at the proxy and trusting its MITM cert.
//
// Usage: node fetch_rendered.js <url> [waitMs]
//   PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers node fetch_rendered.js <url>
//
// Prints rendered visible text (document.body.innerText) to stdout, or a
// one-line error to stderr with a non-zero exit code. Deliberately extracts
// innerText, not raw HTML, to keep output small and avoid the "page still
// navigating" errors seen when calling page.content() too early.

const { chromium } = require('playwright');

async function main() {
  const url = process.argv[2];
  const waitMs = parseInt(process.argv[3] || '4000', 10);
  if (!url) {
    console.error('usage: node fetch_rendered.js <url> [extraWaitMs]');
    process.exit(2);
  }

  // The sandbox's egress proxy status endpoint (see CLAUDE.md/pipeline
  // notes) reports its own port; default to the value seen in practice.
  // If HTTPS_PROXY/HTTP_PROXY is set in the environment, prefer that.
  const proxyServer = process.env.HTTPS_PROXY || process.env.HTTP_PROXY || 'http://127.0.0.1:37265';

  const browser = await chromium.launch({
    headless: true,
    proxy: { server: proxyServer },
  });

  try {
    const context = await browser.newContext({
      ignoreHTTPSErrors: true,
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
    });
    const page = await context.newPage();

    try {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
    } catch (e) {
      console.error(`goto warning: ${e.message} — attempting to read whatever loaded anyway`);
    }

    // SPAs keep background XHR/analytics alive indefinitely, so waiting for
    // 'networkidle' usually times out even after the real content is
    // present. A fixed settle window after domcontentloaded is more
    // reliable than chasing networkidle.
    await page.waitForTimeout(waitMs);

    const text = await page.evaluate(() => document.body ? document.body.innerText : '');
    if (!text || text.trim().length < 20) {
      console.error('warning: page rendered but visible text is empty/near-empty — likely still blocked or needs a longer wait');
    }
    process.stdout.write(text || '');
  } finally {
    await browser.close();
  }
}

main().catch((e) => {
  console.error(`fatal: ${e.message}`);
  process.exit(1);
});
