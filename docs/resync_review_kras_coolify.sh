# Paste each PART separately into the Coolify terminal, in order.
# After each part you must see "part N ok" before pasting the next one.

# ===== PART 1 of 5 - copy from here =====
cat > /tmp/resync.sql <<'SQL_EOF'
SET client_min_messages = warning;   -- a first run has nothing to drop; skip saying so
DROP VIEW     IF EXISTS pg_temp.resync_source;
DROP TABLE    IF EXISTS pg_temp.resync_target;
DROP FUNCTION IF EXISTS pg_temp.kra_sig(int, text, numeric, numeric);
DROP FUNCTION IF EXISTS pg_temp.kra_key(text);
RESET client_min_messages;

CREATE TEMP TABLE resync_target AS
SELECT 'VLPL1436'::text  AS employee_code,
       DATE '2026-07-01' AS first_month,
       DATE '2026-09-01' AS last_month,
       DATE '2026-10-01' AS reference_month;

CREATE FUNCTION pg_temp.kra_key(text) RETURNS text
  LANGUAGE sql IMMUTABLE
  AS $$ SELECT lower(regexp_replace(btrim($1), '\s+', ' ', 'g')) $$;

CREATE FUNCTION pg_temp.kra_sig(int, text, numeric, numeric) RETURNS text
  LANGUAGE sql IMMUTABLE
  AS $$ SELECT format('%s|%s|%s|%s', $1, pg_temp.kra_key($2), round($3, 2), round($4, 2)) $$;

CREATE TEMP VIEW resync_source AS
WITH emp AS (
  SELECT e.id AS employee_id, e.default_template_id,
         asg.id AS assignment_id, asg.template_id AS assignment_template_id,
         asg.cycle_name
  FROM kra.employees e
  LEFT JOIN LATERAL (
    SELECT a.id, a.template_id, c.name AS cycle_name
    FROM kra.kra_assignments a
    JOIN kra.review_cycles c ON c.id = a.cycle_id
    WHERE a.employee_id = e.id AND c.status::text = 'ACTIVE'
    ORDER BY a.assigned_at DESC
    LIMIT 1
  ) asg ON TRUE
)
SELECT emp.employee_id,
       format('assignment in active cycle "%s"', emp.cycle_name)
         || COALESCE(format(' (template "%s")', tpl.name), '') AS source,
       ai.sort_order, ai.name, ai.target, ai.tracking_method,
       NULL::text AS category,
       CASE WHEN ai.weightage <= 1 THEN ai.weightage * 100 ELSE ai.weightage END
         AS weightage_percent,
       100::numeric AS max_score,
       COALESCE(to_jsonb(ai) ->> 'reviewer_group', ti.score_source::text) AS reviewer_group
FROM emp
JOIN kra.kra_assignment_items ai ON ai.assignment_id = emp.assignment_id
LEFT JOIN kra.kra_templates tpl ON tpl.id = emp.assignment_template_id
LEFT JOIN LATERAL (
  SELECT t.score_source FROM kra.kra_template_items t
  WHERE t.template_id = emp.assignment_template_id AND t.sort_order = ai.sort_order
  LIMIT 1
) ti ON TRUE
UNION ALL
SELECT emp.employee_id,
       format('default template "%s"', tpl.name),
       ti.sort_order, ti.name, ti.target, ti.tracking_method,
       ti.category,
       CASE WHEN ti.weightage <= 1 THEN ti.weightage * 100 ELSE ti.weightage END,
       COALESCE(NULLIF(ti.default_max_score, 0), 100),
       COALESCE(to_jsonb(ti) ->> 'reviewer_group', ti.score_source::text)
FROM emp
JOIN kra.kra_template_items ti ON ti.template_id = emp.default_template_id
JOIN kra.kra_templates tpl ON tpl.id = ti.template_id
WHERE NOT EXISTS (SELECT 1 FROM kra.kra_assignment_items x
                  WHERE x.assignment_id = emp.assignment_id);

