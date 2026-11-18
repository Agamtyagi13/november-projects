#!/usr/bin/env python3
"""Infrastructure drift detector.

READ-ONLY by design: it only runs `terraform plan` / `terraform show` and never `apply`,
so it reports differences without silently changing any resource.

Two kinds of findings, both read from the Terraform plan JSON:
  * drift          - real infrastructure changed outside Terraform (plan `resource_drift`)
  * config-diff    - real infrastructure no longer matches the code (plan `resource_changes`)

Exit codes: 0 = no drift, 2 = drift detected, 1 = error.
"""
import argparse
import datetime
import fnmatch
import json
import os
import subprocess
import sys
import urllib.request
from dataclasses import dataclass, field, asdict

MASK = "(sensitive)"


@dataclass
class Finding:
    kind: str                      # "drift" | "config-diff"
    address: str
    type: str
    actions: list
    diffs: list = field(default_factory=list)   # [(path, old, new)]


def _walk(b, a, sb, sa, path, out):
    if isinstance(b, dict) or isinstance(a, dict):
        if (b is None or isinstance(b, dict)) and (a is None or isinstance(a, dict)):
            b, a = b or {}, a or {}
            sb = sb if isinstance(sb, dict) else {}
            sa = sa if isinstance(sa, dict) else {}
            for k in sorted(set(b) | set(a)):
                _walk(b.get(k), a.get(k), sb.get(k), sa.get(k), f"{path}.{k}" if path else k, out)
            return
    if isinstance(b, list) and isinstance(a, list) and len(b) == len(a):
        sb = sb if isinstance(sb, list) else [None] * len(b)
        sa = sa if isinstance(sa, list) else [None] * len(a)
        for i, (x, y) in enumerate(zip(b, a)):
            _walk(x, y, sb[i] if i < len(sb) else None, sa[i] if i < len(sa) else None, f"{path}[{i}]", out)
        return
    if b != a:
        out.append((path or "(resource)", MASK if sb is True else b, MASK if sa is True else a))


def diff_attrs(change):
    out = []
    _walk(change.get("before"), change.get("after"),
          change.get("before_sensitive"), change.get("after_sensitive"), "", out)
    return out


def parse_plan(plan, ignore=()):
    findings = []

    def add(kind, item):
        ch = item.get("change", {})
        actions = ch.get("actions", [])
        if actions in (["no-op"], ["read"], []):
            return
        diffs = [d for d in diff_attrs(ch) if not any(fnmatch.fnmatch(d[0], p) for p in ignore)]
        if not diffs and "create" not in actions and "delete" not in actions:
            return          # everything it changed was explicitly ignored
        findings.append(Finding(kind, item["address"], item.get("type", ""), actions, diffs))

    for item in plan.get("resource_drift", []):
        add("drift", item)
    for item in plan.get("resource_changes", []):
        add("config-diff", item)
    return findings


def _fmt(v):
    return json.dumps(v) if not isinstance(v, str) or v != MASK else v


def to_markdown(findings, ts):
    if not findings:
        return f"# Drift report — {ts}\n\n**Status: ✅ NO DRIFT** — infrastructure matches Terraform state and code.\n"
    lines = [f"# Drift report — {ts}", "",
             f"**Status: ⚠️ DRIFT DETECTED** — {len(findings)} finding(s). No resources were modified.", "",
             "| Resource | Kind | Planned action |", "|---|---|---|"]
    lines += [f"| `{f.address}` | {f.kind} | {', '.join(f.actions)} |" for f in findings]
    for f in findings:
        lines += ["", f"### `{f.address}` ({f.kind})"]
        lines += [f"- `{p}`: {_fmt(o)} → {_fmt(n)}" for p, o, n in f.diffs] or ["- resource would be " + "/".join(f.actions)]
    lines += ["", "To remediate: review the changes above, then either `terraform apply` (revert the drift) "
                  "or update the Terraform code to accept it."]
    return "\n".join(lines) + "\n"


def run_terraform(workdir):
    def tf(*args, check=True):
        r = subprocess.run(["terraform", f"-chdir={workdir}", *args], capture_output=True, text=True)
        if check and r.returncode not in (0, 2):
            raise RuntimeError(f"terraform {args[0]} failed:\n{r.stderr or r.stdout}")
        return r
    tf("init", "-input=false", "-no-color")
    tf("plan", "-detailed-exitcode", "-input=false", "-lock=false", "-no-color", "-out=drift.tfplan")
    shown = tf("show", "-json", "drift.tfplan")
    return json.loads(shown.stdout)


def notify(url, text):
    req = urllib.request.Request(url, json.dumps({"text": text}).encode(), {"content-type": "application/json"})
    urllib.request.urlopen(req, timeout=10).read()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workdir", default="terraform")
    ap.add_argument("--plan-json", help="use an existing `terraform show -json` file instead of running terraform")
    ap.add_argument("--report-dir", default="reports")
    ap.add_argument("--ignore", action="append", default=[], help="attribute path glob to ignore, e.g. 'tags_all.*'")
    ap.add_argument("--webhook", default=os.getenv("DRIFT_WEBHOOK_URL"))
    a = ap.parse_args(argv)
    try:
        plan = json.load(open(a.plan_json)) if a.plan_json else run_terraform(a.workdir)
        findings = parse_plan(plan, a.ignore)
    except Exception as e:      # noqa: BLE001
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    os.makedirs(a.report_dir, exist_ok=True)
    md = to_markdown(findings, ts)
    open(os.path.join(a.report_dir, "drift-report.md"), "w").write(md)
    json.dump({"timestamp": ts, "drift": bool(findings), "findings": [asdict(f) for f in findings]},
              open(os.path.join(a.report_dir, "drift-report.json"), "w"), indent=2, default=str)
    print(md)
    if findings and a.webhook:
        try:
            notify(a.webhook, f"Infrastructure drift detected: {len(findings)} resource(s): " + ", ".join(f.address for f in findings))
        except Exception as e:  # noqa: BLE001
            print(f"warning: webhook failed: {e}", file=sys.stderr)
    return 2 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
