'use strict';
// Verifies docs/resync_review_kras.sql end to end, against a throwaway Postgres
// cluster this script creates and deletes itself:
//
//   node docs/verify_resync_review_kras.cjs <vistar_CRM checkout> [<postgres bin dir>]
//
// The review data is produced by the backend's REAL monthly-reviews repository
// (generateMonth -> snapshotRows, writeRowScores, resyncRowsIfUntouched, ...)
// with its prisma handle pointed at the throwaway server, so "the same copy the
// backend makes" is checked against the backend itself, not a retyped copy.
// Nothing outside the temporary cluster is read from or written to.
const fs = require('fs');
const os = require('os');
const net = require('net');
const path = require('path');
const Module = require('module');
const { spawnSync } = require('child_process');

const CRM = process.argv[2];
if (!CRM || !fs.existsSync(path.join(CRM, 'src/modules/kra/dist'))) {
  console.error('usage: node verify_resync_review_kras.cjs <vistar_CRM checkout> [<postgres bin dir>]');
  process.exit(2);
}
const PGBIN = process.argv[3] || (process.platform === 'win32' ? 'C:/Program Files/PostgreSQL/18/bin' : '');
const bin = (name) => (PGBIN ? path.join(PGBIN, name) : name);
const { Client } = require(path.join(CRM, 'node_modules/pg'));
const DIST = path.join(CRM, 'src/modules/kra/dist');
const MIGRATIONS = path.join(CRM, 'migrations');
const PSQL = bin('psql');
const SCRIPT = path.join(__dirname, 'resync_review_kras.sql');
const HERE = fs.mkdtempSync(path.join(os.tmpdir(), 'kra-resync-verify-'));
let PORT = 0;
const EXIM = '14f9961c-db82-4a21-b411-52d59afa7859'; // migration 115's template id

const conn = (database) =>
  new Client({ host: '127.0.0.1', port: PORT, user: 'postgres', database });