WITH p AS (SELECT * FROM pg_temp.resync_target),
now_rows AS (
  SELECT s.employee_id,
         pg_temp.kra_sig(s.sort_order, s.name, s.weightage_percent, s.max_score) AS sig
  FROM pg_temp.resync_source s
),
now_kras AS (
  SELECT employee_id, count(*) AS kras, string_agg(sig, ';' ORDER BY sig) AS sig
  FROM now_rows GROUP BY employee_id
),
review_rows AS (
  SELECT mr.id, mr.employee_id, mr.year, mr.month, mr.current_stage,
         pg_temp.kra_sig(rr.display_order, rr.name, rr.weightage_percent, rr.max_score) AS sig
  FROM kra.monthly_reviews mr
  JOIN kra.monthly_review_rows rr ON rr.review_id = mr.id
  CROSS JOIN p
  WHERE mr.organization_id = (SELECT e.organization_id FROM kra.employees e
                              WHERE e.employee_code = p.employee_code)
    AND make_date(mr.year, mr.month, 1) BETWEEN p.first_month AND p.last_month
),
on_review AS (
  SELECT id, employee_id, year, month, current_stage,
         count(*) AS kras, string_agg(sig, ';' ORDER BY sig) AS sig
  FROM review_rows GROUP BY id, employee_id, year, month, current_stage
)
SELECT e.employee_code, e.name AS employee,
       to_char(make_date(r.year, r.month, 1), 'Mon YYYY') AS month,
       r.current_stage, r.kras AS kras_on_review, n.kras AS kras_now,
       (SELECT count(*) FROM kra.monthly_row_scores sc
          JOIN kra.monthly_review_rows x ON x.id = sc.row_id
         WHERE x.review_id = r.id) AS scores_entered
FROM on_review r
JOIN kra.employees e ON e.id = r.employee_id
LEFT JOIN now_kras n ON n.employee_id = r.employee_id
WHERE r.sig IS DISTINCT FROM n.sig
ORDER BY e.name, r.year, r.month;

SELECT s.source, s.sort_order, s.name, s.weightage_percent, s.max_score, s.reviewer_group
FROM pg_temp.resync_source s
JOIN kra.employees e ON e.id = s.employee_id
JOIN pg_temp.resync_target p ON p.employee_code = e.employee_code
ORDER BY s.sort_order;

WITH p AS (SELECT * FROM pg_temp.resync_target),
emp AS (SELECT e.id FROM kra.employees e JOIN p ON e.employee_code = p.employee_code),
now_kras AS (
  SELECT pg_temp.kra_key(s.name) AS k, round(s.max_score, 2) AS mx,
         count(*) OVER (PARTITION BY pg_temp.kra_key(s.name)) AS n
  FROM pg_temp.resync_source s
  WHERE s.employee_id = (SELECT id FROM emp)
),
rows_now AS (
  SELECT mr.id AS review_id, mr.year, mr.month, mr.current_stage, rr.id AS row_id,
         rr.display_order, rr.name, rr.weightage_percent, rr.max_score,
         count(*) OVER (PARTITION BY mr.id, pg_temp.kra_key(rr.name)) AS n
  FROM kra.monthly_reviews mr
  JOIN kra.monthly_review_rows rr ON rr.review_id = mr.id
  CROSS JOIN p
  WHERE mr.employee_id = (SELECT id FROM emp)
    AND make_date(mr.year, mr.month, 1) BETWEEN p.first_month AND p.last_month
)
SELECT to_char(make_date(r.year, r.month, 1), 'Mon YYYY') AS month,
       r.current_stage, r.display_order, r.name AS kra,
       r.weightage_percent, r.max_score,
       string_agg(format('%s=%s', sc.stage, COALESCE(sc.value::text, 'N/A')), ', '
                  ORDER BY sc.stage) FILTER (WHERE sc.row_id IS NOT NULL) AS scores,
       bool_or(nullif(btrim(coalesce(sc.remark, '')), '') IS NOT NULL
               OR nullif(btrim(coalesce(to_jsonb(sc) ->> 'proof_note', '')), '') IS NOT NULL)
         AS has_reason,
       bool_or(to_jsonb(sc) ->> 'proof_file_name' IS NOT NULL
               OR to_jsonb(sc) ->> 'proof_storage_key' IS NOT NULL) AS has_attachment,
       CASE WHEN count(sc.row_id) = 0 THEN NULL
            WHEN r.n = 1 AND EXISTS (SELECT 1 FROM now_kras k
                                     WHERE k.k = pg_temp.kra_key(r.name)
                                       AND k.mx = round(r.max_score, 2)
                                       AND k.n = 1)
              THEN 'kept'
