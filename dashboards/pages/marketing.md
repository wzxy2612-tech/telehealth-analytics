---
title: Marketing
---

First-touch acquisition performance. Use the channel filter to drill in — every
chart and table below reacts to it.

```sql channels
select distinct channel
from telehealth.mart_marketing_attribution
order by channel
```

<Dropdown data={channels} name=channel value=channel defaultValue="%" title="Channel">
  <DropdownOption valueLabel="All Channels" value="%"/>
</Dropdown>

```sql mkt_kpis
select
  sum(signups)                                   as signups,
  sum(subscribers)                               as subscribers,
  sum(total_spend)                               as total_spend,
  sum(total_spend) / nullif(sum(signups), 0)     as blended_cac,
  sum(active_mrr)                                as active_mrr
from telehealth.mart_marketing_attribution
where channel like '${inputs.channel.value}'
```

<BigValue data={mkt_kpis} value=signups fmt=num0 title="Signups"/>
<BigValue data={mkt_kpis} value=subscribers fmt=num0 title="Converted to Sub"/>
<BigValue data={mkt_kpis} value=total_spend fmt=usd0 title="Spend"/>
<BigValue data={mkt_kpis} value=blended_cac fmt=usd2 title="CAC / Signup"/>
<BigValue data={mkt_kpis} value=active_mrr fmt=usd0 title="Active MRR (attributed)"/>

## Signups by channel

```sql by_channel
select
  channel,
  sum(signups)                                as signups,
  sum(subscribers)                            as subscribers,
  sum(total_spend)                            as spend,
  sum(total_spend) / nullif(sum(signups), 0)  as cac_per_signup,
  sum(active_mrr)                             as active_mrr
from telehealth.mart_marketing_attribution
where channel like '${inputs.channel.value}'
group by 1
order by signups desc
```

<BarChart data={by_channel} x=channel y=signups title="Signups by Channel" swapXY=true/>

## Acquisition cost by channel

<BarChart data={by_channel} x=channel y=cac_per_signup yFmt=usd2 title="CAC per Signup" swapXY=true/>

## Channel × campaign detail

```sql detail
select
  channel,
  campaign,
  signups,
  subscribers,
  active_subscribers,
  total_spend,
  cac_per_signup,
  cac_per_subscriber,
  active_mrr
from telehealth.mart_marketing_attribution
where channel like '${inputs.channel.value}'
order by signups desc
```

<DataTable data={detail} rows=15 search=true>
  <Column id=channel title="Channel"/>
  <Column id=campaign title="Campaign"/>
  <Column id=signups fmt=num0/>
  <Column id=subscribers fmt=num0/>
  <Column id=total_spend title="Spend" fmt=usd0/>
  <Column id=cac_per_signup title="CAC/Signup" fmt=usd2 contentType=colorscale colorScale=negative/>
  <Column id=cac_per_subscriber title="CAC/Sub" fmt=usd2/>
  <Column id=active_mrr title="Active MRR" fmt=usd0/>
</DataTable>
