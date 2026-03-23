-- standalone_queries_sqlserver.sql
-- All queries converted for SQL Server (SSMS)
-- Run each section separately or all at once

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. OVERALL CONVERSION RATE
-- ═══════════════════════════════════════════════════════════════════════════
SELECT
    COUNT(DISTINCT organization_id)                                          AS total_orgs,
    COUNT(DISTINCT CASE WHEN converted = 'True' THEN organization_id END)   AS converted_orgs,
    ROUND(
        COUNT(DISTINCT CASE WHEN converted = 'True' THEN organization_id END)
        * 100.0 / COUNT(DISTINCT organization_id), 1
    )                                                                        AS conversion_rate_pct
FROM events_clean;


-- ═══════════════════════════════════════════════════════════════════════════
-- 2. FEATURE ADOPTION RATES
-- ═══════════════════════════════════════════════════════════════════════════
WITH org_activity AS (
    SELECT
        organization_id,
        activity_name,
        MAX(converted)                                                       AS converted
    FROM events_clean
    GROUP BY organization_id, activity_name
),
total_orgs AS (
    SELECT COUNT(DISTINCT organization_id) AS n FROM events_clean
)
SELECT
    activity_name,
    COUNT(DISTINCT organization_id)                                          AS orgs_used,
    ROUND(COUNT(DISTINCT organization_id) * 100.0 / MAX(total_orgs.n), 1)  AS adoption_pct,
    COUNT(DISTINCT CASE WHEN converted = 'True'
                        THEN organization_id END)                           AS conv_orgs_used,
    ROUND(
        COUNT(DISTINCT CASE WHEN converted = 'True' THEN organization_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT organization_id), 0), 1
    )                                                                        AS conv_rate_among_users
FROM org_activity
CROSS JOIN total_orgs
GROUP BY activity_name
ORDER BY adoption_pct DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- 3. TRIAL GOALS — COMPLETION PER ORG
-- ═══════════════════════════════════════════════════════════════════════════
WITH

orgs AS (
    SELECT
        organization_id,
        MAX(converted)                                   AS is_converted,
        CAST(MIN(trial_start) AS DATETIME)               AS trial_started_at,
        CAST(MAX(trial_end)   AS DATETIME)               AS trial_ended_at
    FROM events_clean
    GROUP BY organization_id
),

-- G1: >= 3 shifts created in first 14 days
g1 AS (
    SELECT
        organization_id,
        CASE WHEN COUNT(*) >= 3 THEN 1 ELSE 0 END        AS g1_schedule_builder,
        MIN(CASE WHEN rn = 3
                 THEN CAST(timestamp AS DATETIME) END)    AS g1_completed_at
    FROM (
        SELECT
            organization_id,
            timestamp,
            ROW_NUMBER() OVER (
                PARTITION BY organization_id
                ORDER BY CAST(timestamp AS DATETIME)
            )                                             AS rn
        FROM events_clean
        WHERE activity_name  = 'Scheduling.Shift.Created'
          AND days_into_trial <= 14
    ) r
    GROUP BY organization_id
),

-- G2: >= 1 mobile schedule load
g2 AS (
    SELECT
        organization_id,
        1                                                AS g2_mobile_adoption,
        MIN(CAST(timestamp AS DATETIME))                 AS g2_completed_at
    FROM events_clean
    WHERE activity_name = 'Mobile.Schedule.Loaded'
    GROUP BY organization_id
),

-- G3: >= 1 punch clock in
g3 AS (
    SELECT
        organization_id,
        1                                                AS g3_clock_activated,
        MIN(CAST(timestamp AS DATETIME))                 AS g3_completed_at
    FROM events_clean
    WHERE activity_name = 'PunchClock.PunchedIn'
    GROUP BY organization_id
),

-- G4: >= 1 shift approved
g4 AS (
    SELECT
        organization_id,
        1                                                AS g4_approval_workflow,
        MIN(CAST(timestamp AS DATETIME))                 AS g4_completed_at
    FROM events_clean
    WHERE activity_name = 'Scheduling.Shift.Approved'
    GROUP BY organization_id
),

-- G5: bulk timesheet OR Xero export (aspirational)
g5 AS (
    SELECT
        organization_id,
        1                                                AS g5_payroll_loop,
        MIN(CAST(timestamp AS DATETIME))                 AS g5_completed_at
    FROM events_clean
    WHERE activity_name IN (
        'Timesheets.BulkApprove.Confirmed',
        'Integration.Xero.PayrollExport.Synced'
    )
    GROUP BY organization_id
)

SELECT
    o.organization_id,
    o.is_converted,
    ISNULL(g1.g1_schedule_builder,  0)                  AS g1_schedule_builder,
    ISNULL(g2.g2_mobile_adoption,   0)                  AS g2_mobile_adoption,
    ISNULL(g3.g3_clock_activated,   0)                  AS g3_clock_activated,
    ISNULL(g4.g4_approval_workflow, 0)                  AS g4_approval_workflow,
    ISNULL(g5.g5_payroll_loop,      0)                  AS g5_payroll_loop,
    g1.g1_completed_at,
    g2.g2_completed_at,
    g3.g3_completed_at,
    g4.g4_completed_at,
    g5.g5_completed_at,

    -- Total goals completed
    ISNULL(g1.g1_schedule_builder,  0)
    + ISNULL(g2.g2_mobile_adoption,   0)
    + ISNULL(g3.g3_clock_activated,   0)
    + ISNULL(g4.g4_approval_workflow, 0)
    + ISNULL(g5.g5_payroll_loop,      0)                AS goals_completed_count,

    -- Trial Activation: all 4 core goals (G5 aspirational)
    CASE
        WHEN ISNULL(g1.g1_schedule_builder,  0) = 1
         AND ISNULL(g2.g2_mobile_adoption,   0) = 1
         AND ISNULL(g3.g3_clock_activated,   0) = 1
         AND ISNULL(g4.g4_approval_workflow, 0) = 1
        THEN 1 ELSE 0
    END                                                 AS is_activated