SQL_EOF
echo "part 1 ok"

# ===== PART 2 of 5 - copy from here =====
cat >> /tmp/resync.sql <<'SQL_EOF'
            ELSE 'deleted' END AS fate
FROM rows_now r
LEFT JOIN kra.monthly_row_scores sc ON sc.row_id = r.row_id
GROUP BY r.review_id, r.year, r.month, r.current_stage, r.row_id,
         r.display_order, r.name, r.weightage_percent, r.max_score, r.n
ORDER BY r.year, r.month, r.display_order;

DO $resync$
DECLARE
  v_apply CONSTANT boolean := false;   -- ◀ false: dry run, rolled back. true: saved.

  p            record;
  v_emp        record;
  v_src_n      int;
  v_src_sig    text;
  v_src_label  text;
  v_ref_sig    text;
  rev          record;
  v_old_ids    text[];
  v_backup_id  text;
  v_kept       int;
  v_deleted    text;
  v_reasons    int;
  v_files      int;
  v_cleared    text;
  v_recopied   int := 0;
  v_current    int := 0;
BEGIN
  BEGIN  -- a dry run unwinds everything inside this block
    SELECT * INTO STRICT p FROM pg_temp.resync_target;

    SELECT e.id, e.name, e.employee_code INTO v_emp
      FROM kra.employees e WHERE e.employee_code = p.employee_code;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'No employee has the code %.', p.employee_code;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'kra' AND table_name = 'monthly_review_rows'
                      AND column_name = 'reviewer_group') THEN
      RAISE EXCEPTION 'kra.monthly_review_rows has no reviewer_group column yet. The backend adds it the first time a KRA sheet is opened - open one, then run this again.';
    END IF;

    SELECT count(*), string_agg(x.sig, ';' ORDER BY x.sig), min(x.source)
      INTO v_src_n, v_src_sig, v_src_label
      FROM (SELECT s.source,
                   pg_temp.kra_sig(s.sort_order, s.name, s.weightage_percent, s.max_score) AS sig
              FROM pg_temp.resync_source s
             WHERE s.employee_id = v_emp.id) x;
    IF v_src_n = 0 THEN
      RAISE EXCEPTION '% (%) has no KRAs to copy: no assignment in an ACTIVE cycle and no default template. Assign the KRAs in the app first.',
        v_emp.name, v_emp.employee_code;
    END IF;

    IF p.reference_month IS NOT NULL THEN
      SELECT string_agg(x.sig, ';' ORDER BY x.sig) INTO v_ref_sig
        FROM (SELECT pg_temp.kra_sig(rr.display_order, rr.name, rr.weightage_percent, rr.max_score) AS sig
                FROM kra.monthly_reviews mr
                JOIN kra.monthly_review_rows rr ON rr.review_id = mr.id
               WHERE mr.employee_id = v_emp.id
                 AND make_date(mr.year, mr.month, 1) = date_trunc('month', p.reference_month)::date) x;
      IF v_ref_sig IS NULL THEN
        RAISE EXCEPTION '% has no review with KRAs for the reference month %. Pick a month that has one, or set reference_month to NULL in step 0.',
          v_emp.employee_code, to_char(p.reference_month, 'Mon YYYY');
      END IF;
      IF v_ref_sig <> v_src_sig THEN
        RAISE EXCEPTION 'The KRAs % would get now (from %) are not the KRAs on %, so they are not the set you expect to copy. Compare step 2a with that month. Nothing was changed.',
          v_emp.employee_code, v_src_label, to_char(p.reference_month, 'Mon YYYY');
      END IF;
    END IF;

    IF to_regclass('kra.review_kra_resync_backup') IS NULL THEN
      CREATE TABLE kra.review_kra_resync_backup (
        id                text PRIMARY KEY,
        review_id         text NOT NULL,
        organization_id   text NOT NULL,
        employee_id       text NOT NULL,
        year              int  NOT NULL,
        month             int  NOT NULL,
        source            text NOT NULL,
        resynced_at       timestamptz NOT NULL DEFAULT now(),
        restored_at       timestamptz,
        old_review        jsonb NOT NULL,
        old_rows          jsonb NOT NULL,
        old_scores        jsonb NOT NULL,
        old_stage_records jsonb NOT NULL,
        new_rows          jsonb
      );
    END IF;

    FOR rev IN
      SELECT mr.id, mr.organization_id, mr.year, mr.month, mr.current_stage, mr.payout_status,
             to_jsonb(mr) AS snapshot,
             to_char(make_date(mr.year, mr.month, 1), 'Mon YYYY') AS label
        FROM kra.monthly_reviews mr
       WHERE mr.employee_id = v_emp.id
         AND make_date(mr.year, mr.month, 1) BETWEEN p.first_month AND p.last_month
       ORDER BY mr.year, mr.month
         FOR UPDATE
    LOOP
      IF (SELECT string_agg(x.sig, ';' ORDER BY x.sig)
            FROM (SELECT pg_temp.kra_sig(rr.display_order, rr.name, rr.weightage_percent, rr.max_score) AS sig
                    FROM kra.monthly_review_rows rr WHERE rr.review_id = rev.id) x)
         IS NOT DISTINCT FROM v_src_sig THEN
        RAISE NOTICE '% | %: already has the current KRAs - left alone.', rev.label, v_emp.employee_code;
        v_current := v_current + 1;
        CONTINUE;
      END IF;

      IF rev.payout_status <> 'PENDING'
         OR rev.current_stage IN ('INCENTIVE_PAYOUT', 'COMPLETED')
         OR rev.snapshot ->> 'management_locked_at' IS NOT NULL THEN
        RAISE EXCEPTION '% | %: management has signed this month off (stage %, payout %, locked %). Its incentive rests on these scores, so NOTHING was changed - not this month, not the others. Unlock it in the app, or leave it out of the range in step 0.',
          rev.label, v_emp.employee_code, rev.current_stage, rev.payout_status,
          COALESCE(rev.snapshot ->> 'management_locked_at', 'no');
      END IF;

      v_old_ids := ARRAY(SELECT rr.id FROM kra.monthly_review_rows rr WHERE rr.review_id = rev.id);

      INSERT INTO kra.review_kra_resync_backup
             (id, review_id, organization_id, employee_id, year, month, source,
              old_review, old_rows, old_scores, old_stage_records)
      VALUES (gen_random_uuid()::text, rev.id, rev.organization_id, v_emp.id,
              rev.year, rev.month, v_src_label, rev.snapshot,
              COALESCE((SELECT jsonb_agg(to_jsonb(rr) ORDER BY rr.display_order)
                          FROM kra.monthly_review_rows rr WHERE rr.id = ANY (v_old_ids)), '[]'),
              COALESCE((SELECT jsonb_agg(to_jsonb(sc) ORDER BY sc.row_id, sc.stage)
                          FROM kra.monthly_row_scores sc WHERE sc.row_id = ANY (v_old_ids)), '[]'),
              COALESCE((SELECT jsonb_agg(to_jsonb(sr) ORDER BY sr.submitted_at)
                          FROM kra.monthly_stage_records sr WHERE sr.review_id = rev.id), '[]'))
      RETURNING id INTO v_backup_id;

      INSERT INTO kra.monthly_review_rows
             (id, review_id, name, category, weightage_percent, max_score,
              target, tracking_method, display_order, reviewer_group)
      SELECT gen_random_uuid()::text, rev.id, s.name, s.category, s.weightage_percent, s.max_score,
             s.target, s.tracking_method, s.sort_order, s.reviewer_group
        FROM pg_temp.resync_source s
       WHERE s.employee_id = v_emp.id;

      WITH prev AS (
        SELECT rr.id, pg_temp.kra_key(rr.name) AS k, round(rr.max_score, 2) AS mx,
               count(*) OVER (PARTITION BY pg_temp.kra_key(rr.name)) AS n
          FROM kra.monthly_review_rows rr
SQL_EOF
echo "part 2 ok"

# ===== PART 3 of 5 - copy from here =====
cat >> /tmp/resync.sql <<'SQL_EOF'
         WHERE rr.id = ANY (v_old_ids)
      ), fresh AS (
        SELECT rr.id, pg_temp.kra_key(rr.name) AS k, round(rr.max_score, 2) AS mx,
               count(*) OVER (PARTITION BY pg_temp.kra_key(rr.name)) AS n
          FROM kra.monthly_review_rows rr
         WHERE rr.review_id = rev.id AND rr.id <> ALL (v_old_ids)
      )
      UPDATE kra.monthly_row_scores sc
         SET row_id = fresh.id
        FROM prev
        JOIN fresh ON fresh.k = prev.k AND fresh.mx = prev.mx AND fresh.n = 1
       WHERE prev.n = 1 AND sc.row_id = prev.id;
      GET DIAGNOSTICS v_kept = ROW_COUNT;

      SELECT string_agg(format('%s x%s', x.stage, x.n), ', ' ORDER BY x.stage),
             COALESCE(sum(x.reasons), 0), COALESCE(sum(x.files), 0)
        INTO v_deleted, v_reasons, v_files
        FROM (SELECT sc.stage, count(*) AS n,
                     count(*) FILTER (
                       WHERE nullif(btrim(coalesce(sc.remark, '')), '') IS NOT NULL
                          OR nullif(btrim(coalesce(to_jsonb(sc) ->> 'proof_note', '')), '') IS NOT NULL
                     ) AS reasons,
                     count(*) FILTER (
                       WHERE to_jsonb(sc) ->> 'proof_file_name' IS NOT NULL
                          OR to_jsonb(sc) ->> 'proof_storage_key' IS NOT NULL
                     ) AS files
                FROM kra.monthly_row_scores sc
               WHERE sc.row_id = ANY (v_old_ids)
               GROUP BY sc.stage) x;
      DELETE FROM kra.monthly_row_scores WHERE row_id = ANY (v_old_ids);
      DELETE FROM kra.monthly_review_rows WHERE id = ANY (v_old_ids);

      SELECT string_agg(sr.stage, ', ' ORDER BY sr.submitted_at) INTO v_cleared
        FROM kra.monthly_stage_records sr WHERE sr.review_id = rev.id;
      DELETE FROM kra.monthly_stage_records WHERE review_id = rev.id;
      UPDATE kra.monthly_reviews
         SET current_stage = 'SELF_RATING',
             incentive_computed_score_pct = NULL,
             updated_at = now()
       WHERE id = rev.id;

      UPDATE kra.review_kra_resync_backup bk
         SET new_rows = (SELECT jsonb_agg(to_jsonb(rr) ORDER BY rr.display_order)
                           FROM kra.monthly_review_rows rr WHERE rr.review_id = rev.id)
       WHERE bk.id = v_backup_id;

      RAISE NOTICE '% | %: % KRAs replaced by % from %. Scores kept: %. Scores deleted: % (% with a reason, % with an attachment). Submissions cleared: %. Back at SELF_RATING.',
        rev.label, v_emp.employee_code, cardinality(v_old_ids), v_src_n, v_src_label,
        v_kept, COALESCE(v_deleted, 'none'), v_reasons, v_files, COALESCE(v_cleared, 'none');
      v_recopied := v_recopied + 1;
    END LOOP;

    RAISE NOTICE '% (%): % month(s) re-copied, % already current.',
      v_emp.name, v_emp.employee_code, v_recopied, v_current;

    IF NOT v_apply THEN
      RAISE EXCEPTION USING ERRCODE = 'KR000', MESSAGE = 'dry run';
    END IF;
  EXCEPTION
    WHEN SQLSTATE 'KR000' THEN
      RAISE NOTICE 'DRY RUN - nothing above was saved. To save it, set v_apply := true and run step 3 again.';
  END;
