/**
 * Ships the employee's job DESIGNATION with monthly reviews.
 *
 *     node D:\Vistar\krafrontend\docs\install_review_designation.mjs --dry
 *     node D:\Vistar\krafrontend\docs\install_review_designation.mjs
 *
 * Idempotent; all-or-nothing; backs each file up as <name>.bak before writing.
 * `--kra=<dir>` patches a COPY of the dist tree so the result can be
 * syntax-checked before the deployed files are touched.
 *
 * ── WHY ─────────────────────────────────────────────────────────────────────
 *
 * The Monthly Reviews list shows a name and an employee code. Reviewers asked
 * for the designation alongside, so a reviewer scanning forty cards can tell a
 * Cluster Manager from a Sr. Accountant without opening each one.
 *
 * The value already exists: `kra.employees.position` (Prisma `position
 * String?`), which HR sets on the employee form and the client already exposes
 * as `Employee.position`. It is simply not selected by the monthly-review
 * queries, so it never reaches the list.
 *
 * ── WHAT CHANGES ────────────────────────────────────────────────────────────
 *
 *   repository  list SELECT    + e.position
 *   repository  header SELECT  + e.position
 *   service     toSummary      + employeeDesignation
 *   service     full review    + designation
 *
 * Four lines. No new joins — `kra.employees` is already joined as `e` in both
 * queries, so this adds a column to an existing scan and costs nothing.
 *
 * The field is named `employeeDesignation` on the wire rather than `position`.
 * "Position" reads as an index in list code, and the client model calls it
 * `employeeDesignation` for the same reason; the client also accepts
 * `employeePosition`/`position` so a mixed deployment still renders.
 *
 * ── WHAT DELIBERATELY DOES *NOT* CHANGE ─────────────────────────────────────
 *
 *   * Nothing is made required. `position` is nullable in the schema and plenty
 *     of employees have none, so it serialises as null and the client renders
 *     no line at all rather than a placeholder.
 *   * The list's search filter still matches name and code only — its
 *     placeholder says "Search by name or code", and widening the match
 *     without changing that copy would be a silent behaviour change.
 *   * No index is added. This is a projection on rows already being read, not
 *     a filter.
 *
 * ── THE CLIENT IS ALREADY READY ─────────────────────────────────────────────
 *
 * `MonthlyReviewSummary.employeeDesignation` parses it and the card renders the
 * line only when it is non-empty. So the client is safe to deploy before or
 * after this patch: without it the cards look exactly as they do today.
 */
import fs from 'fs';

const kraArg = process.argv.find((a) => a.startsWith('--kra='));
const KRA = kraArg
  ? kraArg.slice('--kra='.length)
  : 'D:/Vistar/vistar_CRM/src/modules/kra/dist';
const REPO = `${KRA}/features/monthly-reviews/monthly-reviews.repository.js`;
const SVC = `${KRA}/features/monthly-reviews/monthly-reviews.service.js`;
const DRY = process.argv.includes('--dry');

const EDITS = [
  {
    file: REPO,
    marker: 'e.grade, e.position,',
    find: '              e.name AS employee_name, e.employee_code, e.grade,',
    replace:
      '              e.name AS employee_name, e.employee_code, e.grade, e.position,',
  },
  {
    file: REPO,
    // Must include the `SELECT r.*,` prefix. A marker of just
    // "e.grade, e.position," is a SUBSTRING of what the edit above writes, so
    // this edit reported "already present" and silently did nothing — the
    // header query went unpatched while the dry run looked clean.
    marker:
      'SELECT r.*, e.name AS employee_name, e.employee_code, e.grade, e.position,',
    find:
      'SELECT r.*, e.name AS employee_name, e.employee_code, e.grade,\n' +
      '              e.manager_id, m.name AS manager_name',
    replace:
      'SELECT r.*, e.name AS employee_name, e.employee_code, e.grade, e.position,\n' +
      '              e.manager_id, m.name AS manager_name',
  },
  {
    file: SVC,
    marker: 'employeeDesignation: r.position ?? null,',
    find: '        employeeGrade: r.grade ?? null,',
    replace:
      '        employeeGrade: r.grade ?? null,\n' +
      '        // Job designation (employees.position) — shown beside the name\n' +
      '        // on the Monthly Reviews list. Nullable: plenty of employees\n' +
      '        // have none, and the client renders no line rather than a\n' +
      '        // placeholder.\n' +
      '        employeeDesignation: r.position ?? null,',
  },
  {
    file: SVC,
    marker: 'designation: header.position ?? null,',
    find: '        grade: header.grade ?? null,',
    replace:
      '        grade: header.grade ?? null,\n' +
      '        designation: header.position ?? null,',
  },
];

for (const f of [REPO, SVC]) {
  if (!fs.existsSync(f)) {
    console.error(`FAIL  not found: ${f}`);
    process.exit(1);
  }
}

const byFile = new Map([
  [REPO, fs.readFileSync(REPO, 'utf8')],
  [SVC, fs.readFileSync(SVC, 'utf8')],
]);

let applied = 0;
let skipped = 0;
let failed = 0;

for (const e of EDITS) {
  const name = e.file.split('/').pop();
  const label = `${name}: ${e.marker.split('\n')[0].slice(0, 44)}`;
  const src = byFile.get(e.file);
  const eol = src.includes('\r\n') ? '\r\n' : '\n';
  const N = (t) => t.split('\n').join(eol);

  if (src.includes(N(e.marker))) {
    console.log(`  SKIP   ${label} — already present`);
    skipped++;
    continue;
  }

  const find = N(e.find);
  const hits = src.split(find).length - 1;
  if (hits !== 1) {
    console.error(`  FAIL   ${label} — anchor matched ${hits} times, expected 1`);
    failed++;
    continue;
  }

  byFile.set(e.file, src.replace(find, N(e.replace)));
  console.log(`  ${DRY ? 'WOULD ' : 'OK    '} ${label}`);
  applied++;
}

if (failed > 0) {
  console.error('');
  console.error(`FAILED — ${failed} anchor(s) did not match. NOTHING was written.`);
  console.error('A half-applied patch would select the column without serialising');
  console.error('it, or serialise a column that was never selected (undefined).');
  process.exit(1);
}

console.log('');
if (DRY) {
  console.log(`dry run: ${applied} would apply, ${skipped} already done`);
  process.exit(0);
}

if (applied === 0) {
  console.log(`nothing to do (skipped=${skipped}) — already patched`);
  process.exit(0);
}

for (const [f, src] of byFile) {
  fs.copyFileSync(f, `${f}.bak`);
  fs.writeFileSync(f, src, 'utf8');
}
console.log(`applied=${applied} skipped=${skipped}`);
console.log('');
console.log('Next: restart / redeploy the API.');
console.log('');
console.log('Verify:');
console.log('  GET /reviews/monthly?year=2026&month=8');
console.log('  -> each row carries employeeDesignation (null where the');
console.log('     employee has no position set — that is expected)');
console.log('');
console.log('Then the Monthly Reviews cards show the designation under the');
console.log('name. Employees with no position keep a single-line card.');
for (const f of byFile.keys()) {
  const n = f.split('/').pop();
  console.log(`  restore: copy ${n}.bak ${n}`);
}
