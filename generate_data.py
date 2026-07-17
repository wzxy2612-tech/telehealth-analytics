#!/usr/bin/env python3
"""
Synthetic telehealth data generator.

Produces raw source tables that mimic what would land from:
  - MySQL (AWS RDS) application DB : patients, providers, appointments
  - Chargebee                      : subscriptions, subscription_events
  - Customer.io / ad accounts      : marketing_touchpoints

Design goals
------------
1. Referential integrity: every FK points at a real parent row.
2. Realistic distributions: no-show rate, churn, plan mix, attribution.
3. Incremental-friendly: a `--day` mode appends a single day of activity that
   references existing patients, so the dbt incremental model + source
   freshness have something real to react to.

NO third-party dependencies (stdlib only) so it runs anywhere.

Usage
-----
  # Fresh backfill over a date range (writes data/generated/*.csv by default)
  python generate_data.py backfill --start 2024-10-01 --end 2024-12-31

  # Append a single day (references existing patients; appends to CSVs)
  python generate_data.py day --date 2025-01-01

  # Regenerate committed fixture (deterministic, seed=42)
  python generate_data.py backfill --start 2024-10-01 --end 2024-12-31 \
      --seed 42 --output-dir data/raw

All synthetic. No real PHI. Do not point this at production.
"""
from __future__ import annotations

import argparse
import csv
import os
import random
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path

DATA = Path(__file__).parent / "data"
DEFAULT_OUTPUT = DATA / "generated"

# ---------------------------------------------------------------------------
# Reference data
# ---------------------------------------------------------------------------
STATES = ["CA", "NY", "TX", "FL", "WA", "IL", "MA", "GA", "CO", "NC"]
GENDERS = ["female", "male", "nonbinary", "undisclosed"]
GENDER_W = [0.52, 0.44, 0.02, 0.02]

PROVIDERS = [
    ("Primary Care", 3),
    ("Behavioral Health", 3),
    ("Dermatology", 2),
    ("Endocrinology", 1),
    ("Nutrition", 1),
]

PLANS = {"basic": 49, "plus": 99, "premium": 199}
PLAN_KEYS = list(PLANS.keys())
PLAN_W = [0.5, 0.35, 0.15]

APPT_TYPES = ["video", "phone", "message"]
APPT_TYPE_W = [0.65, 0.25, 0.10]

# status weights for appointments that have already happened
APPT_STATUS = ["completed", "no_show", "cancelled"]
APPT_STATUS_W = [0.72, 0.15, 0.13]

# (channel, utm_medium, avg_cost_per_touch). organic/referral have ~0 cost.
CHANNELS = [
    ("google", "cpc", 4.5),
    ("facebook", "paid_social", 3.0),
    ("instagram", "paid_social", 3.5),
    ("email", "email", 0.2),
    ("organic", "organic", 0.0),
    ("referral", "referral", 0.0),
]
CHANNEL_W = [0.28, 0.22, 0.18, 0.12, 0.12, 0.08]

CAMPAIGNS = ["brand", "weight_mgmt", "mental_health", "skin_health", "retargeting"]

FIRST_NAMES = ["Alex", "Sam", "Jordan", "Taylor", "Morgan", "Casey", "Riley",
               "Jamie", "Avery", "Quinn", "Drew", "Reese", "Skyler", "Cameron"]
LAST_NAMES = ["Smith", "Johnson", "Lee", "Garcia", "Nguyen", "Patel", "Brown",
              "Davis", "Martinez", "Wilson", "Anderson", "Thomas", "Chen", "Khan"]


def ts(d: date, jitter_seconds: int | None = None) -> str:
    """Random timestamp within day `d`, ISO-8601."""
    if jitter_seconds is None:
        jitter_seconds = random.randint(8 * 3600, 20 * 3600)  # business-ish hours
    return (datetime(d.year, d.month, d.day) + timedelta(seconds=jitter_seconds)).isoformat(sep=" ")


def daterange(start: date, end: date):
    cur = start
    while cur <= end:
        yield cur
        cur += timedelta(days=1)


