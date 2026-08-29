// App-wide audit of KRA reviewer mapping and review-state consistency.
//
// Answers "is the mapping right for EVERY employee?" without opening 42 sheets
// by hand. For one month it fetches every monthly review in full, plus each
// employee's KRA assignment and its source template, and reports per employee:
//
//   * REVIEWER MISMATCH — a review row's reviewer_group disagrees with the
//     assignment item / template it was snapshotted from. The row is what every
//     screen reads, so a mismatch means the sheet shows the wrong owner.
//   * NO REVIEWER — a row with no reviewer at all. The app defaults these to
//     the reporting manager; the backend self-heals them to MANAGER on read, so
//     any that survive point at a review the self-heal did not cover.
//   * WEIGHTAGE — KRA weightages that do not sum to 100%. Every score on the
//     sheet is weighted, so this silently distorts the final percentage.
//   * REVIEWED BEFORE SELF — a reviewer, or management, scored a KRA the
//     employee never self-rated. The sheet used to offer a Rate button on
//     months nobody had self-rated, and the reporting manager's score is meant
//     to be capped by the self score, so these rows were entered with no
//     ceiling and should be re-checked.
//   * CURSOR AHEAD OF WORK — the stored currentStage has run past stages whose
//     scores do not exist. This is what made the compliance report read
//     "Submitted" and "Approved" for people who had rated almost nothing.
//   * NO ASSIGNMENT — no active-cycle KRA assignment, so the reviewer can only
//     come from the employee's default template.
//
// Read-only: every request is a GET. Nothing is written.
//
// Usage:
//   node scripts/audit-kra-mapping.mjs --email hr.admin@vistar.test --password 'Vistar@123'
//   node scripts/audit-kra-mapping.mjs --month 2026-07
//   node scripts/audit-kra-mapping.mjs --base https://api.vistarlogitek.com/api/v1/kra
//   node scripts/audit-kra-mapping.mjs --json > audit.json
//
// Credentials may also come from KRA_EMAIL / KRA_PASSWORD in the environment,
// which keeps them out of your shell history.

const args = parseArgs(process.argv.slice(2));

const BASE = (
  args.base ||
  process.env.KRA_BASE ||
  'https://api.vistarlogitek.com/api/v1/kra'
).replace(/\/+$/, '');

const EMAIL = args.email || process.env.KRA_EMAIL;
const PASSWORD = args.password || process.env.KRA_PASSWORD;

// Requires an HR_ADMIN / ADMIN login: the templates and assignments endpoints
// are HR-tier, and the whole point is to compare them against the reviews.
if (!EMAIL || !PASSWORD) {
  console.error(
    'Need HR credentials.\n' +
      '  node scripts/audit-kra-mapping.mjs --email <hr email> --password <password>\n' +
      '  or set KRA_EMAIL / KRA_PASSWORD',
  );
  process.exit(2);
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) {
      out[key] = true;
    } else {
      out[key] = next;
      i++;
    }
  }
  return out;
}

/// The month to audit, defaulting to the current calendar month.
function resolveMonth(raw) {
  if (typeof raw === 'string') {
    const m = /^(\d{4})-(\d{1,2})$/.exec(raw.trim());
    if (!m) {
      console.error(`--month must look like 2026-07, got "${raw}"`);
      process.exit(2);
    }
    return { year: Number(m[1]), month: Number(m[2]) };
  }
  const now = new Date();
  return { year: now.getFullYear(), month: now.getMonth() + 1 };
}

const { year, month } = resolveMonth(args.month);

// ── HTTP ────────────────────────────────────────────────────────────

let token = null;

