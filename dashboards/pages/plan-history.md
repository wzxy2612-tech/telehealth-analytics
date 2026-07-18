---
title: Plan History
description: Subscription plan changes over time, from the SCD Type 2 model
---

Subscriptions move between plans. `fct_subscriptions` only knows where each one
is *today*, so it can't answer *what plan was this on in November?* — every
question on this page needs the **SCD Type 2** model
(`dim_subscription_history`), which reconstructs one row per plan period from
the subscription event log.

```sql headline
select
    count(distinct subscription_id)                            as subscriptions,
    count(distinct subscription_id) filter (where version > 1) as subs_changed,
    count(*) filter (where version > 1)                        as plan_changes,
    count(distinct subscription_id) filter (where version > 1) * 1.0
        / nullif(count(distinct subscription_id), 0)           as pct_changed
from telehealth.dim_subscription_history
```

```sql directions
select
    sum(changes) filter (where direction = 'upgrade')   as upgrades,
    sum(changes) filter (where direction = 'downgrade') as downgrades
from telehealth.plan_transitions
```

<Grid cols=4>
  <BigValue data={headline} value=plan_changes fmt=num0 title="Plan Changes"/>
  <BigValue data={headline} value=pct_changed fmt=pct1 title="Changed Subs"/>
  <BigValue data={directions} value=upgrades fmt=num0 title="Upgrades"/>
  <BigValue data={directions} value=downgrades fmt=num0 title="Downgrades"/>
</Grid>

## Plan mix over time

Point-in-time composition of the subscriber base: on each day, how many
subscriptions sat on each tier.

```sql mix
select calendar_date, plan_id, subscriptions, mrr
from telehealth.plan_mix_over_time
```

<AreaChart
    data={mix}
    x=calendar_date
    y=subscriptions
    series=plan_id
    title="Active Subscriptions by Plan"
/>

<AreaChart
    data={mix}
    x=calendar_date
    y=mrr
    series=plan_id
    yFmt=usd0
    title="MRR by Plan"
/>

## Why history matters

`fct_mrr_daily` applies each subscription's **current** plan price across its
whole life — a common shortcut when you have no history. With SCD2 we can
compute the plan that was actually in force on each day and compare.

```sql mrr_comparison
select
    p.calendar_date,
    sum(p.mrr)   as mrr_point_in_time,
    max(m.mrr)   as mrr_current_plan
from telehealth.plan_mix_over_time p
join telehealth.fct_mrr_daily m on p.calendar_date = m.calendar_date
group by 1
order by 1
```

```sql gap
with cmp as (
    select
        p.calendar_date,
        sum(p.mrr) as pit,
        max(m.mrr) as naive
    from telehealth.plan_mix_over_time p
    join telehealth.fct_mrr_daily m on p.calendar_date = m.calendar_date
    group by 1
)
select
    max(abs(naive - pit))                          as max_gap,
    max(abs(naive - pit) / nullif(pit, 0))         as max_gap_pct
from cmp
```

<LineChart
    data={mrr_comparison}
    x=calendar_date
    y={["mrr_point_in_time", "mrr_current_plan"]}
    yFmt=usd0
    title="Point-in-Time MRR vs. Current-Plan MRR"
/>

The two lines diverge by up to <Value data={gap} column=max_gap fmt=usd0/>
(<Value data={gap} column=max_gap_pct fmt=pct1/>). Every dollar of that gap is
revenue mis-stated by back-applying today's plan to a historical day — the error
SCD2 exists to remove.

## Upgrade and downgrade flows

```sql transitions
select transition, direction, changes
from telehealth.plan_transitions
order by changes desc
```

<BarChart
    data={transitions}
    x=transition
    y=changes
    series=direction
    swapXY=true
    title="Plan Transitions"
/>

## Sample timelines

The subscriptions with the most plan periods. A blank `valid_to` means the
period is still open.

```sql busiest
select
    subscription_id,
    version,
    plan_id,
    mrr_amount,
    valid_from,
    valid_to,
    is_current
from telehealth.dim_subscription_history
where subscription_id in (
    select subscription_id
    from telehealth.dim_subscription_history
    group by 1
    order by count(*) desc
    limit 4
)
order by subscription_id, version
```

<DataTable data={busiest} rows=12>
  <Column id=subscription_id title="Subscription"/>
  <Column id=version/>
  <Column id=plan_id title="Plan"/>
  <Column id=mrr_amount title="MRR" fmt=usd0/>
  <Column id=valid_from title="From"/>
  <Column id=valid_to title="To"/>
  <Column id=is_current title="Current"/>
</DataTable>
