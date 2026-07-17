-- Marketing: first-touch acquisition + CAC by channel/campaign.
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
from marts.mart_marketing_attribution
