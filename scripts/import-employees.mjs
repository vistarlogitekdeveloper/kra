// Bulk upsert the employee master sheet into the live KRA backend.
//
// Usage:
//   KRA_EMAIL=you@vistarlogitek.com KRA_PASSWORD='...' node scripts/import-employees.mjs
//   KRA_EMAIL=... KRA_PASSWORD='...' node scripts/import-employees.mjs --apply
//
// DRY RUN BY DEFAULT — it prints exactly what it would create and change and
// writes nothing. Pass --apply to actually send the requests.
//
// Idempotent: matches on EMP. ID (employeeCode), so re-running updates instead
// of duplicating. Safe to run repeatedly.
//
// Two passes, because a reporting manager may not exist yet when their report is
// created: pass 1 upserts everyone, pass 2 resolves manager NAMES to ids and
// patches the reporting line.
//
// It deliberately does NOT touch `role` on employees that already exist. Access
// roles are granted separately (see docs/ACCESS_CONTROL_DESIGN.md) and re-deriving
// them from job titles here would wipe any override — e.g. resetting an HR admin
// back to MANAGER just because their title says "Commercial Manager".

const BASE = process.env.KRA_BASE ?? 'https://vistar-crm.onrender.com/api/v1/kra';
const EMAIL = process.env.KRA_EMAIL;
const PASSWORD = process.env.KRA_PASSWORD;
const APPLY = process.argv.includes('--apply');

