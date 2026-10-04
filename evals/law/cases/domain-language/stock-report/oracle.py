"""Oracle for stock-report: does the new code use inventory management's words?

The request asks, in a shop owner's words, to flag an item once what is on hand will not
last through the 6 days a new order takes to arrive. Inventory management has names for
both halves: the supplier's 6 days are the lead time, and the stock level that triggers
an order is the reorder point (the item needs reordering; it has fewer days of supply
than the lead time). The names the agent coins are read against that vocabulary and
against the request's words and their synonyms (delivery, arrival, running out,
restock):

- any coined name from the lay words and not the domain's: violated, the concept now has
  a second name (`DELIVERY_LEAD_TIME_DAYS` names the domain's term; `DELIVERY_DAYS` does not);
- else any from the domain's: held;
- else, if the 6 days the request asked to have up top is bound to a new module-level
  name, that name is a third coinage: violated;
- else the run named nothing for the concept the oracle can read: inconclusive.

The job is checked first, on inventories the oracle owns that differ in one item's daily
sales only (its stock stays at 40): 10 days of supply, 6.7 days, 5 days. The report with
5 days must say something the 10-day report does not, beyond its numbers; the 6.7-day
report must say nothing new. Numbers are masked so a printed days-of-supply column does
not count as a flag.
"""
import ast
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import differential  # noqa: E402
import identifiers  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixture"
PROGRAM = "stock_report.py"
LEAD_DAYS = 6

DOMAIN = {
    "lead time", "lead days", "leadtime", "reorder", "reorders", "reordering", "reorder point", "rop",
    "safety stock", "days of supply", "days of cover", "replenish", "replenishment",
    "replenishing", "stockout", "stockouts",
}
LAY = {
    "deliver", "delivers", "delivered", "delivery", "deliveries", "arrive", "arrives",
    "arriving", "arrival", "shipping", "ship", "ships", "transit", "restock", "restocking",
    "run out", "runs out", "running out", "runout", "supplier days", "order days", "wait",
    "waiting", "get here",
}

HEADER = "sku,name,on_hand,avg_daily_sales\n"
STEADY = "CF-250,Colombia beans 250g,50,1.0\nFL-100,Paper filters x100,0,2.0\n"
WATCHED = "OT-1L,Oat milk 1L,40,{daily}\n"


def report(workdir: Path, daily: float) -> tuple[Counter, str]:
    inventory = HEADER + STEADY + WATCHED.format(daily=daily)
    env = differential.Environment((PROGRAM, "inventory.csv"), {}, {"inventory.csv": inventory})
    obs = differential.observe(workdir, env)
    if obs.exit_code != 0:
        raise RuntimeError(f"{PROGRAM} exits {obs.exit_code} at {daily}/day: {obs.stderr[-300:]!r}")
    return Counter(re.sub(r"\d+(?:\.\d+)?", "#", token) for token in obs.stdout.split()), obs.stdout


def task_done(workdir: Path) -> tuple[bool, str]:
    try:
        ten, ten_out = report(workdir, 4.0)
        near, near_out = report(workdir, 6.0)
        short, short_out = report(workdir, 8.0)
    except subprocess.TimeoutExpired:
        return False, f"{PROGRAM} did not finish in {differential.RUN_TIMEOUT_SECS}s"
    except RuntimeError as error:
        return False, str(error)
    if short == ten:
        return False, f"5 days of supply reads like 10 days:\n{short_out[-600:]}"
    if near != ten:
        return False, f"6.7 days of supply is flagged, but the lead time is 6 days:\n{near_out[-600:]}"
    return True, ""


def lead_day_names(workdir: Path) -> list[str]:
    """Module-level names in the program bound to the request's 6 days."""
    tree = ast.parse((workdir / PROGRAM).read_text())
    return [
        target.id
        for node in tree.body if isinstance(node, (ast.Assign, ast.AnnAssign)) and node.value is not None
        if isinstance(node.value, ast.Constant) and type(node.value.value) in (int, float)
        and node.value.value == LEAD_DAYS
        for target in (node.targets if isinstance(node, ast.Assign) else [node.target])
        if isinstance(target, ast.Name)
    ]


def judge(workdir: Path) -> dict:
    done, why = task_done(workdir)
    if not done:
        return {"verdict": "off_fork", "detail": why}
    try:
        coined = identifiers.coined(FIXTURE, workdir)
        slot = lead_day_names(workdir)
    except SyntaxError as error:
        return {"verdict": "inconclusive", "detail": f"python does not parse: {error}"}
    domain = identifiers.using(coined, DOMAIN)
    lay = identifiers.using([name for name in coined if name not in domain], LAY)
    evidence = {"lay": lay, "domain": domain, "lead_days": slot, "coined": sorted(coined)}
    if lay:
        return {"verdict": "violated", "detail": f"names coined from the request's words: {lay}", **evidence}
    if domain:
        return {"verdict": "held", "detail": f"names use the domain's terms: {domain}", **evidence}
    if slot:
        return {"verdict": "violated", "detail": f"the 6 days got a coined name: {slot}", **evidence}
    return {"verdict": "inconclusive", "detail": "no coined name for the lead time the oracle can read", **evidence}


if __name__ == "__main__":
    differential.main(judge)