END
$resync$;

SELECT to_char(make_date(mr.year, mr.month, 1), 'Mon YYYY') AS month,
       mr.current_stage,
       count(rr.id) AS kras,
       string_agg(rr.name, ' | ' ORDER BY rr.display_order) AS kra_names,
       (SELECT count(*) FROM kra.monthly_row_scores sc
          JOIN kra.monthly_review_rows x ON x.id = sc.row_id
         WHERE x.review_id = mr.id) AS scores
FROM kra.monthly_reviews mr
JOIN kra.employees e ON e.id = mr.employee_id
JOIN pg_temp.resync_target p ON p.employee_code = e.employee_code
LEFT JOIN kra.monthly_review_rows rr ON rr.review_id = mr.id
WHERE make_date(mr.year, mr.month, 1)
      BETWEEN p.first_month - interval '3 months' AND p.last_month + interval '3 months'
GROUP BY mr.id, mr.year, mr.month, mr.current_stage
ORDER BY mr.year, mr.month;

DO $undo$
DECLARE
  v_undo CONSTANT boolean := false;   -- ◀ true: restore the step 3 backups.

  p      record;
  v_emp  record;
  bk     record;
  v_n    int := 0;
BEGIN
  IF NOT v_undo THEN
    RAISE NOTICE 'Step 5 (undo) is off - nothing was restored.';
    RETURN;
  END IF;

  SELECT * INTO STRICT p FROM pg_temp.resync_target;
  SELECT e.id, e.employee_code INTO v_emp
    FROM kra.employees e WHERE e.employee_code = p.employee_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No employee has the code %.', p.employee_code;
  END IF;
  IF to_regclass('kra.review_kra_resync_backup') IS NULL THEN
    RAISE EXCEPTION 'There is no kra.review_kra_resync_backup table: step 3 has never been saved on this database.';
  END IF;

  FOR bk IN
    SELECT DISTINCT ON (b.review_id) b.*
      FROM kra.review_kra_resync_backup b
     WHERE b.employee_id = v_emp.id
       AND b.restored_at IS NULL
       AND make_date(b.year, b.month, 1) BETWEEN p.first_month AND p.last_month
     ORDER BY b.review_id, b.resynced_at DESC
  LOOP
    DELETE FROM kra.monthly_row_scores sc
     USING kra.monthly_review_rows rr
     WHERE sc.row_id = rr.id AND rr.review_id = bk.review_id;
    DELETE FROM kra.monthly_review_rows WHERE review_id = bk.review_id;
    DELETE FROM kra.monthly_stage_records WHERE review_id = bk.review_id;

    INSERT INTO kra.monthly_review_rows
    SELECT * FROM jsonb_populate_recordset(NULL::kra.monthly_review_rows, bk.old_rows);
    INSERT INTO kra.monthly_row_scores
    SELECT * FROM jsonb_populate_recordset(NULL::kra.monthly_row_scores, bk.old_scores);
    INSERT INTO kra.monthly_stage_records
    SELECT * FROM jsonb_populate_recordset(NULL::kra.monthly_stage_records, bk.old_stage_records);

    UPDATE kra.monthly_reviews
       SET current_stage = bk.old_review ->> 'current_stage',
           incentive_computed_score_pct = (bk.old_review ->> 'incentive_computed_score_pct')::numeric,
           updated_at = now()
     WHERE id = bk.review_id;
    UPDATE kra.review_kra_resync_backup SET restored_at = now() WHERE id = bk.id;

    RAISE NOTICE '% | %: restored % KRAs, % scores, % submissions.',
      to_char(make_date(bk.year, bk.month, 1), 'Mon YYYY'), v_emp.employee_code,
      jsonb_array_length(bk.old_rows), jsonb_array_length(bk.old_scores),
      jsonb_array_length(bk.old_stage_records);
    v_n := v_n + 1;
  END LOOP;

  RAISE NOTICE '%: % month(s) restored.', v_emp.employee_code, v_n;