// ── The throwaway cluster ───────────────────────────────────────────────────
function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.once('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}
function run(cmd, args) {
  const r = spawnSync(cmd, args, { stdio: 'ignore' });
  if (r.status !== 0) {
    const why = r.error ? ' (' + r.error.message + ')' : '';
    throw new Error(path.basename(cmd) + ' ' + args.join(' ') + ' exited ' + r.status + why);
  }
}
async function startCluster() {
  PORT = await freePort();
  const data = path.join(HERE, 'pgdata');
  run(bin('initdb'), ['-D', data, '-U', 'postgres', '-A', 'trust', '-E', 'UTF8', '--locale=C']);
  run(bin('pg_ctl'), ['-D', data, '-o', '-p ' + PORT + ' -c listen_addresses=127.0.0.1',
                      '-l', path.join(HERE, 'pg.log'), '-w', 'start']);
}
function stopCluster() {
  spawnSync(bin('pg_ctl'), ['-D', path.join(HERE, 'pgdata'), '-m', 'fast', '-w', 'stop'], { stdio: 'ignore' });
  fs.rmSync(HERE, { recursive: true, force: true });
}

async function admin(sql) {
  const c = conn('postgres');
  await c.connect();
  try { await c.query(sql); } finally { await c.end(); }
}

let passed = 0;
let failed = 0;
function check(cond, msg, detail) {
  if (cond) { passed++; console.log('  ok   ' + msg); }
  else { failed++; console.log('  FAIL ' + msg + (detail !== undefined ? '\n       ' + JSON.stringify(detail) : '')); }
}

// ── The backend repository, its prisma swapped for a pg client ──────────────
function fakeModule(file, exports) {
  const key = require.resolve(file);
  const m = new Module(key, null);
  m.filename = key;
  m.loaded = true;
  m.exports = exports;
  require.cache[key] = m;
}
function loadRepo(client) {
  const stub = {
    $queryRawUnsafe: async (sql, ...params) => (await client.query(sql, params)).rows,
    $executeRawUnsafe: async (sql, ...params) => (await client.query(sql, params)).rowCount,
    async $transaction(fn) {
      await client.query('BEGIN');
      try { const r = await fn(stub); await client.query('COMMIT'); return r; }
      catch (e) { await client.query('ROLLBACK'); throw e; }
    },
  };
  const repoPath = require.resolve(path.join(DIST, 'features/monthly-reviews/monthly-reviews.repository.js'));
  delete require.cache[repoPath];
  fakeModule(path.join(DIST, 'config/database.js'), { prisma: stub });
  fakeModule(path.join(DIST, 'lib/proofStore.js'), {
    storeProof: async (data) => ({ data: data ?? null, storageKey: null }),
  });
  return require(repoPath).monthlyReviewsRepository;
}

const reviewId = async (c, code, y, m) =>
  (await c.query(
    `SELECT r.id FROM kra.monthly_reviews r JOIN kra.employees e ON e.id = r.employee_id
      WHERE e.employee_code = $1 AND r.year = $2 AND r.month = $3`, [code, y, m])).rows[0].id;
const rowsOf = async (c, id) =>
  (await c.query(`SELECT id, name, display_order FROM kra.monthly_review_rows
                   WHERE review_id = $1 ORDER BY display_order`, [id])).rows;

// ── Seed: the history behind the bug, played through the backend ────────────
async function buildSeed() {
  await admin('DROP DATABASE IF EXISTS kra_seed');
  await admin('CREATE DATABASE kra_seed');
  const c = conn('kra_seed');
  await c.connect();
  for (const f of ['008_kra_correct_schema.sql', '009_kra_enums.sql', '068_kra_template_archive.sql', '069_kra_monthly_reviews.sql',
                   '076_kra_monthly_reviews_id_text.sql']) {
    await c.query(fs.readFileSync(path.join(MIGRATIONS, f), 'utf8'));
  }
  // The proof columns came from ensureProofNoteColumn on the live database long
  // before migration 135, which assumes them — same statements, same order.
  await c.query(`
    ALTER TABLE kra.monthly_row_scores ADD COLUMN IF NOT EXISTS proof_note TEXT;
    ALTER TABLE kra.monthly_row_scores ADD COLUMN IF NOT EXISTS proof_file_name TEXT;
    ALTER TABLE kra.monthly_row_scores ADD COLUMN IF NOT EXISTS proof_file_mime TEXT;
    ALTER TABLE kra.monthly_row_scores ADD COLUMN IF NOT EXISTS proof_file_data TEXT;`);
  await c.query(fs.readFileSync(path.join(MIGRATIONS, '135_kra_proof_external_storage.sql'), 'utf8'));
  const repo = loadRepo(c);

  await c.query(`
    INSERT INTO kra.organizations (id, name, slug) VALUES
      ('org_vlpl', 'Vistar Logitek', 'vistar-logitek'),
      ('org_other', 'Other Org', 'other-org');
    INSERT INTO kra.kra_templates (id, organization_id, name, role) VALUES
      ('tpl_ops', 'org_vlpl', 'Manager KRA', 'MANAGER'),
      ('tpl_other', 'org_other', 'Other KRA', 'EMPLOYEE');
    INSERT INTO kra.kra_template_items
      (id, template_id, category, name, target, tracking_method, weightage, default_max_score, score_source, sort_order) VALUES
      ('o1',  'tpl_ops', 'Safety',    'Safety of the Facility',                  'Zero incidents', 'Audit',    0.15, 15, 'MANAGER',       1),
      ('o2',  'tpl_ops', 'Ops',       'Ops Excellence reports',                  'On time',        'Reports',  0.10, 10, 'OPS_FEED',      2),
      ('o3',  'tpl_ops', 'Inventory', 'Inventory accuracy',                      '99.5%',          'WMS',      0.15, 15, 'MANAGER',       3),
      ('o4',  'tpl_ops', 'Customer',  'Monthly review with customer/Leadership', 'Monthly',        'MOM',      0.10, 10, 'MANAGER',       4),
      ('o5',  'tpl_ops', 'Customer',  'Customer Escalations',                    'Zero',           'CRM',      0.10, 10, 'MANAGER',       5),
      ('o6',  'tpl_ops', 'Finance',   'Debits/Deductions',                       'Zero',           'Accounts', 0.10, 10, 'ACCOUNTS_FEED', 6),
      ('o7',  'tpl_ops', 'Finance',   'Invoice submission',                      'On time',        'Accounts', 0.10, 10, 'ACCOUNTS_FEED', 7),
      ('o8',  'tpl_ops', 'Finance',   'Accounts Receivable',                     '< 45 days',      'Accounts', 0.10, 10, 'ACCOUNTS_FEED', 8),
      ('o9',  'tpl_ops', 'HR',        'Submission of Attendance on time to HR',  'By 2nd',         'HR',       0.05,  5, 'HR_FEED',       9),
      ('o10', 'tpl_ops', 'HR',        'Joining Formalities',                     '100%',           'HR',       0.05,  5, 'HR_FEED',      10),
      ('x1',  'tpl_other', NULL, 'Other one', NULL, NULL, 0.5, 50, 'MANAGER', 1),
      ('x2',  'tpl_other', NULL, 'Other two', NULL, NULL, 0.5, 50, 'MANAGER', 2);
    INSERT INTO kra.employees
      (id, organization_id, email, name, employee_code, role, joined_date, default_template_id) VALUES
      ('emp_admin', 'org_vlpl',  'admin@t.test',  'Super Admin',                 'VLPL0001', 'HR_ADMIN', '2024-01-01', NULL),
      ('emp_dat',   'org_vlpl',  'dat@t.test',    'Test Employee 1436', 'VLPL1436', 'EMPLOYEE', '2025-01-01', 'tpl_ops'),
      ('emp_bha',   'org_vlpl',  'bha@t.test',    'Bhavna Template',             'VLPL2000', 'EMPLOYEE', '2025-01-01', 'tpl_ops'),
      ('emp_che',   'org_vlpl',  'che@t.test',    'Chetan InSync',               'VLPL3000', 'EMPLOYEE', '2025-01-01', 'tpl_ops'),
      ('emp_oth',   'org_other', 'oth@t.test',    'Other Org Person',            'OTH0001',  'EMPLOYEE', '2025-01-01', 'tpl_other');
    INSERT INTO kra.review_cycles
      (id, organization_id, name, fy_label, quarter_num, start_date, end_date, status,
       self_rating_deadline, manager_review_deadline, ops_scoring_deadline, finance_scoring_deadline) VALUES
      ('cyc_q2', 'org_vlpl', 'Q2 FY26-27', 'FY26-27', 2, '2026-07-01', '2026-09-30', 'ACTIVE',
       '2026-10-10', '2026-10-13', '2026-10-12', '2026-10-12'),
      ('cyc_q3', 'org_vlpl', 'Q3 FY26-27', 'FY26-27', 3, '2026-10-01', '2026-12-31', 'DRAFT',
       '2027-01-10', '2027-01-13', '2027-01-12', '2027-01-12');
  `);

  // Phase A — Jul–Sep generated while everyone is on the operations template.
  for (const m of [7, 8, 9]) await repo.generateMonth('org_vlpl', 2026, m);
  await repo.generateMonth('org_other', 2026, 7);

  const jul = await reviewId(c, 'VLPL1436', 2026, 7);
  const julRows = await rowsOf(c, jul);
  await repo.transaction(async (tx) => {
    const s = {};
    julRows.forEach((r, i) => {
      s[r.id] = {
        value: [12, 8, 14, 9, 10, 7, 9, 8, 5, 4][i],
        remark: i < 3 ? `July reason ${i + 1}` : null,
        ...(i === 0 ? { proofFile: { name: 'safety-audit.pdf', mime: 'application/pdf',
                                      data: Buffer.from('%PDF-1.4 test').toString('base64') } } : {}),
      };
    });
    await repo.writeRowScores(tx, jul, 'SELF_RATING', s);
    await repo.writeStageRecord(tx, jul, 'SELF_RATING', 'emp_dat', 'Test Employee 1436', 'Done', false);
    await repo.setCurrentStage(tx, jul, 'REPORTING_MANAGER_RATING');
    await repo.writeRowScores(tx, jul, 'REPORTING_MANAGER_RATING', { [julRows[0].id]: { value: 11, remark: 'RM note' } });
  });
  const aug = await reviewId(c, 'VLPL1436', 2026, 8);
  const augRows = await rowsOf(c, aug);
  await repo.transaction(async (tx) => {
    const s = {};
    augRows.slice(0, 5).forEach((r, i) => {
      s[r.id] = { value: [13, 9, 15, 8, 10][i],
                  remark: i === 3 ? 'Aug reason' : null, proofNote: i === 3 ? 'see MOM' : null };
    });
    await repo.writeRowScores(tx, aug, 'SELF_RATING', s);
  });
  for (const code of ['VLPL2000', 'VLPL3000']) {
    const id = await reviewId(c, code, 2026, 7);
    const rows = await rowsOf(c, id);
    await repo.transaction((tx) => repo.writeRowScores(tx, id, 'SELF_RATING', { [rows[0].id]: { value: 10 } }));
  }

  // Phase B — HR moves VLPL1436 and VLPL2000 to the Sr. GM EXIM KRAs (migration 115).
  await c.query(fs.readFileSync(path.join(MIGRATIONS, '115_kra_sr_gm_exim_template.sql'), 'utf8'));
  await c.query(`UPDATE kra.employees SET default_template_id = $1
                  WHERE employee_code IN ('VLPL1436', 'VLPL2000')`, [EXIM]);
  await c.query(`UPDATE kra.review_cycles SET status = 'CLOSED' WHERE id = 'cyc_q2'`);
  await c.query(`UPDATE kra.review_cycles SET status = 'ACTIVE' WHERE id = 'cyc_q3'`);
  // Only VLPL1436 gets an assignment (as HR's assign copies the template items);
  // VLPL2000 relies on the default template, the other source snapshotRows reads.
  await c.query(`
    INSERT INTO kra.kra_assignments (id, organization_id, employee_id, cycle_id, template_id, assigned_by, assigned_at)
    VALUES ('asg_dat_q3', 'org_vlpl', 'emp_dat', 'cyc_q3', $1, 'emp_admin', now());`, [EXIM]);
  await c.query(`
    INSERT INTO kra.kra_assignment_items (id, assignment_id, name, description, target, tracking_method, weightage, sort_order)
    SELECT 'asgi_' || sort_order, 'asg_dat_q3', name, description, target, tracking_method, weightage, sort_order
      FROM kra.kra_template_items WHERE template_id = $1`, [EXIM]);

  for (const m of [4, 5, 6, 10]) await repo.generateMonth('org_vlpl', 2026, m);

  // What a GET of each review does: heal what the backend can heal.
  const healed = {};
  for (const code of ['VLPL1436', 'VLPL2000', 'VLPL3000']) {
    for (const m of [7, 8, 9]) healed[`${code}-${m}`] = await repo.resyncRowsIfUntouched(await reviewId(c, code, 2026, m));
  }
  await c.end();
  return healed;
}

// ── Helpers for the scenarios ───────────────────────────────────────────────
function variant(file, replacements) {
  let s = fs.readFileSync(SCRIPT, 'utf8');
  for (const [from, to] of replacements) {
    const n = s.split(from).length - 1;
    if (n !== 1) throw new Error(`${file}: "${from}" occurs ${n} times`);
    s = s.replace(from, to);
  }
  const out = path.join(HERE, file);
  fs.writeFileSync(out, s);
  return out;
}
const APPLY = ['v_apply CONSTANT boolean := false;', 'v_apply CONSTANT boolean := true;'];
const UNDO = ['v_undo CONSTANT boolean := false;', 'v_undo CONSTANT boolean := true;'];
const code = (c) => ["'VLPL1436'::text  AS employee_code", `'${c}'::text  AS employee_code`];
const reference = (d) => ["DATE '2026-10-01' AS reference_month", `${d} AS reference_month`];

function psql(db, file, extra = []) {
  const r = spawnSync(PSQL, ['-X', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-p', String(PORT),
                             '-U', 'postgres', '-d', db, ...extra, '-f', file], { encoding: 'utf8' });
  return { status: r.status, out: r.stdout || '', err: r.stderr || '' };
}

// Step 0 plus one read-only step, run alone; its result rows, '|'-separated.
function readStep(db, marker, nextMarker) {
  const s = fs.readFileSync(SCRIPT, 'utf8');
  const file = path.join(HERE, 'step.sql');
  fs.writeFileSync(file, s.slice(s.indexOf('-- ── 0.'), s.indexOf('-- ── 1.')) +
                         s.slice(s.indexOf(marker), s.indexOf(nextMarker)));
  const r = psql(db, file, ['-A', '-t', '-F', '|', '-q']);
  return { status: r.status, err: r.err, rows: r.out.split(/\r?\n/).filter((l) => l.includes('|')) };
}
// Who does step 1 list?
const stepOneRows = (db) => readStep(db, '-- ── 1.', '-- ── 2a.');
// Step 2b as "Mon YYYY <display order> <fate>" (fate empty when unscored).
const fates = (db) => readStep(db, '-- ── 2b.', '-- ── 3.').rows.map((l) => {
  const c = l.split('|');
  return `${c[0]} ${c[2]} ${c[9]}`.trim();
});

async function fresh(db) {
  await admin(`DROP DATABASE IF EXISTS ${db}`);
  await admin(`CREATE DATABASE ${db} TEMPLATE kra_seed`);
}

// Order-independent hash of every review, row, score and stage record matching
// `where` (a function of the review-id column). strict=false ignores updated_at.
async function fingerprint(db, { strict = true, where = () => 'TRUE' } = {}) {
  const c = conn(db);
  await c.connect();
  try {
    const r = await c.query(`
      SELECT md5(coalesce(string_agg(x, E'\\n' ORDER BY x), '')) AS fp, count(*)::int AS n FROM (
        SELECT (CASE WHEN ${strict} THEN to_jsonb(r) ELSE to_jsonb(r) - 'updated_at' END)::text AS x
          FROM kra.monthly_reviews r WHERE ${where('r.id')}
        UNION ALL SELECT to_jsonb(rr)::text FROM kra.monthly_review_rows rr WHERE ${where('rr.review_id')}
        UNION ALL SELECT to_jsonb(s)::text FROM kra.monthly_row_scores s
                    JOIN kra.monthly_review_rows q ON q.id = s.row_id WHERE ${where('q.review_id')}
        UNION ALL SELECT to_jsonb(sr)::text FROM kra.monthly_stage_records sr WHERE ${where('sr.review_id')}
      ) z`);
    return r.rows[0];
  } finally { await c.end(); }
}

async function q(db, sql, params = []) {
  const c = conn(db);
  await c.connect();
  try { return (await c.query(sql, params)).rows; } finally { await c.end(); }
}

const ROW_COLS = `name, coalesce(category, '<null>') AS category, weightage_percent::text AS w,
                  max_score::text AS mx, coalesce(target, '<null>') AS target,
                  coalesce(tracking_method, '<null>') AS tracking, display_order,
                  coalesce(reviewer_group, '<null>') AS reviewer_group`;
const monthRows = (db, empCode, m) => q(db, `
  SELECT ${ROW_COLS} FROM kra.monthly_review_rows rr
   WHERE rr.review_id = (SELECT r.id FROM kra.monthly_reviews r JOIN kra.employees e ON e.id = r.employee_id
                          WHERE e.employee_code = $1 AND r.year = 2026 AND r.month = $2)
   ORDER BY display_order`, [empCode, m]);
const reviewState = (db, empCode, m) => q(db, `
  SELECT r.id, r.current_stage, r.incentive_computed_score_pct,
         (SELECT count(*)::int FROM kra.monthly_row_scores s JOIN kra.monthly_review_rows x ON x.id = s.row_id
           WHERE x.review_id = r.id) AS scores,
         (SELECT count(*)::int FROM kra.monthly_stage_records sr WHERE sr.review_id = r.id) AS records
    FROM kra.monthly_reviews r JOIN kra.employees e ON e.id = r.employee_id
   WHERE e.employee_code = $1 AND r.year = 2026 AND r.month = $2`, [empCode, m]).then((r) => r[0]);
const backupExists = async (db) =>
  (await q(db, `SELECT to_regclass('kra.review_kra_resync_backup') IS NOT NULL AS e`))[0].e;

// ── Run ─────────────────────────────────────────────────────────────────────
async function main() {
  console.log('seed (backend code plays the history)');
  const healed = await buildSeed();
  check(healed['VLPL1436-7'] === 0 && healed['VLPL1436-8'] === 0,
        'bug reproduced: the backend refuses to re-copy Jul/Aug because they carry scores', healed);
  check(healed['VLPL1436-9'] === 5, 'the backend re-copied the untouched September itself', healed);
  check(healed['VLPL2000-8'] === 0 && healed['VLPL2000-9'] === 0,
        'a default-template change is never healed by the backend (no active assignment)', healed);
  const seedLoose = await fingerprint('kra_seed', { strict: false });
  const seedJulOps = await monthRows('kra_seed', 'VLPL1436', 7);
  check(seedJulOps.length === 10 && seedJulOps[0].name === 'Safety of the Facility',
        'seed: Jul holds the 10 operations KRAs');
  const octRows = await monthRows('kra_seed', 'VLPL1436', 10);
  check(octRows.length === 5 && octRows[0].name === 'New Business Development & Customer Acquisition',
        'seed: Oct (backend-generated) holds the 5 Sr. GM EXIM KRAs', octRows.map((r) => r.name));
  const aprRows = await monthRows('kra_seed', 'VLPL1436', 4);
  check(JSON.stringify(aprRows) === JSON.stringify(octRows), 'seed: Apr matches Oct (the "correct" quarters)');

  console.log('\n1. step 1 lists exactly the stale reviews');
  {
    const r = stepOneRows('kra_seed');
    check(r.status === 0, 'steps 0-1 run clean', r.err);
    const keys = r.rows.map((l) => l.split('|').slice(0, 3).filter((_, i) => i !== 1).join(' ')).sort();
    check(JSON.stringify(keys) === JSON.stringify([
      'VLPL1436 Aug 2026', 'VLPL1436 Jul 2026', 'VLPL2000 Aug 2026', 'VLPL2000 Jul 2026', 'VLPL2000 Sep 2026',
    ]), 'VLPL1436 Jul+Aug and VLPL2000 Jul-Sep; not Sep (healed), not VLPL3000, not the other org', r.rows);
  }

  console.log('\n1b. steps 2a and 2b show what step 3 will do');
  {
    const a = readStep('kra_seed', '-- ── 2a.', '-- ── 2b.');
    check(a.status === 0 && JSON.stringify(a.rows.map((l) => l.split('|')[2])) === JSON.stringify(octRows.map((r) => r.name)) &&
          a.rows[0].startsWith('assignment in active cycle "Q3 FY26-27" (template "Sr. General Manager EXIM KRA")|1|'),
          '2a lists the five KRAs October has, and where they come from', a.rows);
    const b = readStep('kra_seed', '-- ── 2b.', '-- ── 3.');
    const julFirst = b.rows[0].split('|');
    check(b.status === 0 && julFirst[0] === 'Jul 2026' && julFirst[3] === 'Safety of the Facility' &&
          julFirst[6] === 'REPORTING_MANAGER_RATING=11.0000, SELF_RATING=12.0000' &&
          julFirst[7] === 't' && julFirst[8] === 't' && julFirst[9] === 'deleted',
          '2b shows each score, its reason and attachment', b.rows[0]);
    const expected = [
      ...[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((o) => `Jul 2026 ${o} deleted`),
      ...[1, 2, 3, 4, 5].map((o) => `Aug 2026 ${o} deleted`),
      ...[6, 7, 8, 9, 10].map((o) => `Aug 2026 ${o}`),
      ...[1, 2, 3, 4, 5].map((o) => `Sep 2026 ${o}`),
    ];
    check(JSON.stringify(fates('kra_seed')) === JSON.stringify(expected),
          '2b fates: every Jul score and Aug draft deleted, unscored rows blank', fates('kra_seed'));
  }

  console.log('\n2. dry run changes nothing');
  await fresh('kra_dry');
  {
    const before = await fingerprint('kra_dry');
    const r = psql('kra_dry', SCRIPT);
    check(r.status === 0, 'whole script runs clean as shipped', r.err.slice(-800));
    console.log(r.err.split(/\r?\n/).map((l) => l.replace(/^psql:.*?:\d+: /, ''))
      .filter((l) => l.startsWith('NOTICE:')).map((l) => '       | ' + l).join('\n'));
    check(/Jul 2026 \| VLPL1436: 10 KRAs replaced by 5 from assignment in active cycle "Q3 FY26-27" \(template "Sr\. General Manager EXIM KRA"\)/.test(r.err),
          'announces July', r.err);
    check(/Aug 2026 \| VLPL1436: 10 KRAs replaced by 5/.test(r.err), 'announces August');
    check(/Sep 2026 \| VLPL1436: already has the current KRAs - left alone/.test(r.err), 'leaves September alone');
    check(/DRY RUN - nothing above was saved/.test(r.err), 'says it was a dry run');
    check(/Step 5 \(undo\) is off/.test(r.err), 'undo stays off');
    check(!/does not exist, skipping|already exists, skipping/.test(r.err), 'no housekeeping noise in the output', r.err);
    const after = await fingerprint('kra_dry');
    check(before.fp === after.fp, 'database byte-identical afterwards (incl. updated_at)', { before, after });
    check(!(await backupExists('kra_dry')), 'no backup table left behind');
  }

  console.log('\n3. apply');
  await fresh('kra_apply');
  const julId = (await reviewState('kra_apply', 'VLPL1436', 7)).id;
  const augId = (await reviewState('kra_apply', 'VLPL1436', 8)).id;
  const notTargets = (col) => `${col} NOT IN ('${julId}', '${augId}')`;
  {
    const othersBefore = await fingerprint('kra_apply', { where: notTargets });
    const r = psql('kra_apply', variant('apply.sql', [APPLY]));
    check(r.status === 0, 'runs clean', r.err.slice(-800));
    check(r.err.includes('Jul 2026 | VLPL1436: 10 KRAs replaced by 5') &&
          r.err.includes('Scores kept: 0. Scores deleted: REPORTING_MANAGER_RATING x1, SELF_RATING x10 (4 with a reason, 1 with an attachment). Submissions cleared: SELF_RATING. Back at SELF_RATING.'),
          'July line: 11 scores deleted, 4 with a reason (3 self + the manager note), 1 attachment, SELF submission cleared', r.err);
    check(r.err.includes('Scores kept: 0. Scores deleted: SELF_RATING x5 (1 with a reason, 0 with an attachment). Submissions cleared: none.'),
          'August line: 5 drafts deleted, 1 reason');
    check(r.err.includes('Test Employee 1436 (VLPL1436): 2 month(s) re-copied, 1 already current.'), 'summary line');
    check(!r.err.includes('DRY RUN'), 'not a dry run');
    for (const m of [7, 8]) {
      const rows = await monthRows('kra_apply', 'VLPL1436', m);
      check(JSON.stringify(rows) === JSON.stringify(octRows),
            `month ${m}: rows identical to the backend-generated October (name, category, weight, max, target, tracking, order, reviewer)`,
            { rows, octRows });
      const st = await reviewState('kra_apply', 'VLPL1436', m);
      check(st.current_stage === 'SELF_RATING' && st.scores === 0 && st.records === 0 && st.incentive_computed_score_pct === null,
            `month ${m}: restarted at SELF_RATING, no scores, no submissions, no incentive figure`, st);
    }
    const othersAfter = await fingerprint('kra_apply', { where: notTargets });
    check(othersBefore.fp === othersAfter.fp && othersBefore.n > 50,
          `every other review untouched, to the byte (${othersBefore.n} records)`, { othersBefore, othersAfter });
    const bk = await q('kra_apply', `
      SELECT month, jsonb_array_length(old_rows) AS r, jsonb_array_length(old_scores) AS s,
             jsonb_array_length(old_stage_records) AS sr, jsonb_array_length(new_rows) AS nr,
             (SELECT count(*)::int FROM jsonb_array_elements(old_scores) e WHERE e ->> 'proof_file_data' IS NOT NULL) AS files,
             old_review ->> 'current_stage' AS stage, restored_at
        FROM kra.review_kra_resync_backup ORDER BY month`);
    check(JSON.stringify(bk.map((b) => [b.month, b.r, b.s, b.sr, b.nr, b.files, b.stage, b.restored_at])) ===
          JSON.stringify([[7, 10, 11, 1, 5, 1, 'REPORTING_MANAGER_RATING', null], [8, 10, 5, 0, 5, 0, 'SELF_RATING', null]]),
          'backup holds every deleted row, score (with the attachment bytes) and submission', bk);

    // The backend reads the result back without objection.
    const c = conn('kra_apply');
    await c.connect();
    const repo = loadRepo(c);
    check((await repo.resyncRowsIfUntouched(julId)) === 0, 'backend: no further re-copy wanted on read');
    const viaBackend = await repo.findRows(julId);
    check(viaBackend.length === 5 && viaBackend.every((r) => r.reviewer_group === 'MANAGER'),
          'backend: findRows (with its reviewer self-heal) returns the 5 KRAs', viaBackend.map((r) => [r.name, r.reviewer_group]));
    const summaries = await repo.listSummaries({ organizationId: 'org_vlpl', year: 2026, month: 7 });
    const mine = summaries.find((s) => s.employee_code === 'VLPL1436');
    check(mine && mine.current_stage === 'SELF_RATING' && mine.total_rows === 5 && mine.reviewed_rows === 0,
          'backend: the July list summary shows 5 KRAs, none reviewed, at SELF_RATING', mine);
    await c.end();
    const afterReads = await fingerprint('kra_apply');

    const again = psql('kra_apply', path.join(HERE, 'apply.sql'));
    check(again.status === 0 && (again.err.match(/already has the current KRAs - left alone/g) || []).length === 3 &&
          again.err.includes('0 month(s) re-copied, 3 already current.'),
          'second run: all three months already current', again.err);
    check(!/exists, skipping/.test(again.err), 'second run: backup table reused quietly', again.err);
    check((await fingerprint('kra_apply')).fp === afterReads.fp, 'second run changed nothing (incl. updated_at)');
  }

  console.log('\n4. undo puts back exactly what was there');
  {
    const r = psql('kra_apply', variant('undo.sql', [UNDO]));
    check(r.status === 0, 'runs clean', r.err.slice(-800));
    check(r.err.includes('Jul 2026 | VLPL1436: restored 10 KRAs, 11 scores, 1 submissions.') &&
          r.err.includes('Aug 2026 | VLPL1436: restored 10 KRAs, 5 scores, 0 submissions.'), 'restore lines', r.err);
    const loose = await fingerprint('kra_apply', { strict: false });
    check(loose.fp === seedLoose.fp, 'every review, row id, score, attachment and submission equals the seed', { loose, seedLoose });
    const r2 = psql('kra_apply', path.join(HERE, 'undo.sql'));
    check(r2.status === 0 && r2.err.includes('VLPL1436: 0 month(s) restored.'), 'undo twice restores nothing more', r2.err);
  }

  console.log('\n5. refuses a signed-off month, and changes nothing at all');
  await fresh('kra_locked');
  {
    await q('kra_locked', `ALTER TABLE kra.monthly_reviews ADD COLUMN IF NOT EXISTS management_locked_at TIMESTAMPTZ`);
    await q('kra_locked', `UPDATE kra.monthly_reviews SET management_locked_at = now() WHERE id = (
                             SELECT r.id FROM kra.monthly_reviews r JOIN kra.employees e ON e.id = r.employee_id
                              WHERE e.employee_code = 'VLPL1436' AND r.year = 2026 AND r.month = 8)`);
    const before = await fingerprint('kra_locked');
    const r = psql('kra_locked', path.join(HERE, 'apply.sql'));
    check(r.status !== 0 && r.err.includes('Aug 2026 | VLPL1436: management has signed this month off'),
          'stops with the reason', r.err.slice(-600));
    check((await fingerprint('kra_locked')).fp === before.fp, 'July (processed first) was rolled back too');
    check(!(await backupExists('kra_locked')), 'no backup table left behind');
  }
  await fresh('kra_paid');
  {
    await q('kra_paid', `UPDATE kra.monthly_reviews SET payout_status = 'PAID', current_stage = 'COMPLETED' WHERE id = (
                           SELECT r.id FROM kra.monthly_reviews r JOIN kra.employees e ON e.id = r.employee_id
                            WHERE e.employee_code = 'VLPL1436' AND r.year = 2026 AND r.month = 7)`);
    const before = await fingerprint('kra_paid');
    const r = psql('kra_paid', path.join(HERE, 'apply.sql'));
    check(r.status !== 0 && r.err.includes('Jul 2026 | VLPL1436: management has signed this month off (stage COMPLETED, payout PAID'),
          'refuses a paid month', r.err.slice(-600));
    check((await fingerprint('kra_paid')).fp === before.fp, 'nothing changed');
  }

  console.log('\n6. refuses when the current KRAs are not the reference month\'s');
  await fresh('kra_ref');
  {
    const before = await fingerprint('kra_ref');
    const r = psql('kra_ref', variant('ref_aug.sql', [APPLY, reference("DATE '2026-08-01'")]));
    check(r.status !== 0 && r.err.includes('are not the KRAs on Aug 2026'), 'stops with the reason', r.err.slice(-600));
    check((await fingerprint('kra_ref')).fp === before.fp, 'nothing changed');
    const r2 = psql('kra_ref', variant('ref_none.sql', [APPLY, reference("DATE '2026-11-01'")]));
    check(r2.status !== 0 && r2.err.includes('has no review with KRAs for the reference month Nov 2026'),
          'a reference month with no review is refused, not skipped', r2.err.slice(-600));
    const r3 = psql('kra_ref', variant('nobody.sql', [APPLY, code('NOPE9999')]));
    check(r3.status !== 0 && r3.err.includes('No employee has the code NOPE9999.'), 'unknown employee code is refused');
    check((await fingerprint('kra_ref')).fp === before.fp, 'still nothing changed');
  }

  console.log('\n7. a KRA present in both sets keeps its score');
  await fresh('kra_carry');
  {
    // August's 4th KRA renamed (odd case and spacing) to one of the new KRAs, same max score.
    await q('kra_carry', `UPDATE kra.monthly_review_rows SET name = '  cross   FUNCTIONAL coordination ', max_score = 100
                           WHERE review_id = (SELECT r.id FROM kra.monthly_reviews r JOIN kra.employees e ON e.id = r.employee_id
                                               WHERE e.employee_code = 'VLPL1436' AND r.year = 2026 AND r.month = 8)
                             AND display_order = 4`);
    const aug = fates('kra_carry').filter((f) => f.startsWith('Aug 2026'));
    check(JSON.stringify(aug) === JSON.stringify(['Aug 2026 1 deleted', 'Aug 2026 2 deleted', 'Aug 2026 3 deleted',
                                                  'Aug 2026 4 kept', 'Aug 2026 5 deleted', 'Aug 2026 6', 'Aug 2026 7',
                                                  'Aug 2026 8', 'Aug 2026 9', 'Aug 2026 10']),
          '2b predicts it: the 4th August KRA "kept", the other drafts "deleted"', aug);
    const r = psql('kra_carry', path.join(HERE, 'apply.sql'));
    check(r.status === 0 && r.err.includes('Aug 2026 | VLPL1436: 10 KRAs replaced by 5') &&
          r.err.includes('Scores kept: 1. Scores deleted: SELF_RATING x4 (0 with a reason, 0 with an attachment)'),
          'August keeps 1, deletes 4', r.err.slice(-900));
    const kept = await q('kra_carry', `
      SELECT rr.name, s.stage, s.value::text AS value, s.remark, s.proof_note
        FROM kra.monthly_row_scores s JOIN kra.monthly_review_rows rr ON rr.id = s.row_id
       WHERE rr.review_id = (SELECT r.id FROM kra.monthly_reviews r JOIN kra.employees e ON e.id = r.employee_id
                              WHERE e.employee_code = 'VLPL1436' AND r.year = 2026 AND r.month = 8)`);
    check(JSON.stringify(kept) === JSON.stringify([{ name: 'Cross Functional Coordination', stage: 'SELF_RATING',
                                                     value: '8.0000', remark: 'Aug reason', proof_note: 'see MOM' }]),
          'the score, its reason and note now sit on the new row', kept);
  }

  console.log('\n8. default-template source (VLPL2000) matches the backend\'s template copy');
  await fresh('kra_tpl');
  {
    const octTpl = await monthRows('kra_tpl', 'VLPL2000', 10);
    check(octTpl.length === 5 && octTpl[0].mx === '50.00' && octTpl[0].category === 'Business Development',
          'seed: her October came from the template (max 50, category set)', octTpl[0]);
    const r = psql('kra_tpl', variant('tpl.sql', [APPLY, code('VLPL2000')]));
    check(r.status === 0 && r.err.includes('3 month(s) re-copied, 0 already current.') &&
          r.err.includes('from default template "Sr. General Manager EXIM KRA"'), 'all three months re-copied', r.err.slice(-900));
    for (const m of [7, 8, 9]) {
      check(JSON.stringify(await monthRows('kra_tpl', 'VLPL2000', m)) === JSON.stringify(octTpl),
            `month ${m}: identical to her backend-generated October`);
    }
    const st = await stepOneRows('kra_tpl');
    check(st.rows.every((l) => !l.startsWith('VLPL2000|')), 'step 1 no longer lists her', st.rows);
  }

}

(async () => {
  try {
    await startCluster();
    await main();
  } finally {
    stopCluster();
  }
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(2);
});