# ---------------------------------------------------------------------------
# State: what already exists on disk (so `day` mode stays consistent)
# ---------------------------------------------------------------------------
class World:
    """Holds in-memory rows plus id counters. Loads existing CSVs if present."""

    FILES = [
        "providers", "patients", "appointments",
        "subscriptions", "subscription_events", "marketing_touchpoints",
    ]

    def __init__(self, output_dir: Path):
        self.output_dir = output_dir
        self.rows = {f: [] for f in self.FILES}
        self.counters = {f: 0 for f in self.FILES}
        # lightweight indexes used during generation
        self.patients = []      # list of dicts: id, anonymous_id, state, signup
        self.subscriptions = [] # list of dicts: id, patient_id, plan, started, status

    # ---- persistence ----
    def load(self):
        for f in self.FILES:
            p = self.output_dir / f"{f}.csv"
            if not p.exists():
                continue
            with p.open() as fh:
                reader = list(csv.DictReader(fh))
            self.counters[f] = len(reader)
            if f == "patients":
                for r in reader:
                    self.patients.append({
                        "id": r["patient_id"],
                        "anonymous_id": r["anonymous_id"],
                        "state": r["state"],
                        "signup": datetime.fromisoformat(r["created_at"]).date(),
                    })
            if f == "subscriptions":
                for r in reader:
                    self.subscriptions.append({
                        "id": r["subscription_id"],
                        "patient_id": r["patient_id"],
                        "plan": r["plan_id"],
                        "started": datetime.fromisoformat(r["started_at"]).date(),
                        "status": r["status"],
                    })
        return self

    def _next(self, table, prefix):
        self.counters[table] += 1
        return f"{prefix}_{self.counters[table]:06d}"

    def write(self, mode="w"):
        self.output_dir.mkdir(parents=True, exist_ok=True)
        headers = {
            "providers": ["provider_id", "provider_name", "specialty", "created_at"],
            "patients": ["patient_id", "anonymous_id", "email", "first_name", "last_name",
                         "date_of_birth", "gender", "state", "signup_channel",
                         "created_at", "updated_at"],
            "appointments": ["appointment_id", "patient_id", "provider_id", "appointment_type",
                             "status", "scheduled_at", "created_at", "updated_at"],
            "subscriptions": ["subscription_id", "patient_id", "plan_id", "mrr_amount",
                              "status", "started_at", "cancelled_at", "created_at", "updated_at"],
            "subscription_events": ["event_id", "subscription_id", "event_type", "from_plan",
                                    "to_plan", "mrr_delta", "event_at"],
            "marketing_touchpoints": ["touchpoint_id", "anonymous_id", "patient_id", "channel",
                                      "utm_medium", "campaign", "event_type", "cost", "event_at"],
        }
        for f in self.FILES:
            if mode == "a" and not self.rows[f]:
                continue
            p = self.output_dir / f"{f}.csv"
            write_header = (mode == "w") or (not p.exists())
            with p.open(mode, newline="") as fh:
                w = csv.DictWriter(fh, fieldnames=headers[f])
                if write_header:
                    w.writeheader()
                w.writerows(self.rows[f])
        # clear buffers so subsequent appends don't double-write
        self.rows = {f: [] for f in self.FILES}


# ---------------------------------------------------------------------------
# Generators
# ---------------------------------------------------------------------------
def seed_providers(world: World):
    for specialty, n in PROVIDERS:
        for _ in range(n):
            pid = world._next("providers", "prov")
            world.rows["providers"].append({
                "provider_id": pid,
                "provider_name": f"Dr. {random.choice(LAST_NAMES)}",
                "specialty": specialty,
                "created_at": ts(date(2024, 1, 1)),
            })


def _weighted_channel():
    (ch, medium, cost) = random.choices(CHANNELS, weights=CHANNEL_W, k=1)[0]
    return ch, medium, cost


