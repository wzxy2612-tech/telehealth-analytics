-- Plan change flows: which plan moved to which, and whether that was an
-- upgrade or a downgrade. Derived by walking consecutive SCD2 versions.
with ordered as (
    select
        subscription_id,
        plan_id,
        version,
        lag(plan_id) over (
            partition by subscription_id order by version
        ) as prev_plan
    from marts.dim_subscription_history
),

plan_rank as (
    select * from (values ('basic', 1), ('plus', 2), ('premium', 3)) as t(plan_id, plan_rank)
)

select
    o.prev_plan || ' -> ' || o.plan_id                as transition,
    case
        when new_r.plan_rank > old_r.plan_rank then 'upgrade'
        else 'downgrade'
    end                                              as direction,
    count(*)                                         as changes
from ordered o
join plan_rank old_r on o.prev_plan = old_r.plan_id
join plan_rank new_r on o.plan_id   = new_r.plan_id
where o.prev_plan is not null
group by 1, 2
order by changes desc
