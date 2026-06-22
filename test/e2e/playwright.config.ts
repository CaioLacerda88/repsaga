import { defineConfig } from '@playwright/test';
import dotenv from 'dotenv';
import path from 'path';
import { WORKERS_COUNT } from './fixtures/worker-users';

// Load .env.local so FLUTTER_APP_URL and Supabase credentials are available
// to both the config and the global setup/teardown scripts.
dotenv.config({ path: path.join(__dirname, '.env.local') });

// In CI, FLUTTER_APP_URL is set by the workflow before Playwright runs.
// Locally, Playwright auto-starts the server on LOCAL_PORT using the
// pre-built web assets in ../../build/web.
const appUrl = process.env['FLUTTER_APP_URL'];
const LOCAL_PORT = 4200;

export default defineConfig({
  testDir: '.',
  timeout: 60_000,
  retries: 1,
  // Phase 21: per-worker user pool (see fixtures/worker-users.ts) eliminates
  // concurrent races on shared user state, so we can run workers = vCPU on
  // CI (4 on GitHub Actions Linux runners). PR #156 also raised the local
  // Supabase `sign_in_sign_ups` rate limit so 4 concurrent workers don't
  // saturate the per-IP auth bucket. The same constant drives
  // `global-setup.ts`'s per-worker user creation loop, so both stay in sync
  // automatically.
  workers: WORKERS_COUNT,
  // fullyParallel intentionally left at the Playwright default (false).
  // Tests within the same spec file still run sequentially. Within-file
  // parallelism is a separate optimization that requires per-test isolation
  // we don't yet have (e.g., a single user finishing a workout invalidates
  // shared XP state observed by the next test). Keeping this conservative
  // until per-test isolation is proven across the suite.
  globalSetup: './global-setup.ts',
  globalTeardown: './global-teardown.ts',
  use: {
    baseURL: appUrl || `http://localhost:${LOCAL_PORT}`,
    headless: true,
    screenshot: 'only-on-failure',
    trace: 'on-first-retry',
    launchOptions: {
      // Force Chromium to expose its accessibility tree in headless mode.
      // Flutter web detects an active accessibility tree and enables its
      // semantics layer (flt-semantics elements) automatically — without
      // needing the unreliable placeholder click + Tab workaround.
      args: ['--force-renderer-accessibility'],
    },
  },
  // Auto-start the web server for local dev.
  // CI sets FLUTTER_APP_URL and manages its own server — skip here.
  ...(appUrl
    ? {}
    : {
        webServer: {
          // Custom static server: serves dotfiles (.env for flutter_dotenv),
          // streams responses with backpressure, and handles SPA fallback.
          // Replaces npx http-server which crashed under concurrent Playwright load.
          command: `node static-server.cjs ../../build/web ${LOCAL_PORT}`,
          port: LOCAL_PORT,
          reuseExistingServer: true,
          timeout: 30_000,
        },
      }),
  // In CI, exclude the env-gated exploratory / charter specs from the
  // collection entirely so Playwright doesn't count their skipped tests when
  // distributing work across --shard=k/n shards. Each of these files guards
  // itself behind an env var that CI never sets (EXPL_CHARTER_A, EXPL_CHARTER_B,
  // etc.), so they produce 0 runnable tests in CI — but Playwright still assigns
  // them to a shard bucket, which skews the 3-way split heavily toward shard 1
  // (alphabetically first). Ignoring them in CI keeps the distribution even.
  // Locally (no CI env var), testIgnore is undefined and the files are visible
  // so developers can activate them via their respective env flags.
  ...(process.env['CI']
    ? {
        testIgnore: [
          // charter-a cluster
          '**/specs/charter-a-exploratory.spec.ts',
          '**/specs/charter-a-refined.spec.ts',
          '**/specs/charter-a-verify-weight.spec.ts',
          '**/specs/charter-a-weight-test.spec.ts',
          // charter-b cluster
          '**/specs/charter-b-exploratory.spec.ts',
          '**/specs/charter-b-followup.spec.ts',
          // charter-c cluster
          '**/specs/charter-c-exploratory.spec.ts',
          // generic exploratory driver
          '**/specs/exploratory.spec.ts',
        ],
      }
    : {}),
  projects: [
    {
      name: 'regression',
      testMatch: /specs\/.*\.spec\.ts$/,
      use: {
        actionTimeout: 15_000,
        navigationTimeout: 30_000,
      },
    },
  ],
});
