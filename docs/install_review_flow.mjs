/**
 * Adds a per-organization review flow.
 *
 *     node D:\Vistar\krafrontend\docs\install_review_flow.mjs --dry
 *     node D:\Vistar\krafrontend\docs\install_review_flow.mjs
 *
 * Idempotent; backs each file up as <name>.bak before writing.
 *
 * RUN THE SQL IN docs/add_review_flow_column.sql FIRST — this patches code that
 * reads a column, and without the column every organizations read would 500.
 *
 * ── THE TWO FLOWS ───────────────────────────────────────────────────────────
 *
 *   STANDARD    self -> (reporting manager | HR | Accounts) -> management
 *               -> payout.  The original pipeline. THE DEFAULT.
 *   ADMIN_ONLY  (HR | Accounts) -> management -> payout.  The standard
 *               pipeline with EXACTLY two stages removed: the employee's
 *               self-rating and the reporting-manager rating.  HR and Accounts
 *               still rate their own seats and management still signs off --
 *               an earlier draft of this comment also dropped the Accounts
 *               rating, and the code matched it, which left every
 *               Accounts-assigned KRA with no eligible rater at all.
 *
 * ── WHY THE DEFAULT MATTERS SO MUCH ─────────────────────────────────────────
 *
 * Every existing organization must keep running STANDARD. The column therefore
 * defaults to it at the database level, the API omits the field rather than
 * guessing, and the client resolves anything unknown or absent to STANDARD.
 * Three independent layers all fail in the same safe direction, because the
 * failure in the other direction — silently switching a live tenant to
 * ADMIN_ONLY — would strip every employee's ability to rate themselves.
 *
 * ── WHAT CHANGES ────────────────────────────────────────────────────────────
 *
 *   1. organizations.routes.js  reviewFlow accepted on create + patch,
 *                               returned by every read
 *   2. auth.service.js          reviewFlow included in the login and /auth/me
 *                               user payload
 *
 * Step 2 is the one that makes the feature real for anyone other than a super
 * admin: `/organizations` is SUPER_ADMIN-only, so HR, managers and employees
 * have no other way to learn which pipeline their own organization runs.
 */
import fs from 'fs';

// `--kra=<dir>` rebases every path onto a COPY of the dist tree, so the patch
// can be rehearsed and the result syntax-checked (`node --check`) before the
// deployed files are touched. Rehearsing found a real defect in this script:
// edit 2b's marker matched login()'s deeper-indented copy as a substring and
// reported "already present" without applying.
const kraArg = process.argv.find((a) => a.startsWith('--kra='));
const KRA = kraArg
  ? kraArg.slice('--kra='.length)
  : 'D:/Vistar/vistar_CRM/src/modules/kra/dist';
const ORG = `${KRA}/features/organizations/organizations.routes.js`;
const AUTH = `${KRA}/features/auth/auth.service.js`;
const REPO = `${KRA}/features/auth/auth.repository.js`;
const DRY = process.argv.includes('--dry');

