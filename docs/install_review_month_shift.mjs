/**
 * The month under review is the PREVIOUS calendar month, not the current one.
 *
 *     node D:\Vistar\krafrontend\docs\install_review_month_shift.mjs --dry
 *     node D:\Vistar\krafrontend\docs\install_review_month_shift.mjs
 *
 * Idempotent; all-or-nothing; backs the file up as <name>.bak before writing.
 * `--kra=<dir>` patches a COPY of the dist tree so the result can be
 * syntax-checked before the deployed file is touched.
 *
 * ── THE BUG ─────────────────────────────────────────────────────────────────
 *
 * On 9 September 2026 the employee home screen said:
 *
 *     banner : "Sep '26 self-rating closes in 1 day"
 *     card   : "Sep-26 / Self-rating pending"
 *
 * August was what was actually owed. `GET /employee/dashboard` returns
 * `currentMonth`, and `findCurrentMonth()` picks the cycle month whose
 * year+month equal TODAY's:
 *
 *     const exact = months.find((m) =>
 *       m.monthDate.getUTCFullYear() === now.getUTCFullYear() &&
 *       m.monthDate.getUTCMonth()    === now.getUTCMonth());
 *
 * Through September that is September — a month with twenty days still to run
 * and therefore nothing anyone could rate.
 *
 * ── WHY THIS IS A DEFECT AND NOT A PREFERENCE ───────────────────────────────
 *
 * The deadline schedule already assumed the other answer. `ReviewStage`
 * puts self-rating on the **10th**. If the month under review were the current
 * one, that deadline would land with two-thirds of the month unfinished — you
 * would be marked overdue for failing to rate days that had not happened. The
 * schedule only makes sense as "the 10th of the month AFTER the review month",
 * which is exactly this change.
 *
 * ── WHAT CHANGES ────────────────────────────────────────────────────────────
 *
 * One function. `findCurrentMonth` matches the month BEFORE today's instead of
 * today's. Its two existing fallbacks — the last OPEN month, then the last
 * month of the cycle — are untouched, and they are what keep a cycle that has
 * not reached its second month working.
 *
 * `Date.UTC(y, m - 1, 1)` handles the January rollover on its own: month index
 * -1 resolves to December of the previous year. That is deliberate rather than
 * a hand-written branch, because a hand-written one is where this class of bug
 * usually reappears.
 *
 * ── WHAT DELIBERATELY DOES *NOT* CHANGE ─────────────────────────────────────
 *
 *   * The deadline days. They were always right; see above.
 *   * `monthLabel` generation in review-cycles / kra-assignments. Those label a
 *     month that is handed to them; they do not choose which month is current.
 *   * Monthly review generation. It generates every month of the cycle, so the
 *     row for the month now under review already exists.
 *   * Anything about which STAGE a review is at. This is only "which calendar
 *     month is the live one".
 *
 * ── THE CLIENT DOES NOT DEPEND ON THIS LANDING ──────────────────────────────
 *
 * `_periodFor` in employee_home_screen.dart already CLAMPS whatever the server
 * sends to at most the previous calendar month, and `CurrentMonthCard` renders
 * that clamped value instead of the server's `monthLabel`. So the screens are
 * correct before this patch is applied. Applying it makes the API itself
 * correct — which matters for any other consumer, and so the clamp is a
 * safety net rather than the only thing holding the behaviour up.
 */
import fs from 'fs';

const kraArg = process.argv.find((a) => a.startsWith('--kra='));
const KRA = kraArg
  ? kraArg.slice('--kra='.length)
  : 'D:/Vistar/vistar_CRM/src/modules/kra/dist';
const SVC = `${KRA}/features/employee/employee.service.js`;
const DRY = process.argv.includes('--dry');

const FIND = `function findCurrentMonth(months) {
    if (months.length === 0)
        return null;
    const now = new Date();
    const exact = months.find((m) => m.monthDate.getUTCFullYear() === now.getUTCFullYear() &&
        m.monthDate.getUTCMonth() === now.getUTCMonth());
    if (exact)
        return exact;`;

const REPLACE = `function findCurrentMonth(months) {
    if (months.length === 0)
        return null;
    // The month under review is the month that has ENDED - through September
    // you rate August. This used to match today's own month, which meant the
    // employee dashboard asked for a rating of a month with twenty days still
    // to run, and reported it as closing on the 10th.
    //
    // The deadline schedule is the proof this is the right way round: self
    // rating is due on the 10th, which only makes sense as the 10th of the
    // month AFTER the one being rated.
    //
    // Date.UTC with a month index of -1 rolls back to December of the previous
    // year on its own; a hand-written January branch is where this bug class
    // usually comes back.
    const now = new Date();
    const under = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
    const exact = months.find((m) => m.monthDate.getUTCFullYear() === under.getUTCFullYear() &&
        m.monthDate.getUTCMonth() === under.getUTCMonth());
    if (exact)
        return exact;`;

// ── Preflight ───────────────────────────────────────────────────────────────
if (!fs.existsSync(SVC)) {
  console.error(`FAIL  not found: ${SVC}`);
  process.exit(1);
}

let src = fs.readFileSync(SVC, 'utf8');
const eol = src.includes('\r\n') ? '\r\n' : '\n';
const N = (t) => t.split('\n').join(eol);
const name = SVC.split('/').pop();

const MARKER = 'const under = new Date(Date.UTC(';
if (src.includes(MARKER)) {
  console.log(`  SKIP   ${name} — already patched`);
  console.log('');
  console.log('nothing to do');
  process.exit(0);
}

const find = N(FIND);
const hits = src.split(find).length - 1;
if (hits !== 1) {
  console.error(`  FAIL   ${name} — findCurrentMonth matched ${hits} times, expected 1.`);
  console.error('         Patch by hand: match the month BEFORE today instead of today.');
  process.exit(1);
}

if (DRY) {
  console.log(`  WOULD  ${name} — findCurrentMonth picks the previous calendar month`);
  console.log('');
  console.log('dry run: 1 would apply');
  process.exit(0);
}

fs.copyFileSync(SVC, `${SVC}.bak`);
fs.writeFileSync(SVC, src.replace(find, N(REPLACE)), 'utf8');
console.log(`  OK     ${name} — findCurrentMonth picks the previous calendar month`);
console.log('');
console.log('Next: restart / redeploy the API.');
console.log('');
console.log('Verify:');
console.log('  GET /employee/dashboard  ->  currentMonth.monthLabel is the');
console.log('  PREVIOUS calendar month (e.g. "Aug-26" during September), and');
console.log('  currentMonth.monthDate is that month.');
console.log('');
console.log('Check the January rollover too, since that is the case a');
console.log('hand-written version would get wrong:');
console.log('  in January, currentMonth must be December of the PREVIOUS year.');
console.log('');
console.log(`  restore: copy ${name}.bak ${name}`);
