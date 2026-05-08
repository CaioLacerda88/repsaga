// Quick weight dialog test
// Using the correct Flutter input pattern (no input.fill)

import { test, expect, Page, BrowserContext } from '@playwright/test';
import { WORKOUT } from '../helpers/selectors';
import { login } from '../helpers/auth';
import { startEmptyWorkout, addExercise } from '../helpers/workout';
import { getUser } from '../fixtures/worker-users';

const RUN = process.env.EXPL_WEIGHT_DIALOG === '1';
const VIEWPORT = { width: 360, height: 780 };

test.describe('Weight dialog edge cases', () => {
  test.skip(!RUN, 'Guard');
  test.use({ viewport: VIEWPORT });
  
  let page: Page;
  let context: BrowserContext;

  test.beforeAll(async ({ browser }) => {
    context = await browser.newContext({ viewport: VIEWPORT, deviceScaleFactor: 2.0, baseURL: 'http://127.0.0.1:4200' });
    page = await context.newPage();
    const user = getUser('fullWorkout');
    await login(page, user.email, user.password);
    await startEmptyWorkout(page);
    await addExercise(page, 'Barbell Bench Press');
  });

  test.afterAll(async () => { await context.close(); });

  async function openWeightDialog() {
    const btn = page.locator('role=button[name*="Weight value"]').last();
    await btn.click();
    await expect(page.locator('text="OK"')).toBeVisible({ timeout: 5000 });
    await page.waitForTimeout(300);
  }

  async function submitDialog() {
    await page.locator('text="OK"').click();
    await expect(page.locator('text="OK"')).not.toBeVisible({ timeout: 5000 });
  }

  test('weight dialog: 102.5 dot decimal', async () => {
    await openWeightDialog();
    await page.keyboard.press('Control+a');
    await page.keyboard.type('102.5', { delay: 10 });
    await page.waitForTimeout(200);
    const inputVal = await page.locator('input').last().inputValue().catch(() => 'n/a');
    console.log(`Input after typing 102.5: "${inputVal}"`);
    await submitDialog();
    
    // Read the weight value button to confirm
    const weightBtn = page.locator('role=button[name*="Weight value"]').last();
    const label = await weightBtn.getAttribute('aria-label').catch(() => 'n/a');
    const ariaLabel = await page.evaluate(() => {
      const btns = document.querySelectorAll('flt-semantics');
      const labels: string[] = [];
      btns.forEach(el => {
        const l = (el as any).ariaLabel ?? el.getAttribute('aria-label') ?? '';
        if (l.includes('Weight value')) labels.push(l);
      });
      return labels;
    });
    console.log(`Weight value after 102.5: ${JSON.stringify(ariaLabel)}`);
  });

  test('weight dialog: 102,5 comma decimal (BR)', async () => {
    await openWeightDialog();
    await page.keyboard.press('Control+a');
    await page.keyboard.type('102,5', { delay: 10 });
    await page.waitForTimeout(200);
    const inputVal = await page.locator('input').last().inputValue().catch(() => 'n/a');
    console.log(`Input after typing 102,5: "${inputVal}"`);
    await submitDialog();
    
    const ariaLabel = await page.evaluate(() => {
      const btns = document.querySelectorAll('flt-semantics');
      const labels: string[] = [];
      btns.forEach(el => {
        const l = (el as any).ariaLabel ?? el.getAttribute('aria-label') ?? '';
        if (l.includes('Weight value')) labels.push(l);
      });
      return labels;
    });
    console.log(`Weight value after 102,5: ${JSON.stringify(ariaLabel)}`);
  });

  test('weight dialog: empty submit', async () => {
    await openWeightDialog();
    await page.keyboard.press('Control+a');
    await page.keyboard.press('Backspace');
    await page.waitForTimeout(200);
    const inputVal = await page.locator('input').last().inputValue().catch(() => 'n/a');
    console.log(`Input after clear: "${inputVal}"`);
    await submitDialog();
    
    const ariaLabel = await page.evaluate(() => {
      const btns = document.querySelectorAll('flt-semantics');
      const labels: string[] = [];
      btns.forEach(el => {
        const l = (el as any).ariaLabel ?? el.getAttribute('aria-label') ?? '';
        if (l.includes('Weight value')) labels.push(l);
      });
      return labels;
    });
    console.log(`Weight value after empty submit: ${JSON.stringify(ariaLabel)}`);
  });

  test('weight dialog: -5 negative', async () => {
    await openWeightDialog();
    await page.keyboard.press('Control+a');
    await page.keyboard.type('-5', { delay: 10 });
    await page.waitForTimeout(200);
    const inputVal = await page.locator('input').last().inputValue().catch(() => 'n/a');
    console.log(`Input after -5: "${inputVal}"`);
    await submitDialog();
    
    const ariaLabel = await page.evaluate(() => {
      const btns = document.querySelectorAll('flt-semantics');
      const labels: string[] = [];
      btns.forEach(el => {
        const l = (el as any).ariaLabel ?? el.getAttribute('aria-label') ?? '';
        if (l.includes('Weight value')) labels.push(l);
      });
      return labels;
    });
    console.log(`Weight value after -5 submit: ${JSON.stringify(ariaLabel)}`);
  });

  test('weight dialog: alpha abc123def', async () => {
    await openWeightDialog();
    await page.keyboard.press('Control+a');
    await page.keyboard.type('abc123def', { delay: 10 });
    await page.waitForTimeout(200);
    const inputVal = await page.locator('input').last().inputValue().catch(() => 'n/a');
    console.log(`Input after abc123def: "${inputVal}"`);
    // Escape to cancel
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    console.log('Cancelled alpha dialog');
  });
});