const EDITS = [
  // ── 1. organizations: validate, persist and return the flow ──────────────
  {
    file: ORG,
    marker: 'reviewFlowEnum',
    find: "const CreateOrganizationSchema = zod_1.z.object({",
    replace:
      "// STANDARD is the default at every layer. Anything unrecognised is not an\n" +
      "// error either — the client resolves it to STANDARD too.\n" +
      "const reviewFlowEnum = zod_1.z.enum(['STANDARD', 'ADMIN_ONLY']);\n" +
      "const CreateOrganizationSchema = zod_1.z.object({",
  },
  {
    file: ORG,
    marker: 'reviewFlow: reviewFlowEnum.optional()',
    find: "    logoUrl: zod_1.z.string().url().max(500).nullable().optional(),\n});",
    replace:
      "    logoUrl: zod_1.z.string().url().max(500).nullable().optional(),\n" +
      "    reviewFlow: reviewFlowEnum.optional(),\n});",
  },
  {
    file: ORG,
    marker: "reviewFlow: reviewFlowEnum.optional(),\n})\n",
    find:
      "    logoUrl: zod_1.z.string().url().max(500).nullable().optional(),\n})",
    replace:
      "    logoUrl: zod_1.z.string().url().max(500).nullable().optional(),\n" +
      "    reviewFlow: reviewFlowEnum.optional(),\n})",
  },
  {
    file: ORG,
    marker: 'reviewFlow: org.reviewFlow',
    find: "        logoUrl: org.logoUrl ?? null,",
    replace:
      "        logoUrl: org.logoUrl ?? null,\n" +
      "        // Always returned, defaulted here as well as in the column, so a\n" +
      "        // row written before the migration still reads as STANDARD.\n" +
      "        reviewFlow: org.reviewFlow ?? 'STANDARD',",
  },
  {
    file: ORG,
    marker: "reviewFlow: req.body.reviewFlow ?? 'STANDARD'",
    find:
      "                name: req.body.name,\n" +
      "                slug: req.body.slug,\n" +
      "                logoUrl: req.body.logoUrl ?? null,",
    replace:
      "                name: req.body.name,\n" +
      "                slug: req.body.slug,\n" +
      "                logoUrl: req.body.logoUrl ?? null,\n" +
      "                reviewFlow: req.body.reviewFlow ?? 'STANDARD',",
  },
  {
    file: ORG,
    marker: 'data.reviewFlow = req.body.reviewFlow',
    find:
      "    if (req.body.logoUrl !== undefined)\n" +
      "        data.logoUrl = req.body.logoUrl;",
    replace:
      "    if (req.body.logoUrl !== undefined)\n" +
      "        data.logoUrl = req.body.logoUrl;\n" +
      "    if (req.body.reviewFlow !== undefined)\n" +
      "        data.reviewFlow = req.body.reviewFlow;",
  },

  // ── 2. auth: every role learns its own organization's flow ───────────────
  {
    file: AUTH,
    marker: 'reviewFlow:',
    find: "                organizationId: user.organizationId,",
    replace:
      "                organizationId: user.organizationId,\n" +
      "                // The pipeline this user's organization runs. Included here\n" +
      "                // because /organizations is SUPER_ADMIN-only, so no other\n" +
      "                // role can look it up. Absent/unknown resolves to STANDARD\n" +
      "                // on the client.\n" +
      "                reviewFlow: user.organization?.reviewFlow ?? 'STANDARD',",
  },

  // ── 2b. auth: /auth/me must return it TOO ────────────────────────────────
  //
  // login() and getMe() build the user payload SEPARATELY, and step 2 only
  // patched login(). Its anchor carries login's 16-space nesting, so it could
  // never have matched getMe's 12-space one — and its marker ('reviewFlow:')
  // is satisfied by login's copy, so a re-run reports "already present" and
  // moves on. Both facts hid the gap.
  //
  // The consequence was the whole feature quietly reverting. The client
  // rehydrates its session from /auth/me on every boot, page reload and
  // organisation switch (see adoptTokens -> refreshCurrentUser), and
  // refreshCurrentUser OVERWRITES the stored user with that payload. So:
  //
  //     log in            -> reviewFlow: 'ADMIN_ONLY'   the sheet is correct
  //     reload the page   -> field absent -> 'STANDARD'  the sheet reverts
  //
  // On a hot-reloading dev server that is a few seconds. The visible symptom
  // was an ADMIN_ONLY organisation whose sheet still showed the Self column,
  // still labelled a row "Reviewed by Manager", and parked a "waiting on Self"
  // chip in every Review cell — so HR could not rate, because it was waiting
  // on a self-rating the flow had removed.
  //
  // findUserById already includes the relation (step 3), so the value is
  // sitting on the row; getMe just never serialised it.
  {
    file: AUTH,
    // NOT the patched line itself: login()'s copy is the same text at deeper
    // indentation, so `src.includes(...)` matches it as a substring and the
    // edit reports "already present" without ever having applied. Marker text
    // must be unique to THIS edit — a sentence only this edit inserts.
    marker: "MUST match login()'s payload",
    find:
      "            organizationId: user.organizationId,\n" +
      "            projectLocationId: user.projectLocationId,",
    replace:
      "            organizationId: user.organizationId,\n" +
      "            // MUST match login()'s payload. The client rebuilds its whole\n" +
      "            // user object from this response, so a field that is missing\n" +
      "            // here is not merely absent — it is ERASED on the next boot.\n" +
      "            reviewFlow: user.organization?.reviewFlow ?? 'STANDARD',\n" +
      "            projectLocationId: user.projectLocationId,",
  },

  // ── 3. auth.repository: actually LOAD the relation ───────────────────────
  //
  // Without these, step 2 is a no-op that always answers 'STANDARD'.
  // findUserByIdentifier and findUserById are bare findUnique/findMany calls,
  // so `user.organization` is undefined and the `?? 'STANDARD'` fallback wins
  // every time — the feature would appear to work for a super admin (who reads
  // the flow from /organizations) and silently do nothing for everybody else.
  //
  // Adding an include is additive: nothing else reads these rows positionally,
  // and only reviewFlow is selected, so no extra columns cross the wire.
  {
    file: REPO,
    marker: 'ORG_REVIEW_FLOW_INCLUDE',
    find: 'exports.authRepository = {',
    replace:
      "// Only the one column the auth payload needs — selecting the whole\n" +
      "// organization row would ship name, slug and logo on every login.\n" +
      "const ORG_REVIEW_FLOW_INCLUDE = { organization: { select: { reviewFlow: true } } };\n" +
      'exports.authRepository = {',
  },
  {
    file: REPO,
    marker: 'employeeCode: identifier }, include: ORG_REVIEW_FLOW_INCLUDE',
    find:
      "        const byCode = await database_1.prisma.employee.findUnique({ where: { employeeCode: identifier } });",
    replace:
      "        const byCode = await database_1.prisma.employee.findUnique({ where: { employeeCode: identifier }, include: ORG_REVIEW_FLOW_INCLUDE });",
  },
  {
    file: REPO,
    marker: 'take: 2, include: ORG_REVIEW_FLOW_INCLUDE',
    find:
      "        const byEmail = await database_1.prisma.employee.findMany({ where: { email: identifier }, take: 2 });",
    replace:
      "        const byEmail = await database_1.prisma.employee.findMany({ where: { email: identifier }, take: 2, include: ORG_REVIEW_FLOW_INCLUDE });",
  },
  {
    file: REPO,
    marker: 'where: { id }, include: ORG_REVIEW_FLOW_INCLUDE',
    find:
      "        return database_1.prisma.employee.findUnique({ where: { id } });",
    replace:
      "        return database_1.prisma.employee.findUnique({ where: { id }, include: ORG_REVIEW_FLOW_INCLUDE });",
  },
];