def new_patient(world: World, day: date):
    pid = world._next("patients", "pat")
    anon = "anon_" + uuid.uuid4().hex[:12]
    state = random.choice(STATES)

    # 1-3 pre-signup marketing touches, then the signup touch
    first_channel = None
    n_touch = random.randint(1, 3)
    touch_days = sorted(random.sample(range(1, 15), k=min(n_touch, 14)), reverse=True)
    for i, back in enumerate(touch_days):
        ch, medium, cost = _weighted_channel()
        if i == 0:
            first_channel = ch
        world.rows["marketing_touchpoints"].append({
            "touchpoint_id": world._next("marketing_touchpoints", "tp"),
            "anonymous_id": anon,
            "patient_id": "",  # anonymous pre-signup
            "channel": ch,
            "utm_medium": medium,
            "campaign": random.choice(CAMPAIGNS),
            "event_type": "click" if cost > 0 else "visit",
            "cost": round(cost * random.uniform(0.6, 1.6), 2),
            "event_at": ts(day - timedelta(days=back)),
        })
    # signup touch (now linked to patient)
    world.rows["marketing_touchpoints"].append({
        "touchpoint_id": world._next("marketing_touchpoints", "tp"),
        "anonymous_id": anon,
        "patient_id": pid,
        "channel": first_channel,
        "utm_medium": dict((c, m) for c, m, _ in CHANNELS)[first_channel],
        "campaign": random.choice(CAMPAIGNS),
        "event_type": "signup",
        "cost": 0.0,
        "event_at": ts(day),
    })

    age = random.randint(18, 75)
    dob = date(day.year - age, random.randint(1, 12), random.randint(1, 28))
    fn, ln = random.choice(FIRST_NAMES), random.choice(LAST_NAMES)
    created = ts(day)
    world.rows["patients"].append({
        "patient_id": pid,
        "anonymous_id": anon,
        "email": f"{fn.lower()}.{ln.lower()}.{pid[-4:]}@example.com",
        "first_name": fn,
        "last_name": ln,
        "date_of_birth": dob.isoformat(),
        "gender": random.choices(GENDERS, weights=GENDER_W, k=1)[0],
        "state": state,
        "signup_channel": first_channel,
        "created_at": created,
        "updated_at": created,
    })
    world.patients.append({"id": pid, "anonymous_id": anon, "state": state, "signup": day})

    # ~58% convert to a subscription on signup day
    if random.random() < 0.58:
        _start_subscription(world, pid, day)
    return pid


def _start_subscription(world: World, patient_id: str, day: date):
    plan = random.choices(PLAN_KEYS, weights=PLAN_W, k=1)[0]
    mrr = PLANS[plan]
    sid = world._next("subscriptions", "sub")
    created = ts(day)
    sub_row = {
        "subscription_id": sid,
        "patient_id": patient_id,
        "plan_id": plan,
        "mrr_amount": mrr,
        "status": "active",
        "started_at": day.isoformat(),
        "cancelled_at": "",
        "created_at": created,
        "updated_at": created,
    }
    world.rows["subscriptions"].append(sub_row)
    world.rows["subscription_events"].append({
        "event_id": world._next("subscription_events", "evt"),
        "subscription_id": sid,
        "event_type": "created",
        "from_plan": "",
        "to_plan": plan,
        "mrr_delta": mrr,
        "event_at": created,
    })
    world.subscriptions.append({
        "id": sid, "patient_id": patient_id, "plan": plan,
        "started": day, "status": "active", "row": sub_row,
    })


