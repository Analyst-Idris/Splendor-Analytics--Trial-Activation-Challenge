# Splendor-Analytics--Trial-Activation-Challenge

## Problem Statement

At Splendor Analytics, we run a 30-day free trial for new organisations signing up to our workforce management platform. The platform covers everything from shift scheduling and time tracking to payroll approvals and team communications.
The challenge is this: we do not know what a "good" trial looks like. Our product team can see that roughly 1 in 5 trialists eventually converts to a paying customer, but they cannot tell who is on track to convert, when to intervene, or which features actually matter to the decision. Without that clarity, every onboarding improvement is a guess.

To fix this, we want to define what Trial Activation means for our product — a specific set of in-app behaviours that signal a trialist has genuinely experienced our core value. We then want to build the data infrastructure to track activation at scale, and run the analysis to understand whether our current trialists are reaching it.
Your job is to do exactly that: dig into the raw behavioural data, find what matters, define the goals, and build the models.


This solution:
1. Cleans and explores the raw behavioural event data
2. Rigorously tests which in-app activities drive conversion (with honest reporting of null findings)
3. Defines five evidence-backed Trial Goals and a Trial Activation metric
4. Builds production-ready SQL mart models to track activation at scale
5. Delivers actionable product recommendations backed by data

---

## Key Findings

| Metric | Value |
|--------|-------|
| Trial conversion rate | **21.3%** |
| Raw duplicate events removed | **67,631 (39.7% of raw data)** |
| XGBoost 5-fold CV AUC | **0.534 (near-random)** |
| Max statistical effect size (r) | **0.043 (small)** |
| Conversions occurring in final 5 days | **75.2%** |
| Trial activation rate (all 5 goals) | **0.3%** |
| Median days to conversion | **30 days** |

### Headline: Honest Null Finding

All three analytical methods (Mann-Whitney U tests, XGBoost + SHAP, K-Means segmentation)
converge on the same conclusion: **current in-app behavioural events do not reliably
predict conversion**. Conversion timing (75% in final 5 days) indicates the decision
is driven by off-platform factors — sales interactions, pricing negotiations, contract
processes — not captured in the event log.

This is reported transparently. The trial goals are defined using **product value logic**
(not predictive power) as evidence-based hypotheses for future A/B testing.

---

## Trial Goals

| Goal | Behaviour | Product rationale |
|------|-----------|-------------------|
| **G1 Schedule Builder** | ≥ 3 shifts created in first 14 days | Core scheduler adoption — separates exploration from real usage |
| **G2 Mobile Adoption** | ≥ 1 `Mobile.Schedule.Loaded` event | Signals team-wide usage (employees viewing schedule), not just one admin |
| **G3 Clock Activated** | ≥ 1 `PunchClock.PunchedIn` event | Platform is live in real operations — highest conv/non-conv gap (23% vs 21%) |
| **G4 Approval Workflow** | ≥ 1 `Scheduling.Shift.Approved` | Admin approval loop closed — proxy for organisational commitment |
| **G5 Payroll Loop** | Bulk timesheet approval OR Xero sync | Full value delivery: scheduling → time-tracking → payroll |

**Trial Activation** = all 5 goals completed within the 30-day window.

> Goals are product-value hypotheses for A/B testing — not proven causal levers.
> Recommend a tiered approach: "Starter Activation" (G1+G2+G3) for near-term tracking,
> Full Activation (all 5) as the aspirational target.

---

## Repo Structure

```
splendor-trial-activation/
├── README.md
├── requirements.txt
├── .gitignore
├── data/
│   └── DA_task.csv            # Raw data (gitignored)
├── notebooks/
│   ├── 01_eda_cleaning.ipynb         # Task 1: Data cleaning & EDA (15 figures)
│   ├── 02_conversion_drivers.ipynb   # Task 2: Statistical tests, XGBoost+SHAP, segmentation
│   └── 03_goals_and_metrics.ipynb    # Task 3: Goal definitions & product metrics
├── models/
│   ├── staging/
│   │   ├── stg_trial_events.sql   # Deduped, typed, boundary-validated events
│   │   └── stg_organisations.sql  # One row per org with trial metadata
│   └── marts/
│       ├── trial_goals.sql        # (org_id × goal_name) with goal_completed flag
│       └── trial_activation.sql   # One row per org: is_activated, activated_at
└── sql/
    └── standalone_queries.sql     # Ad-hoc analysis queries (non-dbt)
```

---

## Setup & Running

### Requirements
```
Python 3.10+  |  pandas  numpy  matplotlib  seaborn  scipy  scikit-learn  xgboost  shap
```

### Install
```bash
pip install -r requirements.txt
```

### Run end-to-end
```bash
mkdir -p data outputs
cp \Users\USER\Downloads\DA task.csv(ensure this is your own file path)

cd notebooks
01_eda_cleaning.ipynb
02_conversion_drivers.ipynb
03_goals_and_metrics.ipynb
```

All charts are written to `outputs/`. Intermediate CSVs to `data/`.

### SQL Models (dbt)
```bash
dbt run --select staging
dbt run --select marts
```
Or run `sql/standalone_queries.sql` directly against any SQL engine (DuckDB, BigQuery, Snowflake, Postgres).

---

## Methods

### Task 1 — Data Cleaning
- Exact deduplication: **67,631 rows removed** (39.7% of raw data — flagged as a pipeline issue)
- Timestamp parsing and UTC normalisation
- Boundary validation: events outside 0–30 day trial window removed
- Derived fields: `days_into_trial`, `events_per_active_day`, `days_to_convert`, `event_bucket`
- Org-level feature table: 966 organisations × 40 features

### Task 2 — Conversion Driver Analysis

**A. Statistical Tests (Mann-Whitney U + Chi-square)**
- Non-parametric two-sided tests on activity count distributions
- Bonferroni-corrected α = 0.05/28 = 0.0018
- Rank-biserial correlation as effect size
- Result: 0 activities significant after correction; max effect r = 0.043

**B. XGBoost + SHAP**
- Feature matrix: 28 activity counts + 28 binary flags + 4 engagement metrics
- Class imbalance handled via `scale_pos_weight` (≈3.7×)
- 5-fold stratified CV: **AUC = 0.534 ± 0.057**
- SHAP values for relative feature ranking (low AUC limits reliability)

**C. K-Means Segmentation**
- 4 engagement tiers: Dormant / Explorer / Active / Power user
- Elbow method for k selection
- Conversion rates: 0–22.5% across segments (minimal variation — consistent with null)

### Task 3 — Goals & Metrics
- 5 trial goals grounded in scheduling → time-tracking → payroll value chain
- Product-value rationale documented for each goal
- Standard metrics: conversion rate, time-to-convert, day-N retention, feature adoption
- Tiered activation definition proposed (Starter + Full)

---

## Product Recommendations

| Priority | Recommendation |
|----------|---------------|
| **P0** | Fix the event pipeline — 39.7% duplicate events undermines all future analytics |
| **P1** | Add richer signals: user count per org, role breakdown, team size |
| **P2** | Ship an onboarding checklist aligned to the 5 trial goals |
| **P3** | Day-7 intervention for orgs without G3 (punch clock) |
| **P4** | Interview recent converters to understand the off-platform decision trigger |
| **P5** | Track Starter Activation (G1+G2+G3) as near-term KPI, Full Activation as stretch |

---
