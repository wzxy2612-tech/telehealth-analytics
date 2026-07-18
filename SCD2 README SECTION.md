## Slowly Changing Dimensions: subscription plan history

Subscriptions change plan over time (upgrade / downgrade). To answer
point-in-time questions — *what plan was this subscription on last month?*,
*how did revenue split across plans over time?* — the current-state
`fct_subscriptions` isn't enough; you need history. This project ships **both
tools for capturing it**, because they suit different source shapes:

| | `snapshots/subscriptions_snapshot.sql` | `dim_subscription_history` |
|---|---|---|
| Mechanism | dbt snapshot (SCD2) | SQL reconstruction from the event log |
| Source | current-state table (overwrites in place) | `subscription_events` |
| History | accrues **going forward**, run over run | **complete immediately**, one build |
| Use when | source keeps no history (e.g. a patient's address) | you have a reliable change log |

**Why two?** Real sources come in both shapes, and Chargebee gives you both a
current-state subscription object *and* an events stream. The rule of thumb:

- If the source only ever shows you *current* state and overwrites it, you can't
  recover the past — so you **snapshot** it on a schedule to capture changes as
  they happen. That's `subscriptions_snapshot`.
- If the source already emits a full **change log**, don't bother snapshotting —
  fold the events into SCD2 directly and you get complete history in one pass.
  That's `dim_subscription_history` (built with window functions over
  `subscription_events`).

A concrete gotcha this repo makes visible: `generate_data.py day` appends to
`subscription_events` but doesn't rewrite existing rows' plan in
`subscriptions.csv`. So the **snapshot alone would miss those plan changes** —
which is exactly the situation where event-reconstruction is the right call. The
snapshot is kept as the pattern you'd use elsewhere.

### `dim_subscription_history` grain

One row per `(subscription_id, plan period)`, with `valid_from`, `valid_to`
(NULL = current), `is_current`, and `version`. Periods are contiguous and
non-overlapping; every active subscription has exactly one current row, and
cancelled subscriptions have none (their final period closes at cancellation).

```sql
-- what plan was every subscription on at a given date?
select subscription_id, plan_id, mrr_amount
from marts.dim_subscription_history
where valid_from <= date '2024-11-15'
  and (valid_to > date '2024-11-15' or valid_to is null);
```

### Running

`dim_subscription_history` is a normal model — `dbt build` picks it up. The
snapshot runs as part of `dbt build` too (or on its own):

```bash
dbt snapshot          # capture current state into the snapshots schema
dbt build             # builds models + snapshots + tests together
```

> To surface the history in Evidence, add a pass-through in
> `dashboards/sources/telehealth/` (`select * from marts.dim_subscription_history`)
> and a page charting plan mix over time — the data is deterministic, so it
> renders on the deployed site.