// ─────────────────────────────────────────────────────────────────────────────
// The master sheet. `incentive` is the monthly Performance Incentive.
//
// joinedDate is deliberately ABSENT: 26 of the 38 rows were column-truncated to
// "########" in the source, and the visible ones are ambiguous (4/8/2026 could be
// 4 Aug or 8 Apr). Guessing would write wrong employment records, so dates are
// left for a follow-up with unambiguous values.
// ─────────────────────────────────────────────────────────────────────────────
const EMPLOYEES = [
  ['VLPL0002', 'Chetan Bhagwat Bhangale', 'chetan.bhangale@vistarlogitek.com', 'A4', 'Head Office, Pune', 'Cluster Manager-Tpt', 'Transportation', 'Prashant Ramchandra Tamhankar', 8000],
  ['VLPL0003', 'Pravin Suryakant Wakchware', 'manager.endurance@vistarlogitek.com', 'A4', 'Endurance B-22, Chakan', 'Manager', 'Wh-Operation', 'Amol Laxman Veer', 10000],
  ['VLPL0008', 'Govind Bapurao Tapkeer', 'manager.bekaert@vistarlogitek.com', 'A4', 'Bekaert, Ranjangaon', 'Manager', 'Wh-Operation', 'Dattatray Dadabhau Zanjad', 2000],
  ['VLPL0099', 'Sagar Ananda Sasane', 'manager.commercial@vistarlogitek.com', 'A4', 'Head Office, Pune', 'Commercial Manager', 'Accounts & Finance', 'Prashant Ramchandra Tamhankar', 8000],
  ['VLPL0107', 'Muralidharan Krishnan', 'muralidharan.k@vistarlogitek.com', 'M1', 'Head Office, Pune', 'Regional Manager-Ka', 'Wh-Operation', 'Prashant Ramchandra Tamhankar', 4000],
  ['VLPL0123', 'Amol Laxman Veer', 'amol.veer@vistarlogitek.com', 'M1', 'Head Office, Pune', 'Regional Manager', 'Wh-Operation', 'Prashant Ramchandra Tamhankar', 12000],
  ['VLPL0156', 'Dinesh Dnyaneshwar Gawade', 'manager.eaton@vistarlogitek.com', 'A4', 'Eaton, Ranjangaon', 'Manager', 'Wh-Operation', 'Dattatray Dadabhau Zanjad', 5000],
  ['VLPL0242', 'Vikram Vilas Desai', 'vikramdesai955@gmail.com', 'A2', 'Karl Dungs, Hinjewadi', 'Project Incharge', 'Wh-Operation', 'Prakash Haibatrao Shivale', 3000],
  ['VLPL0375', 'Sameer Suresh Shinde', 'sameer.shinde@vistarlogitek.com', 'A4', 'Eaton, Magarpatta', 'Cluster Manager', 'Wh-Operation', 'Amol Laxman Veer', 2000],
  ['VLPL0389', 'Ravish N', 'manager.ss@vistarlogitek.com', 'A2', 'Schwing Stetter, Bangalore', 'Project Incharge', 'Wh-Operation', 'Muralidharan Krishnan', 3000],
  ['VLPL0413', 'Ravikumar M', 'smartravi220@gmail.com', 'A2', 'Bosch, Bangalore', 'Project Incharge', 'Wh-Operation', 'Sajith Vasu', 2000],
  ['VLPL0419', 'Pradeep P', 'manager.vst@vistarlogitek.com', 'A2', 'Vst, Bangalore', 'Project Incharge', 'Wh-Operation', 'Sajith Vasu', 2500],
  ['VLPL0469', 'Sajith Vasu', 'sajith.v@vistarlogitek.com', 'A4', 'Vst, Bangalore', 'Cluster Manager', 'Wh-Operation', 'Muralidharan Krishnan', 7000],
  ['VLPL0527', 'Manojkumar Foran Singh', 'mfsingh97@gmail.com', 'A2', 'Grupo, Sanand', 'Project Incharge', 'Wh-Operation', 'Balasaheb Shivaji Chavan', 3000],
  ['VLPL0591', 'Bholenath Prakash Sagat', 'manager.adept@vistarlogitek.com', 'A4', 'Adept, Pune', 'Manager', 'Wh-Operation', 'Prakash Haibatrao Shivale', 4000],
  ['VLPL0610', 'Swati Raghunath Kotkar', 'hr@vistarlogitek.com', 'A2', 'Head Office, Pune', 'Senior Officer-Hr', 'HR', 'Sagar Ananda Sasane', 5000],
  ['VLPL0648', 'Shivaraja V', 'shivaraja.gowda.104@gmail.com', 'A2', 'Chai Point, Bangalore', 'Senior Officer', 'Wh-Operation', 'Sajith Vasu', 2000],
  ['VLPL0718', 'Pravin Vilas Lole', 'pravin.lole@vistarlogitek.com', 'A4', 'Head Office, Pune', 'Manager', 'Wh-Operation', 'Mariappan Mookiah Acharya', 7000],
  ['VLPL0752', 'Rajesh Subhash Wagh', 'rajesh.wagh@vistarlogitek.com', 'A4', 'Cnh, Chakan', 'Manager', 'Wh-Operation', 'Amol Laxman Veer', 5000],
  ['VLPL0767', 'Milind Vijay Ingole', 'managercp.pune@vistarlogitek.com', 'A2', 'Chai Point, Pune', 'Project Incharge', 'Wh-Operation', 'Amol Laxman Veer', 1000],
  ['VLPL0830', 'Mahendra Sahebrao Mahajan', 'manager.danfoss@vistarlogitek.com', 'A3', 'Danfoss, Magarpatta', 'Assistant Manager', 'Wh-Operation', 'Amol Laxman Veer', 2000],
  ['VLPL0872', 'Kishor Yashwant Bhalerao', 'manager.maxion@vistarlogitek.com', 'A2', 'Maxion, Khed', 'Senior Officer', 'Wh-Operation', 'Amol Laxman Veer', 3000],
  ['VLPL0883', 'Dattatray Dadabhau Zanjad', 'dattatray.zanjad@vistarlogitek.com', 'A4', 'Eaton, Ranjangaon', 'Cluster Manager', 'Wh-Operation', 'Amol Laxman Veer', 2000],
  ['VLPL1170', 'Manoj Dattatray Kedari', 'manager.sspune@vistarlogitek.com', 'A2', 'Schwing Stetter, Pune', 'Project Incharge', 'Wh-Operation', 'Amol Laxman Veer', 4000],
  ['VLPL1223', 'Balasaheb Shivaji Chavan', 'balasaheb.chavan@vistarlogitek.com', 'M1', 'Head Office, Pune', 'Regional Manager', 'Wh-Operation', 'Prashant Ramchandra Tamhankar', 10000],
  ['VLPL1285', 'Poonam Dnyandev Pawar', 'accounts@vistarlogitek.com', 'A2', 'Head Office, Pune', 'Sr. Accountant', 'Accounts & Finance', 'Sagar Ananda Sasane', 2000],
  ['VLPL1300', 'Ganga Jha', 'jha.gangaa@gmail.com', 'A2', 'Knorr Bremse, Hinjewadi', 'Senior Officer', 'Wh-Operation', 'Prakash Haibatrao Shivale', 2000],
  ['VLPL1329', 'Prakash Haibatrao Shivale', 'prakash.shivale@vistarlogitek.com', 'A4', 'Knorr Bremse, Hinjewadi', 'Cluster Manager', 'Wh-Operation', 'Amol Laxman Veer', 5000],
  ['VLPL1414', 'Parveez', 'manager.cpblr@vistarlogitek.com', 'A3', 'Chai Point, Bangalore', 'Assistant Manager', 'Wh-Operation', 'Sajith Vasu', 2000],
  ['VLPL1430', 'Sunil Subhash Bhutkar', 'sunilbhutkar786@gmail.com', 'A4', 'Schwing Stetter, Turbhe', 'Manager', 'Wh-Operation', 'Amol Laxman Veer', 2000],
  ['VLPL1432', 'Yash Ramesh Thikekar', 'Flutter.developer@vistarlogitek.com', 'A2', 'Head Office, Pune', 'Software Developer', 'IT Department', 'Swati Raghunath Kotkar', 3000],
  ['VLPL1436', 'Dattatraya Somnath Bamankar', 'dattatraya.bamankar@vistarlogitek.com', 'M2', 'Head Office, Pune', 'Sr. General Manager', 'Wh-Operation', 'Prashant Ramchandra Tamhankar', 40000],
  ['VLPL1443', 'Ganesh Dadarao Wani', 'ganesh.wani@vistarlogitek.com', 'A4', 'Maxion, Khed', 'Cluster Manager', 'Wh-Operation', 'Amol Laxman Veer', 5000],
  ['VLPL1447', 'Rahamat Ali', 'manager.kb@vistarlogitek.com', 'A4', 'Knorr Bremse, Hinjewadi', 'Manager', 'Wh-Operation', 'Prakash Haibatrao Shivale', 3000],
  ['VLPL1463', 'Amit Ramchandra Mane', 'amitmane1534@gmail.com', 'A4', 'Knorr Bremse, Hinjewadi', 'Manager', 'Wh-Operation', 'Prakash Haibatrao Shivale', 5000],
  ['VLPL1473', 'Atul Bhimrao Barge', 'atulbarge07@gmail.com', 'A2', 'Maxion, Khed', 'Project Incharge', 'Wh-Operation', 'Amol Laxman Veer', 5000],
  ['VLPL1474', 'Suraj Bharat Tithe', 'rst2118@gmail.com', 'A1', 'Maxion, Khed', 'Administrative Staff', 'Wh-Operation', 'Amol Laxman Veer', 1000],
  ['VLPL1633', 'Kisan Bhagvat Bhosale', 'kisan.bhosale@vistarlogitek.com', 'A4', 'Head Office, Pune', 'Cluster Manager', 'Wh-Operation', 'Amol Laxman Veer', 5000],
].map(([code, name, email, grade, location, designation, department, manager, incentive]) =>
  ({ code, name, email, grade, location, designation, department, manager, incentive }));