let applied = 0;
let skipped = 0;
let failed = 0;
const backedUp = new Set();

for (const e of EDITS) {
  const name = e.file.split('/').pop();
  if (!fs.existsSync(e.file)) {
    console.error(`  FAIL   ${name} — not found. Run install_organizations_api.mjs first?`);
    failed++;
    continue;
  }

  const src = fs.readFileSync(e.file, 'utf8');
  const eol = src.includes('\r\n') ? '\r\n' : '\n';
  const N = (t) => t.split('\n').join(eol);

  if (src.includes(N(e.marker))) {
    console.log(`  SKIP   ${name} — "${e.marker.split('\n')[0]}" already present`);
    skipped++;
    continue;
  }

  const find = N(e.find);
  const hits = src.split(find).length - 1;
  if (hits !== 1) {
    console.error(
      `  FAIL   ${name} — anchor matched ${hits} times, expected 1 ` +
        `(${e.marker.split('\n')[0]}). Patch by hand.`,
    );
    failed++;
    continue;
  }

  if (DRY) {
    console.log(`  WOULD  ${name} — ${e.marker.split('\n')[0]}`);
    applied++;
    continue;
  }

  if (!backedUp.has(e.file)) {
    fs.copyFileSync(e.file, `${e.file}.bak`);
    backedUp.add(e.file);
  }
  fs.writeFileSync(e.file, src.replace(find, N(e.replace)), 'utf8');
  console.log(`  OK     ${name} — ${e.marker.split('\n')[0]}`);
  applied++;
}

console.log('');
if (DRY) {
  console.log(`dry run: ${applied} would apply, ${skipped} already done, ${failed} failed`);
} else {
  console.log(`applied=${applied} skipped=${skipped} failed=${failed}`);
  if (failed === 0) {
    console.log('');
    console.log('Next: restart / redeploy the API, then set a flow from the');
    console.log('Organizations screen (Edit -> Review flow).');
    console.log('');
    console.log('Verify it reached every role, not just the super admin:');
    console.log('  POST /auth/login    -> data.user.reviewFlow is present');
    console.log('  GET  /auth/me       -> reviewFlow is present  <-- CHECK THIS ONE');
    console.log('  GET  /organizations -> each row has reviewFlow');
    console.log('');
    console.log('/auth/me is the one that matters most and the one that was');
    console.log('missing. The client rebuilds its user from it on every boot,');
    console.log('reload and org switch, so if login has the field and /auth/me');
    console.log('does not, the flow works until the first reload and then');
    console.log('silently reverts to STANDARD.');
    console.log('If BOTH omit reviewFlow, the auth.repository include did not');
    console.log('apply — check the 4 REPO edits above.');
    for (const f of backedUp) {
      const n = f.split('/').pop();
      console.log(`  restore: copy ${n}.bak ${n}`);
    }
  }
}

process.exit(failed > 0 ? 1 : 0);
