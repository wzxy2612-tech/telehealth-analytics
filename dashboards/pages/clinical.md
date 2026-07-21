---
title: Clinical
---

Clinical encounter analysis drawn from the Synthea EHR extract. Shows visit
volume, cost breakdown, and patient demographics.

```sql encounter_kpis
select
  count(encounter_id)                       as total_encounters,
  count(distinct patient_id)                as unique_patients,
  round(sum(total_claim_cost), 0)           as total_costs,
  round(avg(duration_minutes), 1)           as avg_duration_minutes
from telehealth.mart_clinical_encounters
```

<BigValue data={encounter_kpis} value=total_encounters fmt=num0 title="Total Encounters"/>
<BigValue data={encounter_kpis} value=unique_patients fmt=num0 title="Unique Patients"/>
<BigValue data={encounter_kpis} value=total_costs fmt=usd0 title="Total Claim Cost"/>
<BigValue data={encounter_kpis} value=avg_duration_minutes fmt=num1 title="Avg Duration (min)"/>

## Encounters by month

```sql encounters_by_month
select
  date_trunc('month', encounter_date) as encounter_month,
  count(encounter_id)                  as encounters
from telehealth.mart_clinical_encounters
group by 1
order by 1
```

<LineChart data={encounters_by_month} x=encounter_month y=encounters title="Monthly Encounters"/>

## Cost by encounter class

```sql encounters_by_class
select
  encounter_class,
  count(*)                              as encounters,
  round(sum(total_claim_cost), 0)       as total_cost,
  round(avg(total_claim_cost), 0)       as avg_cost
from telehealth.mart_clinical_encounters
group by 1
order by total_cost desc
```

<BarChart data={encounters_by_class} x=encounter_class y=total_cost yFmt=usd0 title="Total Cost by Encounter Class" swapXY=true/>

## Encounters by age band and gender

```sql encounters_by_demo
select
  age_band,
  gender,
  count(encounter_id)                   as encounters
from telehealth.mart_clinical_encounters
where age_band is not null
group by 1, 2
order by 1, 2
```

<BarChart data={encounters_by_demo} x=age_band y=encounters series=gender type=stacked title="Encounters by Age Band"/>