/// Checksum from the source sheet's total row — a transcription guard.
const EXPECTED_INCENTIVE_TOTAL = 196500;

/// Mirrors `_roleFromDesignation` in employee_form_screen.dart. Used ONLY when
/// creating someone new; existing employees keep whatever role they have.
function roleFromDesignation(designation) {
  const d = designation.toUpperCase();
  if (/CEO|FOUNDER|DIRECTOR|CHAIRMAN/.test(d)) return 'HR_ADMIN'; // MANAGEMENT once the backend accepts it
  if (d.includes('HR')) return 'HR';
  if (d.includes('ACCOUNT') || d.includes('FINANCE')) return 'FINANCE';
  if (/MANAGER|INCHARGE|IN-CHARGE|IN CHARGE/.test(d)) return 'MANAGER';
  return 'EMPLOYEE';
}

const norm = (s) => (s ?? '').trim().toLowerCase().replace(/\s+/g, ' ');

/// Name matching that tolerates a dropped middle name — the sheet lists Yash's
/// manager as "Swati Kotkar" while her own row reads "Swati Raghunath Kotkar".
/// Every match is printed so it can be audited rather than trusted blindly.
function findByName(name, employees) {
  const want = norm(name);
  const exact = employees.find((e) => norm(e.fullName) === want);
  if (exact) return { match: exact, exact: true };
  const wantTokens = want.split(' ').filter(Boolean);
  const partial = employees.filter((e) => {
    const have = norm(e.fullName).split(' ').filter(Boolean);
    return wantTokens.every((t) => have.includes(t));
  });
  return partial.length === 1 ? { match: partial[0], exact: false } : { match: null };
}

