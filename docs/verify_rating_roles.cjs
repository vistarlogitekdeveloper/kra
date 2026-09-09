// Verifies the per-stage rating gate, using EACH FILE'S OWN gate logic.
//
// The point of before/after is to reproduce what the deployed server actually
// does. The deployed code compares user.role flat against ACTOR_ROLES; the
// patched code resolves through rolesHeldBy(). An earlier version of this
// harness applied the PATCHED logic to the UNPATCHED table, which made the
// SUPER_ADMIN rows look like they already passed. They do not.
const fs = require('fs');
const path = require('path');
const KRA = 'D:/Vistar/vistar_CRM/src/modules/kra/dist';
const { rolesHeldBy } = require(path.join(KRA, 'middleware/rbac.middleware.js'));

const file = process.argv[2];
const src = fs.readFileSync(file, 'utf8');

// ACTOR_ROLES is lifted verbatim from the file — never retyped — so this check
// cannot drift from the table it is checking.
const m = src.match(/const ACTOR_ROLES = \{[\s\S]*?\n\};/);
if (!m) throw new Error('could not lift ACTOR_ROLES out of ' + file);
const ACTOR_ROLES = eval('(' + m[0].replace(/^const ACTOR_ROLES = /, '').replace(/;$/, '') + ')');

// Which gate does THIS file use? Detected from the source, not assumed.
const hierarchical = /function canActOnStage\(user, stage\)/.test(src);
const canAct = hierarchical
  ? (role, stage) => (ACTOR_ROLES[stage] || []).some((r) => rolesHeldBy(role).includes(r))
  : (role, stage) => (ACTOR_ROLES[stage] || []).includes(role);

const CASES = [
  ['MANAGEMENT',  'MANAGEMENT_REVIEW', true,  'THE REPORTED BUG: management sign-off'],
  ['SUPER_ADMIN', 'MANAGEMENT_REVIEW', true,  'super admin inherits the sign-off'],
  ['SUPER_ADMIN', 'ACCOUNT_HR_RATING', true,  'super admin inherits the HR seat'],
  ['SUPER_ADMIN', 'FINANCE_RATING',    true,  'super admin inherits the Accounts seat'],
  ['SUPER_ADMIN', 'INCENTIVE_PAYOUT',  true,  'super admin inherits payout'],
  ['HR_ADMIN',    'MANAGEMENT_REVIEW', true,  'UNCHANGED: HR_ADMIN keeps the sign-off'],
  ['HR',          'ACCOUNT_HR_RATING', true,  'UNCHANGED: HR rates the HR seat'],
  ['FINANCE',     'FINANCE_RATING',    true,  'UNCHANGED: Accounts rates its seat'],
  ['EMPLOYEE',    'MANAGEMENT_REVIEW', false, 'an employee must never sign off'],
  ['EMPLOYEE',    'ACCOUNT_HR_RATING', false, 'an employee must never rate the HR seat'],
  ['MANAGER',     'MANAGEMENT_REVIEW', false, 'a line manager must never sign off'],
  ['MANAGER',     'ACCOUNT_HR_RATING', false, 'a line manager must never rate the HR seat'],
  ['HR',          'FINANCE_RATING',    false, 'HR must NOT gain the Accounts seat'],
  ['HR_ADMIN',    'FINANCE_RATING',    false, 'left as-is deliberately: RATING_ROLE_DIVERGENCE.md'],
  ['FINANCE',     'MANAGEMENT_REVIEW', false, 'Accounts must not sign off'],
  ['MANAGEMENT',  'ACCOUNT_HR_RATING', false, 'management does not take over the HR seat'],
  ['EMPLOYEE',    'REPORTING_MANAGER_RATING', false, 'employee holds no manager role'],
];

console.log(`  gate: ${hierarchical ? 'rolesHeldBy() hierarchy (PATCHED)' : 'flat includes(user.role) (DEPLOYED)'}`);
let pass = 0;
const fails = [];
for (const [role, stage, expected, why] of CASES) {
  const got = canAct(role, stage);
  if (got === expected) pass++;
  else fails.push(`  ${expected ? 'BLOCKED' : 'LEAKED '}  ${role} / ${stage}  — ${why}`);
}
for (const f of fails) console.log(f);
console.log(`  ${pass}/${CASES.length} as intended, ${fails.length} wrong`);
process.exitCode = fails.length ? 1 : 0;

/*
 * Usage — check the deployed service, then a patched copy:
 *
 *   node docs/verify_rating_roles.cjs \
 *     D:/Vistar/vistar_CRM/src/modules/kra/dist/features/monthly-reviews/monthly-reviews.service.js
 *
 * Exit 0 = every role/stage pair behaves as intended. Exit 1 = at least one is
 * wrong, and each is printed as either
 *
 *   BLOCKED  <role> / <stage>   someone who SHOULD be able to act cannot
 *   LEAKED   <role> / <stage>   someone who should NOT be able to act can
 *
 * LEAKED is the serious one: it means authority was widened. Run this after any
 * edit to ACTOR_ROLES or to IMPLIED_ROLES in rbac.middleware.js — those two
 * compose, so a change to either can widen a seat neither file mentions.
 *
 * Needs no database and no running server: it lifts ACTOR_ROLES straight out of
 * the source and requires the real rbac.middleware.js for the hierarchy.
 */