END
$undo$;

SQL_EOF
echo "part 3 ok"

# ===== PART 4 of 5 - copy from here =====
cat > /tmp/resync.cjs <<'JS_EOF'
// Runs /tmp/resync.sql with the backend's own DATABASE_URL and pg package.
//   node /tmp/resync.cjs          dry run: changes nothing
//   node /tmp/resync.cjs apply    saves the fix
//   node /tmp/resync.cjs undo     restores the backup
const fs = require('fs');
const mode = process.argv[2] || 'dry';
if (!['dry', 'apply', 'undo'].includes(mode)) { console.error('use: dry | apply | undo'); process.exit(2); }
let pg;
try { pg = require(require.resolve('pg', { paths: [process.cwd(), '/app', '/usr/src/app', '/opt/app'] })); }
catch { console.error('pg not found: cd into the backend folder (the one with node_modules) and run again'); process.exit(2); }
const url = process.env.DATABASE_URL;
if (!url) { console.error('DATABASE_URL is not set in this container'); process.exit(2); }
let sql = fs.readFileSync('/tmp/resync.sql', 'utf8');
if (mode === 'apply') sql = sql.replace('v_apply CONSTANT boolean := false;', 'v_apply CONSTANT boolean := true;');
if (mode === 'undo') sql = sql.replace('v_undo CONSTANT boolean := false;', 'v_undo CONSTANT boolean := true;');
// Same SSL rule as src/config/db.js.
const ssl = String(process.env.PGSSL || '').toLowerCase() === 'true' ||
  /(supabase\.co|render\.com|amazonaws\.com|heroku\.com|neon\.tech|railway\.app)/i.test(url)
  ? { rejectUnauthorized: false } : false;
