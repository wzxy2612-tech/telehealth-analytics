-- Business Ops: daily MRR / ARR / active subscriptions.
select
    calendar_date,
    active_subscriptions,
    mrr,
    arr,
    arpu
from marts.fct_mrr_daily
order by calendar_date
