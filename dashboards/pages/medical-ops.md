---
title: Medical Ops
---

Appointment operations for the clinical team. Excludes not-yet-occurred
(`scheduled`) appointments from rate calculations.

```sql appt_kpis
select
  count(*)                                             as total_appointments,
  count(*) filter (where is_no_show)  * 1.0 / nullif(count(*), 0) as no_show_rate,
  count(*) filter (where is_completed) * 1.0 / nullif(count(*), 0) as completion_rate,
  avg(lead_time_days)                                 as avg_lead_time_days
from telehealth.fct_appointments
where status != 'scheduled'
```

<BigValue data={appt_kpis} value=total_appointments fmt=num0 title="Completed + Missed Appts"/>
<BigValue data={appt_kpis} value=no_show_rate fmt=pct1 title="No-show Rate"/>
<BigValue data={appt_kpis} value=completion_rate fmt=pct1 title="Completion Rate"/>
<BigValue data={appt_kpis} value=avg_lead_time_days fmt=num1 title="Avg Lead Time (days)"/>

## Appointment volume by week

```sql appts_by_week
select
  appointment_week,
  count(*)                             as appointments,
  count(*) filter (where is_no_show)   as no_shows
from telehealth.fct_appointments
where status != 'scheduled'
group by 1
order by 1
```

<LineChart data={appts_by_week} x=appointment_week y=appointments title="Weekly Appointments"/>

## No-show rate by specialty

```sql noshow_by_specialty
select
  provider_specialty,
  count(*)                                              as appointments,
  count(*) filter (where is_no_show) * 1.0 / nullif(count(*), 0) as no_show_rate
from telehealth.fct_appointments
where status != 'scheduled' and provider_specialty is not null
group by 1
order by no_show_rate desc
```

<BarChart data={noshow_by_specialty} x=provider_specialty y=no_show_rate yFmt=pct1 title="No-show Rate by Specialty" swapXY=true/>

<DataTable data={noshow_by_specialty} rows=all>
  <Column id=provider_specialty title="Specialty"/>
  <Column id=appointments fmt=num0/>
  <Column id=no_show_rate title="No-show Rate" fmt=pct1 contentType=colorscale scaleColor=red/>
</DataTable>

## Appointment mix by month

```sql appts_by_type
select
  appointment_month,
  appointment_type,
  count(*) as appointments
from telehealth.fct_appointments
where status != 'scheduled'
group by 1, 2
order by 1, 2
```

<BarChart data={appts_by_type} x=appointment_month y=appointments series=appointment_type type=stacked title="Appointments by Channel Type"/>
