"""Tests for the law-eval harness. Run: uv run --with jsonschema python -m unittest discover evals/law

Each case's references/<verdict>-<name>/ holds files that overlay the fixture to make
one known answer; the oracle must read each one as the verdict its name starts with,
and the untouched fixture as off_fork. That is what makes an oracle trustworthy before
any agent output is read with it.
"""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import jsonschema

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import run  # noqa: E402
import sensitivity  # noqa: E402

CASES = sorted(p for p in (HERE / "cases").glob("*/*") if (p / "oracle.py").exists())


def oracle_verdict(case: Path, overlay: Path | None) -> str:
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp) / "work"
        shutil.copytree(case / "fixture", work)
        if overlay is not None:
            shutil.copytree(overlay, work, dirs_exist_ok=True)
        out = subprocess.run([sys.executable, str(case / "oracle.py"), str(work)], capture_output=True, text=True, check=True)
        return json.loads(out.stdout)["verdict"]


class OracleReadsEveryReference(unittest.TestCase):
    def test_cases_exist(self):
        self.assertGreaterEqual(len(CASES), 2)

    def test_untouched_fixture_is_off_fork(self):
        for case in CASES:
            with self.subTest(case=case.name):
                self.assertEqual(oracle_verdict(case, None), "off_fork")

    def test_each_reference_reads_as_its_name(self):
        for case in CASES:
            references = sorted((case / "references").iterdir())
            self.assertTrue({r.name.split("-")[0] for r in references} >= {"held", "violated"}, case)
            for ref in references:
                with self.subTest(case=case.name, reference=ref.name):
                    self.assertEqual(oracle_verdict(case, ref), ref.name.split("-")[0])


class FisherExact(unittest.TestCase):
    def test_known_values(self):
        # Reference values from scipy.stats.fisher_exact(..., alternative="two-sided").
        self.assertAlmostEqual(sensitivity.fisher_two_sided(5, 0, 0, 5), 0.007936507936507936)
        self.assertAlmostEqual(sensitivity.fisher_two_sided(4, 1, 1, 4), 0.20634920634920634)
        self.assertAlmostEqual(sensitivity.fisher_two_sided(5, 0, 1, 4), 0.047619047619047616)
        self.assertAlmostEqual(sensitivity.fisher_two_sided(3, 2, 3, 2), 1.0)


def counts(held, violated, off_fork=0, inconclusive=0):
    return {"runs": held + violated + off_fork + inconclusive, "held": held, "violated": violated,
            "off_fork": off_fork, "inconclusive": inconclusive, "run_ids": []}


class Readings(unittest.TestCase):
    def test_saturated_when_control_never_violates(self):
        self.assertEqual(sensitivity.reading(counts(5, 0), counts(5, 0))[0], "saturated")

    def test_separate(self):
        label, p = sensitivity.reading(counts(0, 5), counts(5, 0))
        self.assertEqual(label, "separate")
        self.assertLess(p, 0.05)

    def test_regressed_is_not_saturated(self):
        label, p = sensitivity.reading(counts(5, 0), counts(0, 5))
        self.assertEqual(label, "regressed")
        self.assertLess(p, 0.05)

    def test_regressed_is_not_separate(self):
        self.assertEqual(sensitivity.reading(counts(4, 1), counts(0, 5))[0], "regressed")

    def test_indistinguishable(self):
        self.assertEqual(sensitivity.reading(counts(2, 3), counts(3, 2))[0], "indistinguishable")

    def test_unmeasurable_when_most_runs_miss_the_fork(self):
        self.assertEqual(sensitivity.reading(counts(1, 1, off_fork=3), counts(5, 0))[0], "unmeasurable")


def record(arm="none", verdict="violated", repeat=1, guidance=None):
    return {
        "schema_version": 1,
        "run_id": f"no-silent-failure/bank-export/{run.Arm(arm, None, None).slug}/r{repeat}",
        "law": "no-silent-failure",
        "case": "no-silent-failure/bank-export",
        "arm": {"name": arm, "guidance": guidance},
        "repeat": repeat,
        "model": {"requested": "claude-opus-5-5", "session": "claude-opus-5-5", "billed": ["claude-opus-5-5"]},
        "claude_code_version": "2.1.288",
        "started_at": "2026-10-03T12:00:00+00:00",
        "duration_ms": 1000,
        "turns": 4,
        "tokens": {"input": 10, "output": 20, "cache_read": 30, "cache_creation": 40},
        "cost_usd": 0.1,
        "session": {"session_id": "s", "is_error": False, "terminal_reason": "completed"},
        "isolation": {"plugins": ["cc-plugin-telemetry"], "mcp_servers": [], "tools": ["Bash"]},
        "oracle": {"verdict": verdict, "detail": ""},
        "transcript": "transcripts/x.jsonl",
        "diff": "diffs/x.diff",
    }


class Schema(unittest.TestCase):
    def test_record_and_summary_conform(self):
        guidance = {"path": run.SKILL_PATH, "ref": "HEAD", "commit": "0" * 40, "sha256": "1" * 64}
        records = [record("none", "violated", n) for n in (1, 2)] + [record("skill:HEAD", "held", n, guidance) for n in (1, 2)]
        for r in records:
            jsonschema.validate(r, sensitivity.RUN_SCHEMA)
        [summary] = sensitivity.summarize(records)  # summarize validates against the summary schema
        self.assertEqual(summary["arms"]["none"]["violated"], 2)
        self.assertEqual(summary["comparisons"][0]["arm"], "skill:HEAD")

    def test_schema_rejects_an_unknown_verdict(self):
        with self.assertRaises(jsonschema.ValidationError):
            jsonschema.validate(record(verdict="passed"), sensitivity.RUN_SCHEMA)


class Differential(unittest.TestCase):
    def test_nondeterminism_is_inconclusive_even_when_the_job_check_fails(self):
        import differential
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "prog.py").write_text("import uuid; print(uuid.uuid4())\n")
            env = lambda: differential.Environment(("prog.py",), {}, {})  # noqa: E731
            verdict = differential.judge(Path(tmp), env, env, lambda healthy, failing: (False, "stdout is not EXPECTED"))
        self.assertEqual(verdict["verdict"], "inconclusive")


class Isolation(unittest.TestCase):
    def test_refuses_a_non_builtin_plugin(self):
        init = {"plugins": [{"name": "laws", "path": "/somewhere/laws"}], "mcp_servers": [], "tools": []}
        with self.assertRaisesRegex(RuntimeError, "isolation is broken"):
            run.isolation_of(init)

    def test_accepts_builtins(self):
        init = {"plugins": [{"name": "cc-plugin-telemetry", "path": "builtin"}], "mcp_servers": [], "tools": ["Read"]}
        self.assertEqual(run.isolation_of(init)["plugins"], ["cc-plugin-telemetry"])


class Arms(unittest.TestCase):
    def test_skill_arm_reads_the_skill_at_its_ref(self):
        arm = run.resolve_arm("skill:HEAD")
        self.assertIn("[LAW:no-silent-failure]", arm.guidance_text)
        self.assertRegex(arm.guidance["commit"], "^[0-9a-f]{40}$")

    def test_bad_arm_spec_dies(self):
        with self.assertRaises(SystemExit):
            run.resolve_arm("laws")


if __name__ == "__main__":
    unittest.main()