async function login() {
  const res = await fetch(`${BASE}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
  });
  const json = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(
      `login failed (${res.status}): ${json?.error?.message ?? 'unknown'}`,
    );
  }
  token =
    json?.data?.tokenPair?.accessToken ??
    json?.data?.accessToken ??
    json?.accessToken;
  if (!token) throw new Error('login returned no access token');
  return json?.data?.user ?? null;
}

async function get(path) {
  const res = await fetch(`${BASE}${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const json = await res.json().catch(() => null);
  if (!res.ok) {
    const message = json?.error?.message ?? res.statusText;
    const err = new Error(`GET ${path} → ${res.status} ${message}`);
    err.status = res.status;
    throw err;
  }
  // Envelope: { success, data, meta? }
  return json?.data ?? json;
}

/// Walks a paginated list endpoint to the end.
///
/// The audit is only correct if it sees EVERY employee — stopping at the first
/// page would quietly audit 50 of 200 and report "all clear".
///
/// Deduplicated by id because `/reviews/monthly` does NOT paginate: its query
/// schema declares only year/month, and zod strips the page/limit sent here, so
/// every request returns the whole list. Without the dedupe, a `meta` block
/// claiming more than one page would audit everyone twice.
async function getAll(path, { limit = 100 } = {}) {
  const items = [];
  const seen = new Set();
  for (let page = 1; page <= 100; page++) {
    const sep = path.includes('?') ? '&' : '?';
    const res = await fetch(`${BASE}${path}${sep}page=${page}&limit=${limit}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const json = await res.json().catch(() => null);
    if (!res.ok) {
      throw new Error(
        `GET ${path} page ${page} → ${res.status} ${json?.error?.message ?? ''}`,
      );
    }
    const data = json?.data ?? [];
    const batch = Array.isArray(data) ? data : (data.items ?? []);
    let fresh = 0;
    for (const item of batch) {
      const key = item?.id ?? JSON.stringify(item);
      if (seen.has(key)) continue;
      seen.add(key);
      items.push(item);
      fresh++;
    }
    const meta = json?.meta;
    if (!meta || !meta.totalPages || page >= meta.totalPages) break;
    // A page that added nothing new means the endpoint is ignoring `page`.
    if (batch.length === 0 || fresh === 0) break;
  }
  return items;
}

// ── Vocabulary ──────────────────────────────────────────────────────

// The reviewer designation appears in two vocabularies: the template's
// score_source enum and the row's free-text reviewer_group. Both are folded to
// one canonical name before comparing, or every row would read as a mismatch.
function canonReviewer(raw) {
  const v = String(raw ?? '').trim().toUpperCase().replace(/-/g, '_');
  if (!v) return null;
  if (['MANAGER', 'REPORTING_MANAGER', 'REPORTING_MANAGER_RATING', 'RM'].includes(v)) {
    return 'MANAGER';
  }
  if (['HR', 'HR_FEED', 'HR_RATING', 'ACCOUNT_HR', 'ACCOUNT_HR_RATING'].includes(v)) {
    return 'HR';
  }
  if (['ACCOUNTS', 'ACCOUNT', 'ACCOUNTS_FEED', 'FINANCE', 'FINANCE_RATING'].includes(v)) {
    return 'ACCOUNTS';
  }
  if (['OPS', 'OPS_FEED', 'OPS_EXCELLENCE'].includes(v)) return 'OPS';
  return v; // unknown — surfaced rather than silently folded
}

const STAGES = [
  'SELF_RATING',
  'REPORTING_MANAGER_RATING',
  'ACCOUNT_HR_RATING',
  'FINANCE_RATING',
  'MANAGEMENT_REVIEW',
  'INCENTIVE_PAYOUT',
  'COMPLETED',
];

const stageIndex = (s) => {
  const i = STAGES.indexOf(String(s ?? '').toUpperCase());
  return i < 0 ? 0 : i;
};

/// The stage a row's assigned reviewer scores.
const reviewStageFor = (reviewer) =>
  ({
    MANAGER: 'REPORTING_MANAGER_RATING',
    HR: 'ACCOUNT_HR_RATING',
    ACCOUNTS: 'FINANCE_RATING',
  })[reviewer] ?? null;

const scoreOf = (row, stage) => {
  const scores = row?.stageScores ?? {};
  const entry = scores[stage];
  const value = entry?.value;
  return value === null || value === undefined ? null : Number(value);
};

const norm = (name) => String(name ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');

// ── Audit ───────────────────────────────────────────────────────────

async function auditEmployee(summary) {
  const findings = [];
  const label = `${summary.employeeName ?? summary.employee?.name ?? '?'} (${
    summary.employeeCode ?? summary.employee?.employeeCode ?? '—'
  })`;

  let review;
  try {
    review = await get(`/reviews/monthly/${summary.id}`);
  } catch (e) {
    return {
      label,
      employeeId: summary.employeeId ?? null,
      reviewId: summary.id,
      findings: [{ kind: 'REVIEW_FETCH_FAILED', detail: e.message }],
      rows: 0,
    };
  }

  const employeeId = review.employeeId ?? summary.employeeId;
  const rows = review.rows ?? [];

  // ── the authority the row SHOULD have come from ──
  let assignmentItems = null;
  let templateItems = null;
  let templateName = null;
  try {
    const assignments = await get(
      `/kra-assignments?employeeId=${encodeURIComponent(employeeId)}&limit=50`,
    );
    const list = Array.isArray(assignments)
      ? assignments
      : (assignments?.items ?? []);
    const chosen =
      list.find((a) => (a.items?.length ?? 0) > 0 || a.templateId || a.template?.id) ??
      list[0];
    if (!chosen) {
      findings.push({
        kind: 'NO_ASSIGNMENT',
        detail:
          'no KRA assignment — the reviewer can only come from the default template',
      });
    } else {
      assignmentItems = chosen.items ?? [];
      const templateId = chosen.template?.id ?? chosen.templateId;
      templateName = chosen.template?.name ?? chosen.templateName ?? null;
      if (templateId) {
        const template = await get(`/kra-templates/${templateId}`);
        templateName = template?.name ?? templateName;
        templateItems = template?.items ?? [];
      }
    }
  } catch (e) {
    findings.push({ kind: 'AUTHORITY_FETCH_FAILED', detail: e.message });
  }

  // Index the authority by BOTH normalised name and sort order, mirroring how
  // the app and the backend match a row to its source.
  const authorityByName = new Map();
  const authorityByOrder = new Map();
  const remember = (items, pick) => {
    for (const it of items ?? []) {
      const reviewer = canonReviewer(pick(it));
      if (!reviewer) continue;
      const order = Number(it.sortOrder ?? it.sort_order);
      if (!authorityByName.has(norm(it.name))) {
        authorityByName.set(norm(it.name), reviewer);
      }
      if (Number.isFinite(order) && !authorityByOrder.has(order)) {
        authorityByOrder.set(order, reviewer);
      }
    }
  };
  // Assignment item first: it is the per-employee override and outranks the
  // shared template, which is the whole basis of a per-employee exception.
  remember(assignmentItems, (it) => it.reviewerGroup ?? it.reviewer_group);
  remember(templateItems, (it) => it.scoreSource ?? it.reviewerGroup ?? it.score_source);

  // ── per-row checks ──
  let weightTotal = 0;
  let selfScored = 0;
  const perReviewer = { MANAGER: [0, 0], HR: [0, 0], ACCOUNTS: [0, 0] };

  for (const row of rows) {
    weightTotal += Number(row.weightagePercent ?? 0);
    if (scoreOf(row, 'SELF_RATING') !== null) selfScored++;

    const actual = canonReviewer(row.reviewerGroup);
    if (!actual) {
      findings.push({
        kind: 'NO_REVIEWER',
        kra: row.name,
        detail: 'row carries no reviewer; screens fall back to the manager',
      });
    } else if (!['MANAGER', 'HR', 'ACCOUNTS'].includes(actual)) {
      findings.push({
        kind: 'UNKNOWN_REVIEWER',
        kra: row.name,
        detail: `reviewer "${row.reviewerGroup}" is not one the app rates with`,
      });
    }

    const expected =
      authorityByName.get(norm(row.name)) ??
      authorityByOrder.get(Number(row.displayOrder));
    if (expected && actual && expected !== actual) {
      findings.push({
        kind: 'REVIEWER_MISMATCH',
        kra: row.name,
        detail: `row says ${actual}, its template/assignment says ${expected}`,
      });
    }

    const owner = actual && ['MANAGER', 'HR', 'ACCOUNTS'].includes(actual)
      ? actual
      : 'MANAGER';
    const stage = reviewStageFor(owner);
    perReviewer[owner][1]++;
    const reviewerScored = stage && scoreOf(row, stage) !== null;
    if (reviewerScored) perReviewer[owner][0]++;

    // Rated out of order: a reviewer (or management) scored a KRA the employee
    // never self-rated. The sheet used to allow this — it offered a Rate button
    // on months nobody had self-rated — and the reporting manager's score is
    // meant to be CAPPED by the self score, so these rows had no ceiling.
    const selfScored = scoreOf(row, 'SELF_RATING') !== null;
    if (!selfScored && reviewerScored) {
      findings.push({
        kind: 'REVIEWED_BEFORE_SELF',
        kra: row.name,
        detail: `${owner} scored this KRA but the employee never self-rated it`,
      });
    }
    if (!selfScored && scoreOf(row, 'MANAGEMENT_REVIEW') !== null) {
      findings.push({
        kind: 'MANAGEMENT_BEFORE_SELF',
        kra: row.name,
        detail: 'management scored a KRA the employee never self-rated',
      });
    }
  }

  if (rows.length > 0 && Math.abs(weightTotal - 100) > 0.5) {
    findings.push({
      kind: 'WEIGHTAGE',
      detail: `KRA weightages sum to ${weightTotal.toFixed(1)}%, not 100% — ` +
        'every score on the sheet is weighted by these',
    });
  }

  // ── cursor vs work ──
  //
  // The check that explains the compliance report reading "Submitted" and
  // "Approved" for someone who had rated almost nothing.
  const cursor = String(review.currentStage ?? '').toUpperCase();
  const cursorAt = stageIndex(cursor);
  const mgmtScored = rows.some(
    (r) => scoreOf(r, 'MANAGEMENT_REVIEW') !== null,
  );
  const locked = Boolean(review.managementLockedAt);
  const records = review.stageRecords ?? {};

  if (cursorAt > stageIndex('SELF_RATING') && selfScored < rows.length) {
    findings.push({
      kind: 'CURSOR_AHEAD_OF_WORK',
      detail:
        `cursor is at ${cursor} but only ${selfScored}/${rows.length} KRAs ` +
        'carry a self score',
    });
  }
  if (cursorAt > stageIndex('MANAGEMENT_REVIEW') && !mgmtScored && !locked) {
    findings.push({
      kind: 'CURSOR_PAST_UNDONE_MANAGEMENT',
      detail:
        `cursor is at ${cursor} but management never scored or locked ` +
        'anything — the review passed its last gate without being signed off',
    });
  }

  return {
    label,
    employeeId,
    reviewId: review.id,
    templateName,
    cursor,
    rows: rows.length,
    weightTotal: Number(weightTotal.toFixed(1)),
    selfScored,
    perReviewer,
    locked,
    hasSelfRecord: Boolean(records.SELF_RATING ?? records.selfRating),
    findings,
  };
}

// ── Report ──────────────────────────────────────────────────────────

const SEVERITY = {
  REVIEWER_MISMATCH: 'BLOCKER',
  UNKNOWN_REVIEWER: 'BLOCKER',
  WEIGHTAGE: 'BLOCKER',
  CURSOR_PAST_UNDONE_MANAGEMENT: 'BLOCKER',
  REVIEWED_BEFORE_SELF: 'BLOCKER',
  MANAGEMENT_BEFORE_SELF: 'BLOCKER',
  CURSOR_AHEAD_OF_WORK: 'WARN',
  NO_REVIEWER: 'WARN',
  NO_ASSIGNMENT: 'WARN',
  REVIEW_FETCH_FAILED: 'WARN',
  AUTHORITY_FETCH_FAILED: 'WARN',
};

function print(results) {
  const pad = (s, n) => String(s).padEnd(n).slice(0, n);
  console.log(
    `\nKRA mapping audit — ${String(month).padStart(2, '0')}/${year} — ${BASE}\n`,
  );

  console.log(
    pad('EMPLOYEE', 34),
    pad('TEMPLATE', 24),
    pad('KRAS', 5),
    pad('WT%', 6),
    pad('SELF', 6),
    pad('MGR', 6),
    pad('HR', 6),
    pad('ACCT', 6),
    'CURSOR',
  );
  console.log('-'.repeat(120));

  for (const r of results) {
    const [m, mt] = r.perReviewer?.MANAGER ?? [0, 0];
    const [h, ht] = r.perReviewer?.HR ?? [0, 0];
    const [a, at] = r.perReviewer?.ACCOUNTS ?? [0, 0];
    const flag = r.findings.some((f) => SEVERITY[f.kind] === 'BLOCKER')
      ? '🔴'
      : r.findings.length > 0
        ? '⚠ '
        : '  ';
    console.log(
      pad(`${flag}${r.label}`, 34),
      pad(r.templateName ?? '—', 24),
      pad(r.rows, 5),
      pad(r.weightTotal ?? '—', 6),
      pad(`${r.selfScored}/${r.rows}`, 6),
      pad(mt ? `${m}/${mt}` : '—', 6),
      pad(ht ? `${h}/${ht}` : '—', 6),
      pad(at ? `${a}/${at}` : '—', 6),
      r.cursor ?? '—',
    );
  }

  const withFindings = results.filter((r) => r.findings.length > 0);
  if (withFindings.length === 0) {
    console.log('\n✅ No mapping or state problems found.\n');
    return;
  }

  console.log(`\n${'='.repeat(120)}\nFINDINGS\n`);
  for (const r of withFindings) {
    console.log(`\n${r.label}  ·  review ${r.reviewId}`);
    for (const f of r.findings) {
      const sev = SEVERITY[f.kind] ?? 'WARN';
      const mark = sev === 'BLOCKER' ? '🔴' : '⚠ ';
      console.log(
        `  ${mark} ${f.kind}${f.kra ? ` [${f.kra}]` : ''}\n       ${f.detail}`,
      );
    }
  }

  // Counts by kind, so a systemic problem is obvious from one line rather than
  // by reading 42 blocks.
  const byKind = {};
  for (const r of withFindings) {
    for (const f of r.findings) byKind[f.kind] = (byKind[f.kind] ?? 0) + 1;
  }
  console.log(`\n${'='.repeat(120)}\nSUMMARY\n`);
  console.log(`  employees audited: ${results.length}`);
  console.log(`  employees with findings: ${withFindings.length}`);
  for (const [kind, count] of Object.entries(byKind).sort(
    (x, y) => y[1] - x[1],
  )) {
    console.log(`  ${pad(kind, 34)} ${count}`);
  }
  console.log('');
}

async function main() {
  const user = await login();
  console.error(
    `signed in as ${user?.email ?? EMAIL} (${user?.role ?? 'role unknown'})`,
  );

  const summaries = await getAll(`/reviews/monthly?year=${year}&month=${month}`);
  if (summaries.length === 0) {
    console.log(`\nNo monthly reviews for ${month}/${year}.\n`);
    return;
  }
  console.error(`auditing ${summaries.length} reviews…`);

  // Batched so a cold-started backend is not buried, matching what the app does.
  const results = [];
  const batchSize = 5;
  for (let i = 0; i < summaries.length; i += batchSize) {
    const batch = summaries.slice(i, i + batchSize);
    results.push(...(await Promise.all(batch.map(auditEmployee))));
    process.stderr.write(
      `\r  ${Math.min(i + batchSize, summaries.length)}/${summaries.length}`,
    );
  }
  process.stderr.write('\n');

  results.sort((a, b) => a.label.localeCompare(b.label));

  if (args.json) {
    console.log(JSON.stringify({ base: BASE, year, month, results }, null, 2));
  } else {
    print(results);
  }

  // Non-zero exit on a blocker, so this can gate a release.
  const blockers = results.filter((r) =>
    r.findings.some((f) => SEVERITY[f.kind] === 'BLOCKER'),
  );
  if (blockers.length > 0) process.exitCode = 1;
}

main().catch((e) => {
  console.error(`\nFAILED: ${e.message}`);
  process.exit(1);
});
