---
title: Telehealth Analytics
---

Executive overview across Medical Ops, Business Ops, and Marketing. All figures
come from the dbt marts; data is synthetic (no real PHI).

```sql overview
select
  (select count(*) from telehealth.dim_patients)                                             as total_patients,
  (select active_subscriptions from telehealth.fct_mrr_daily order by calendar_date desc limit 1) as active_subs,
  (select mrr from telehealth.fct_mrr_daily order by calendar_date desc limit 1)              as mrr,
  (select arr from telehealth.fct_mrr_daily order by calendar_date desc limit 1)              as arr,
  (select count(*) filter (where is_no_show) * 1.0 / nullif(count(*), 0)
     from telehealth.fct_appointments where status != 'scheduled')                           as no_show_rate,
  (select sum(total_spend) / nullif(sum(signups), 0)
     from telehealth.mart_marketing_attribution)                                             as blended_cac
```

<BigValue data={overview} value=total_patients fmt=num0 title="Patients"/>
<BigValue data={overview} value=active_subs fmt=num0 title="Active Subscriptions"/>
<BigValue data={overview} value=mrr fmt=usd0 title="MRR"/>
<BigValue data={overview} value=arr fmt=usd0 title="ARR (run-rate)"/>
<BigValue data={overview} value=no_show_rate fmt=pct1 title="No-show Rate"/>
<BigValue data={overview} value=blended_cac fmt=usd2 title="Blended CAC"/>

## Revenue trend

```sql mrr_trend
select calendar_date, mrr, active_subscriptions
from telehealth.fct_mrr_daily
order by calendar_date
```

<LineChart data={mrr_trend} x=calendar_date y=mrr yFmt=usd0 title="Monthly Recurring Revenue"/>

## Explore by team

- [Medical Ops](/medical-ops) — appointment volume, no-show rate, provider load
- [Business Ops](/business-ops) — MRR, ARR, active subscriptions, churn, plan mix
- [Marketing](/marketing) — signups and CAC by channel and campaign

---

<Details title="About this project">

Built on a local-first stack: synthetic sources → DuckDB → dbt (staging →
intermediate → marts) → Evidence. The same models lift to Redshift + Airbyte +
Looker with a profile swap. See the repository README for architecture and the
path to production.

</Details>