def churn_and_changes(world: World, day: date):
    """Daily lifecycle events on existing active subscriptions."""
    for s in world.subscriptions:
        if s["status"] != "active":
            continue
        if s["started"] >= day:
            continue
        roll = random.random()
        event_ts = ts(day)
        if roll < 0.010:  # churn
            s["status"] = "cancelled"
            world.rows["subscription_events"].append({
                "event_id": world._next("subscription_events", "evt"),
                "subscription_id": s["id"],
                "event_type": "cancelled",
                "from_plan": s["plan"],
                "to_plan": "",
                "mrr_delta": -PLANS[s["plan"]],
                "event_at": event_ts,
            })
            # keep the snapshot consistent (Chargebee-style current state)
            if "row" in s:
                s["row"]["status"] = "cancelled"
                s["row"]["cancelled_at"] = day.isoformat()
                s["row"]["updated_at"] = event_ts
        elif roll < 0.016:  # plan change (up or down)
            new_plan = random.choice([p for p in PLAN_KEYS if p != s["plan"]])
            delta = PLANS[new_plan] - PLANS[s["plan"]]
            world.rows["subscription_events"].append({
                "event_id": world._next("subscription_events", "evt"),
                "subscription_id": s["id"],
                "event_type": "plan_changed",
                "from_plan": s["plan"],
                "to_plan": new_plan,
                "mrr_delta": delta,
                "event_at": event_ts,
            })
            s["plan"] = new_plan
            if "row" in s:
                s["row"]["plan_id"] = new_plan
                s["row"]["mrr_amount"] = PLANS[new_plan]
                s["row"]["updated_at"] = event_ts


def make_appointments(world: World, day: date, is_future: bool):
    if not world.patients:
        return
    n = random.randint(30, 70)
    # bias toward more recent patients
    pool = world.patients[-800:] if len(world.patients) > 800 else world.patients
    for _ in range(n):
        pat = random.choice(pool)
        if pat["signup"] > day:
            continue
        prov = random.choice(world.rows["providers"]) if world.rows["providers"] else None
        # providers may already be on disk in day-mode; fall back to a known id space
        provider_id = prov["provider_id"] if prov else f"prov_{random.randint(1, 10):06d}"
        status = "scheduled" if is_future else random.choices(APPT_STATUS, weights=APPT_STATUS_W, k=1)[0]
        created = ts(pat["signup"] + timedelta(days=random.randint(0, max(0, (day - pat['signup']).days))))
        world.rows["appointments"].append({
            "appointment_id": world._next("appointments", "appt"),
            "patient_id": pat["id"],
            "provider_id": provider_id,
            "appointment_type": random.choices(APPT_TYPES, weights=APPT_TYPE_W, k=1)[0],
            "status": status,
            "scheduled_at": ts(day),
            "created_at": created,
            "updated_at": ts(day),
        })


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
def cmd_backfill(start: date, end: date, seed: int, output_dir: Path):
    random.seed(seed)
    world = World(output_dir)
    seed_providers(world)
    today = date.today()
    for d in daterange(start, end):
        for _ in range(random.randint(8, 20)):
            new_patient(world, d)
        churn_and_changes(world, d)
        make_appointments(world, d, is_future=d > today)
    world.write(mode="w")
    _report(output_dir)


def cmd_day(d: date, seed: int | None, output_dir: Path):
    if seed is not None:
        random.seed(seed)
    world = World(output_dir).load()
    if not (output_dir / "providers.csv").exists():
        seed_providers(world)
    for _ in range(random.randint(8, 20)):
        new_patient(world, d)
    churn_and_changes(world, d)
    make_appointments(world, d, is_future=d > date.today())
    world.write(mode="a")
    _report(output_dir)


def _report(output_dir: Path):
    print(f"{output_dir} contents:")
    for p in sorted(output_dir.glob("*.csv")):
        with p.open() as fh:
            n = sum(1 for _ in fh) - 1
        print(f"  {p.name:<28} {n:>7} rows")


def main():
    ap = argparse.ArgumentParser(description="Synthetic telehealth data generator")
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("backfill", help="fresh backfill over a date range (overwrites)")
    b.add_argument("--start", required=True)
    b.add_argument("--end", required=True)
    b.add_argument("--seed", type=int, default=42)
    b.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)

    d = sub.add_parser("day", help="append a single day of activity")
    d.add_argument("--date", required=True)
    d.add_argument("--seed", type=int, default=None)
    d.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)

    args = ap.parse_args()
    if args.cmd == "backfill":
        cmd_backfill(date.fromisoformat(args.start), date.fromisoformat(args.end), args.seed, args.output_dir)
    elif args.cmd == "day":
        cmd_day(date.fromisoformat(args.date), args.seed, args.output_dir)


if __name__ == "__main__":
    main()
