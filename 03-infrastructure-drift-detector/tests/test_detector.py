import json, os, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from drift_detector.detector import parse_plan, to_markdown, main

PLAN_DRIFT = {
    "resource_drift": [
        {"address": "aws_s3_bucket.data", "type": "aws_s3_bucket",
         "change": {"actions": ["update"],
                    "before": {"tags": {"Owner": "platform", "Project": "drift-demo"}},
                    "after": {"tags": {"Owner": "someone-else", "Project": "drift-demo", "Debug": "true"}}}},
        {"address": "aws_sqs_queue.jobs", "type": "aws_sqs_queue",
         "change": {"actions": ["update"], "before": {"visibility_timeout_seconds": 30},
                    "after": {"visibility_timeout_seconds": 999}}}],
    "resource_changes": [
        {"address": "aws_s3_bucket_versioning.data", "type": "aws_s3_bucket_versioning",
         "change": {"actions": ["update"],
                    "before": {"versioning_configuration": [{"status": "Enabled"}]},
                    "after": {"versioning_configuration": [{"status": "Suspended"}]}}},
        {"address": "aws_s3_bucket.data", "type": "aws_s3_bucket", "change": {"actions": ["no-op"]}}],
}
PLAN_CLEAN = {"resource_drift": [], "resource_changes": [{"address": "x", "type": "t", "change": {"actions": ["no-op"]}}]}


class T(unittest.TestCase):
    def test_detects_drift_and_config_diffs(self):
        f = parse_plan(PLAN_DRIFT)
        self.assertEqual([(x.kind, x.address) for x in f],
                         [("drift", "aws_s3_bucket.data"), ("drift", "aws_sqs_queue.jobs"),
                          ("config-diff", "aws_s3_bucket_versioning.data")])

    def test_attribute_level_diff(self):
        paths = {d[0]: (d[1], d[2]) for d in parse_plan(PLAN_DRIFT)[1].diffs}
        self.assertEqual(paths["visibility_timeout_seconds"], (30, 999))
        tags = {d[0]: (d[1], d[2]) for d in parse_plan(PLAN_DRIFT)[0].diffs}
        self.assertEqual(tags["tags.Owner"], ("platform", "someone-else"))
        self.assertEqual(tags["tags.Debug"], (None, "true"))

    def test_clean_plan_has_no_findings(self):
        self.assertEqual(parse_plan(PLAN_CLEAN), [])

    def test_sensitive_values_masked(self):
        plan = {"resource_drift": [{"address": "a.b", "type": "a", "change": {
            "actions": ["update"], "before": {"password": "old"}, "after": {"password": "new"},
            "before_sensitive": {"password": True}, "after_sensitive": {"password": True}}}]}
        d = parse_plan(plan)[0].diffs[0]
        self.assertEqual(d, ("password", "(sensitive)", "(sensitive)"))
        self.assertNotIn("old", to_markdown(parse_plan(plan), "t"))

    def test_ignore_patterns(self):
        f = parse_plan(PLAN_DRIFT, ignore=["tags.*", "visibility_timeout_seconds"])
        self.assertEqual([x.address for x in f], ["aws_s3_bucket_versioning.data"])

    def test_missing_resource_reported(self):
        plan = {"resource_changes": [{"address": "aws_sqs_queue.jobs", "type": "aws_sqs_queue",
                                      "change": {"actions": ["create"], "before": None, "after": {"name": "q"}}}]}
        self.assertEqual(parse_plan(plan)[0].actions, ["create"])

    def test_cli_exit_codes_and_reports(self):
        with tempfile.TemporaryDirectory() as d:
            for name, plan, code in (("drift", PLAN_DRIFT, 2), ("clean", PLAN_CLEAN, 0)):
                p = os.path.join(d, f"{name}.json"); json.dump(plan, open(p, "w"))
                rep = os.path.join(d, f"rep-{name}")
                self.assertEqual(main(["--plan-json", p, "--report-dir", rep]), code)
                self.assertTrue(os.path.exists(os.path.join(rep, "drift-report.md")))
                self.assertEqual(json.load(open(os.path.join(rep, "drift-report.json")))["drift"], code == 2)

    def test_bad_input_returns_error(self):
        self.assertEqual(main(["--plan-json", "/nonexistent.json"]), 1)


if __name__ == "__main__":
    unittest.main()