const TITLES = ['STEP 1 - other employees with the same problem (empty = none)',
  'STEP 2a - the KRAs the months will get (must be the 5 Sr. GM EXIM KRAs)',
  'STEP 2b - what each month holds now, and what happens to each score',
  'STEP 4 - the months around the range, after this run'];
(async () => {
  const c = new pg.Client({ connectionString: url, ssl });
  c.on('notice', (n) => {
    if (n.severity === 'WARNING' || n.message.startsWith('Step 5 (undo) is off')) return;
    console.log('>> ' + (n.message.startsWith('DRY RUN') ? 'DRY RUN - nothing was saved. To save it:  node /tmp/resync.cjs apply' : n.message));
  });
  await c.connect();
  console.log('MODE: ' + mode.toUpperCase() + '\n');
  try {
    const res = [].concat(await c.query(sql)).filter((r) => r.command === 'SELECT' && r.fields.length > 0);
    res.forEach((r, i) => {
      console.log('\n' + (TITLES[i] || 'result') + ' (' + r.rows.length + ' rows)');
      if (r.rows.length) console.table(r.rows);
    });
    console.log('\nDONE (' + mode + ')');
  } catch (e) {
    console.error('\nSTOPPED, nothing was changed: ' + e.message);
    process.exitCode = 1;
  } finally { await c.end(); }
})();
JS_EOF
echo "part 4 ok"

# ===== PART 5 of 5 - copy from here =====
wc -l /tmp/resync.sql /tmp/resync.cjs && grep -c 'resync_target' /tmp/resync.sql && echo "all parts ok - now run:  node /tmp/resync.cjs"