let token = null;

async function api(method, path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || json.success === false) {
    const err = json.error ?? {};
    throw new Error(
      `${method} ${path} → ${res.status} ${err.code ?? ''} ${err.message ?? ''} ` +
        `${err.details ? JSON.stringify(err.details) : ''}`.trim(),
    );
  }
  return json.data;
}

async function main() {
  const total = EMPLOYEES.reduce((a, e) => a + e.incentive, 0);
  if (total !== EXPECTED_INCENTIVE_TOTAL) {
    console.error(
      `✗ Incentive total is ${total}, expected ${EXPECTED_INCENTIVE_TOTAL} — ` +
        `the table was mis-transcribed. Refusing to run.`,
    );
    process.exit(1);
  }
  console.log(`✓ ${EMPLOYEES.length} rows, incentive total ₹${total} matches the sheet\n`);

  if (!EMAIL || !PASSWORD) {
    console.error('Set KRA_EMAIL and KRA_PASSWORD (an HR-admin account).');
    process.exit(1);
  }
  if (!APPLY) console.log('DRY RUN — nothing will be written. Re-run with --apply.\n');

  token = (await api('POST', '/auth/login', { email: EMAIL, password: PASSWORD })).accessToken;

  // Existing roster + locations, so we can match instead of blindly creating.
  const roster = (await api('GET', '/employees?page=1&limit=200')).employees ?? [];
  const locations = (await api('GET', '/locations?page=1&limit=200')).locations ?? [];
  const byCode = new Map(roster.map((e) => [String(e.employeeCode).toUpperCase(), e]));
  const locByName = new Map(locations.map((l) => [norm(l.name), l]));
  console.log(`Found ${roster.length} existing employees, ${locations.length} locations.\n`);

  const unmatchedLocations = new Set();
  const created = [];
  const updated = [];
  const unchanged = [];
  const failed = [];

  // ── Pass 1: upsert identity + employment fields (no reporting line yet) ──
  for (const row of EMPLOYEES) {
    const existing = byCode.get(row.code.toUpperCase());
    const loc = locByName.get(norm(row.location));
    if (!loc) unmatchedLocations.add(row.location);

    const fields = {
      name: row.name,
      email: row.email,
      position: row.designation,
      department: row.department,
      grade: row.grade,
      monthlyIncentiveAmount: row.incentive,
      ...(loc ? { projectLocationId: loc.id } : {}),
    };

    try {
      if (!existing) {
        const payload = {
          employeeCode: row.code,
          role: roleFromDesignation(row.designation),
          ...fields,
        };
        if (APPLY) {
          const emp = await api('POST', '/employees', payload);
          byCode.set(row.code.toUpperCase(), emp);
          roster.push(emp);
        }
        created.push(`${row.code}  ${row.name}  (role ${payload.role})`);
      } else {
        // Only send what actually differs, and never `role`.
        const changes = {};
        for (const [k, v] of Object.entries(fields)) {
          const before = k === 'projectLocationId' ? existing.projectLocationId : existing[k];
          if (String(before ?? '') !== String(v ?? '')) changes[k] = v;
        }
        if (Object.keys(changes).length === 0) {
          unchanged.push(`${row.code}  ${row.name}`);
        } else {
          if (APPLY) await api('PATCH', `/employees/${existing.id}`, changes);
          updated.push(`${row.code}  ${row.name}  →  ${Object.keys(changes).join(', ')}`);
        }
      }
    } catch (e) {
      failed.push(`${row.code}  ${row.name}  →  ${e.message}`);
    }
  }

  // ── Pass 2: reporting line, now that everyone exists ──
  const managerFixes = [];
  const unresolvedManagers = new Map();
  for (const row of EMPLOYEES) {
    const self = byCode.get(row.code.toUpperCase());
    if (!self) continue; // dry run, or pass 1 failed
    const { match, exact } = findByName(row.manager, roster);
    if (!match) {
      unresolvedManagers.set(row.manager, (unresolvedManagers.get(row.manager) ?? 0) + 1);
      continue;
    }
    if (match.id === self.id) {
      failed.push(`${row.code}  ${row.name}  →  reports to themselves; skipped`);
      continue;
    }
    if (self.managerId === match.id) continue;
    try {
      if (APPLY) await api('PATCH', `/employees/${self.id}`, { managerId: match.id });
      managerFixes.push(
        `${row.code}  ${row.name}  →  ${match.fullName}${exact ? '' : '  [fuzzy match — verify]'}`,
      );
    } catch (e) {
      failed.push(`${row.code}  ${row.name}  → manager: ${e.message}`);
    }
  }

  const section = (title, rows) => {
    if (!rows.length) return;
    console.log(`\n${title} (${rows.length})`);
    rows.forEach((r) => console.log(`  ${r}`));
  };

  section('CREATE', created);
  section('UPDATE', updated);
  section('REPORTING LINE', managerFixes);
  section('UNCHANGED', unchanged);
  section('FAILED', failed);

  if (unmatchedLocations.size) {
    console.log(`\nUNMATCHED PROJECT LOCATIONS (${unmatchedLocations.size})`);
    console.log('  Create these under HR → Locations, then re-run:');
    [...unmatchedLocations].sort().forEach((l) => console.log(`  - ${l}`));
  }
  if (unresolvedManagers.size) {
    console.log(`\nUNRESOLVED REPORTING MANAGERS (${unresolvedManagers.size})`);
    console.log('  Not present in the sheet, so they have no employee record:');
    [...unresolvedManagers].forEach(([n, c]) => console.log(`  - ${n}  (${c} report(s))`));
  }

  console.log(
    `\n${APPLY ? 'Applied' : 'Would apply'}: ${created.length} created, ` +
      `${updated.length} updated, ${managerFixes.length} reporting lines, ` +
      `${unchanged.length} unchanged, ${failed.length} failed.`,
  );
  if (!APPLY) console.log('Re-run with --apply to write.');
}

main().catch((e) => {
  console.error(`\n✗ ${e.message}`);
  process.exit(1);
});
