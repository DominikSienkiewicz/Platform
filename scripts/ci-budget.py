#!/usr/bin/env python3
"""ci-budget.py <jobs.json> <budgets.json> <workflow>: each job's duration against its budget (N-REL-15).

<jobs.json> is the GitHub API listing of a run's jobs (`gh api repos/<repo>/actions/runs/<id>/jobs`). A job takes
the budget of the longest name prefix in budgets.json under <workflow>. An overrun prints a `::warning title=CI
budget::` line and never fails; the job summary gets one row per job. Runner variance makes the numbers noisy,
which is why the budget only warns and timeout-minutes stays the hard ceiling.
"""
import json
import os
import sys
from datetime import datetime


def minutes(job):
    started, completed = job.get("started_at"), job.get("completed_at")
    if not started or not completed:
        return None
    parse = lambda value: datetime.fromisoformat(value.replace("Z", "+00:00"))
    return (parse(completed) - parse(started)).total_seconds() / 60


def main():
    jobs_path, budgets_path, workflow = sys.argv[1:4]
    jobs = json.load(open(jobs_path)).get("jobs", [])
    budgets = json.load(open(budgets_path)).get(workflow, {})
    rows = []
    for job in sorted(jobs, key=lambda item: item["name"]):
        took = minutes(job)
        if took is None or job.get("conclusion") == "skipped":
            continue
        prefix = max((key for key in budgets if job["name"].startswith(key)), key=len, default=None)
        budget = budgets.get(prefix)
        if budget is None:
            verdict = "no budget"
            print(f"::notice title=CI budget::{job['name']} has no budget in .github/ci-budgets.json")
        elif took > budget:
            verdict = f"over by {took - budget:.1f} min"
            print(f"::warning title=CI budget::{job['name']} took {took:.1f} min, budget {budget} min")
        else:
            verdict = "within"
        rows.append(f"| {job['name']} | {took:.1f} | {budget if budget is not None else '—'} | {verdict} |")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as out:
            out.write(f"## CI budget of {workflow}\n\n| Job | Minutes | Budget | Verdict |\n|---|---|---|---|\n")
            out.write("\n".join(rows) + "\n")


main()