FROM orgs o
LEFT JOIN g1 ON g1.organization_id = o.organization_id
LEFT JOIN g2 ON g2.organization_id = o.organization_id
LEFT JOIN g3 ON g3.organization_id = o.organization_id
LEFT JOIN g4 ON g4.organization_id = o.organization_id
LEFT JOIN g5 ON g5.organization_id = o.organization_id
ORDER BY goals_completed_count DESC, is_converted DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- 4. ACTIVATION & CONVERSION RATE SUMMARY
-- Save query 3 into a temp table first, then run this
-- ═══════════════════════════════════════════════════════════════════════════

-- STEP 1: save query 3 results
SELECT
    o.organization_id,
    o.is_converted,
    ISNULL(g1.g1_schedule_builder,  0)
    + ISNULL(g2.g2_mobile_adoption,   0)
    + ISNULL(g3.g3_clock_activated,   0)
    + ISNULL(g4.g4_approval_workflow, 0)
    + ISNULL(g5.g5_payroll_loop,      0)                AS goals_completed_count,
    CASE
        WHEN ISNULL(g1.g1_schedule_builder,  0) = 1
         AND ISNULL(g2.g2_mobile_adoption,   0) = 1
         AND ISNULL(g3.g3_clock_activated,   0) = 1
         AND ISNULL(g4.g4_approval_workflow, 0) = 1
        THEN 1 ELSE 0
    END                                                 AS is_activated
INTO #goals_summary
FROM (
    SELECT organization_id, MAX(converted) AS is_converted
    FROM events_clean GROUP BY organization_id
) o
LEFT JOIN (
    SELECT organization_id,
           CASE WHEN COUNT(*) >= 3 THEN 1 ELSE 0 END AS g1_schedule_builder
    FROM events_clean
    WHERE activity_name = 'Scheduling.Shift.Created' AND days_into_trial <= 14
    GROUP BY organization_id
) g1 ON g1.organization_id = o.organization_id
LEFT JOIN (
    SELECT DISTINCT organization_id, 1 AS g2_mobile_adoption
    FROM events_clean WHERE activity_name = 'Mobile.Schedule.Loaded'
) g2 ON g2.organization_id = o.organization_id
LEFT JOIN (
    SELECT DISTINCT organization_id, 1 AS g3_clock_activated
    FROM events_clean WHERE activity_name = 'PunchClock.PunchedIn'
) g3 ON g3.organization_id = o.organization_id
LEFT JOIN (
    SELECT DISTINCT organization_id, 1 AS g4_approval_workflow
    FROM events_clean WHERE activity_name = 'Scheduling.Shift.Approved'
) g4 ON g4.organization_id = o.organization_id
LEFT JOIN (
    SELECT DISTINCT organization_id, 1 AS g5_payroll_loop
    FROM events_clean WHERE activity_name IN (
        'Timesheets.BulkApprove.Confirmed',
        'Integration.Xero.PayrollExport.Synced')
) g5 ON g5.organization_id = o.organization_id;

-- STEP 2: summary by goals completed
SELECT
    goals_completed_count,
    COUNT(*)                                                             AS n_orgs,
    SUM(CASE WHEN is_converted = 'True' THEN 1 ELSE 0 END)             AS n_converted,
    ROUND(
        SUM(CASE WHEN is_converted = 'True' THEN 1.0 ELSE 0 END)
        * 100.0 / COUNT(*), 1
    )                                                                    AS conversion_rate_pct,
    SUM(is_activated)                                                    AS n_activated
FROM #goals_summary
GROUP BY goals_completed_count
ORDER BY goals_completed_count;

DROP TABLE #goals_summary;


-- ═══════════════════════════════════════════════════════════════════════════
-- 5. DAY-N RETENTION
-- ═══════════════════════════════════════════════════════════════════════════
WITH org_days AS (
    SELECT DISTINCT organization_id, days_into_trial
    FROM events_clean
),
total_orgs AS (
    SELECT COUNT(DISTINCT organization_id) AS n FROM events_clean
)
SELECT
    od.days_into_trial                                                   AS trial_day,
    COUNT(DISTINCT od.organization_id)                                   AS active_orgs,
    ROUND(COUNT(DISTINCT od.organization_id) * 100.0 / MAX(t.n), 1)    AS retention_pct
FROM org_days od
CROSS JOIN total_orgs t
GROUP BY od.days_into_trial
ORDER BY od.days_into_trial;


-- ═══════════════════════════════════════════════════════════════════════════
-- 6. TIME-TO-CONVERT DISTRIBUTION
-- ═══════════════════════════════════════════════════════════════════════════
SELECT
    organization_id,
    DATEDIFF(DAY,
        CAST(MIN(trial_start)  AS DATETIME),
        CAST(MAX(trial_end)    AS DATETIME)
    )                                                                    AS days_to_convert
FROM events_clean
WHERE converted    = 'True'
  AND converted_at IS NOT NULL
GROUP BY organization_id
ORDER BY days_to_convert;
