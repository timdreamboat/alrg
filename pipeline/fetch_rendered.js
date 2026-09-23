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
// Usage:
//   PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers NODE_PATH=/opt/node22/lib/node_modules \
//     node fetch_rendered.js <url> [extraWaitMs]
//
// Prints rendered visible text (document.body.innerText, after attempting to
// dismiss a cookie-consent overlay if one is blocking the page) to stdout,
// or a one-line error to stderr with a non-zero exit code. Deliberately
// extracts innerText, not raw HTML, to keep output small and avoid the
// "page still navigating" errors seen when calling page.content() too early.

const { chromium } = require('playwright');

// Errors seen in practice (2026-09-22 validation run) that look like
// transient proxy/rate-limit churn rather than a real hard block — worth
// a couple of retries with backoff before giving up.
const RETRYABLE_ERROR_PATTERNS = [
  'ERR_TOO_MANY_RETRIES',
  'ERR_CONNECTION_RESET',
  'ERR_CONNECTION_CLOSED',
  'ERR_CONNECTION_REFUSED',
  'ERR_EMPTY_RESPONSE',
  'ERR_NETWORK_CHANGED',
  'ERR_ADDRESS_UNREACHABLE',
  'ERR_PROXY_CONNECTION_FAILED',
];

// Common consent-management-platform selectors, checked first (fast,
// precise), plus a text-based fallback for everything else. Order matters:
// most specific/common platforms first.
const CONSENT_SELECTORS = [
  '#onetrust-accept-btn-handler',
  '#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll',
  '#truste-consent-button',
  'button[data-testid="uc-accept-all-button"]',
  '.qc-cmp2-summary-buttons button[mode="primary"]',
];
const CONSENT_TEXT_PATTERN = /^(accept( all)?|agree|allow all|i agree|got it|ok|accept cookies)$/i;

function isRetryableError(message) {
  return RETRYABLE_ERROR_PATTERNS.some((pat) => message.includes(pat));
}

async function dismissConsentOverlay(page) {
  for (const selector of CONSENT_SELECTORS) {
    try {
      const el = page.locator(selector).first();
      if (await el.isVisible({ timeout: 1500 })) {
        await el.click({ timeout: 1500 });
        await page.waitForTimeout(800);
        return true;
      }
    } catch (_) {
      // selector not present or not clickable — try the next one
    }
  }
  try {
    const el = page.getByRole('button', { name: CONSENT_TEXT_PATTERN }).first();
    if (await el.isVisible({ timeout: 1500 })) {
      await el.click({ timeout: 1500 });
      await page.waitForTimeout(800);
      return true;
    }
  } catch (_) {
    // no matching button found — page likely has no consent overlay
  }
  return false;
}

async function gotoWithRetry(page, url, timeout) {
  const delaysMs = [0, 3000, 8000];
  let lastError = null;
  for (let attempt = 0; attempt < delaysMs.length; attempt++) {
    if (delaysMs[attempt] > 0) {
      console.error(`retrying navigation after ${delaysMs[attempt]}ms (attempt ${attempt + 1}/${delaysMs.length})`);
      await new Promise((r) => setTimeout(r, delaysMs[attempt]));
    }
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout });
      return;
    } catch (e) {
      lastError = e;
      if (!isRetryableError(e.message)) {
        console.error(`goto warning (non-retryable): ${e.message} — attempting to read whatever loaded anyway`);
        return;
      }
    }
  }
  console.error(`goto warning (gave up after retries): ${lastError.message} — attempting to read whatever loaded anyway`);
}

async function main() {
  const url = process.argv[2];
  const waitMs = parseInt(process.argv[3] || '4000', 10);
  if (!url) {
    console.error('usage: node fetch_rendered.js <url> [extraWaitMs]');
    process.exit(2);
  }

  // The sandbox's egress proxy status endpoint (see CLAUDE.md/pipeline
  // notes) reports its own port, which varies between sandbox instances —
  // always prefer the env var; the hardcoded fallback is a last resort.
  const proxyServer = process.env.HTTPS_PROXY || process.env.HTTP_PROXY || 'http://127.0.0.1:37265';

  const browser = await chromium.launch({
    headless: true,
    proxy: { server: proxyServer },
    // ignoreHTTPSErrors on the context isn't enough for some domains
    // (seen on applebees.com — ERR_CERT_AUTHORITY_INVALID persisted even
    // with the context option set); this launch flag covers it at the
    // Chromium-process level instead.
    args: ['--ignore-certificate-errors'],
  });

  try {
    const context = await browser.newContext({
      ignoreHTTPSErrors: true,
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
    });
    const page = await context.newPage();

    await gotoWithRetry(page, url, 45000);

    // SPAs keep background XHR/analytics alive indefinitely, so waiting for
    // 'networkidle' usually times out even after the real content is
    // present. A fixed settle window after domcontentloaded is more
    // reliable than chasing networkidle.
    await page.waitForTimeout(waitMs);

    const dismissed = await dismissConsentOverlay(page);
    if (dismissed) {
      console.error('dismissed a cookie-consent overlay, re-reading page content');
      await page.waitForTimeout(Math.min(waitMs, 3000));
    }

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
