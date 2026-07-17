---
title: Business Ops
---

Subscription revenue and retention. MRR uses each subscription's current plan
(see the note in `fct_mrr_daily`).

```sql sub_stats
select
  count(*) filter (where status = 'active')                              as active_subs,
  count(*) filter (where status = 'cancelled')                           as churned_subs,
  count(*) filter (where status = 'cancelled') * 1.0 / nullif(count(*), 0) as churn_rate,
  sum(mrr_amount) filter (where status = 'active')                       as active_mrr
from telehealth.subscriptions
```

<BigValue data={sub_stats} value=active_mrr fmt=usd0 title="Current MRR"/>
<BigValue data={sub_stats} value=active_subs fmt=num0 title="Active Subscriptions"/>
<BigValue data={sub_stats} value=churned_subs fmt=num0 title="Churned (lifetime)"/>
<BigValue data={sub_stats} value=churn_rate fmt=pct1 title="Churn Rate (lifetime)"/>

## MRR over time

```sql mrr_trend
select calendar_date, mrr, arr, active_subscriptions, arpu
from telehealth.fct_mrr_daily
order by calendar_date
```

<AreaChart data={mrr_trend} x=calendar_date y=mrr yFmt=usd0 title="Monthly Recurring Revenue"/>

## Active subscriptions over time

<LineChart data={mrr_trend} x=calendar_date y=active_subscriptions title="Active Subscriptions"/>

## ARPU over time

<LineChart data={mrr_trend} x=calendar_date y=arpu yFmt=usd0 title="Average Revenue per User"/>

## Plan mix (active)

```sql plan_mix
select
  plan_id,
  count(*)          as subscriptions,
  sum(mrr_amount)   as mrr
from telehealth.subscriptions
where status = 'active'
group by 1
order by mrr desc
```

<BarChart data={plan_mix} x=plan_id y=subscriptions title="Active Subscriptions by Plan"/>

<DataTable data={plan_mix} rows=all>
  <Column id=plan_id title="Plan"/>
  <Column id=subscriptions fmt=num0/>
  <Column id=mrr title="MRR" fmt=usd0/>
</DataTable>
