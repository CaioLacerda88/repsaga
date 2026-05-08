import { test, expect, Page, BrowserContext } from '@playwright/test';
import { WORKOUT } from '../helpers/selectors';
import { login } from '../helpers/auth';
import { startEmptyWorkout, addExercise, setWeight } from '../helpers/workout';
import { getUser } from '../fixtures/worker-users';

const RUN = process.env.VERIFY_WEIGHT === '1';
const VIEWPORT = { width: 360, height: 780 };

test.describe('Verify weight helper', () => {
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

  test('setWeight helper sets weight to 80kg', async () => {
    await setWeight(page, '80');
    await page.waitForTimeout(500);
    
    // Take screenshot to visually verify
    await page.screenshot({ path: 'C:/Users/caiol/Projects/repsaga/tasks/active-workout-findings/screenshots/charter-A-BR-1-weight-80.png' });
    
    // Dump all semantics to see weight
    const allSemantics = await page.evaluate(() => {
      const els = document.querySelectorAll('flt-semantics');
      const labels: string[] = [];
      els.forEach((el: Element) => {
        const label = (el as any).ariaLabel ?? el.getAttribute('aria-label') ?? '';
        const id = el.getAttribute('flt-semantics-identifier') ?? '';
        if (label || id) labels.push(`[${el.getAttribute('role')}/${id}] ${label.slice(0, 80)}`);
      });
      return labels;
    });
    console.log('All semantics after weight set:');
    allSemantics.forEach(s => console.log('  ' + s));
    
    // Explicitly check what the Weight value button shows
    const weightBtns = page.locator('role=button[name*="Weight value"]');
    const count = await weightBtns.count();
    console.log(`Weight value buttons: ${count}`);
    for (let i = 0; i < count; i++) {
      const box = await weightBtns.nth(i).boundingBox();
      console.log(`  btn[${i}]: box=${JSON.stringify(box)}`);
    }
  });
});
