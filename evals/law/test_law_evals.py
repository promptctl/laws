"""Tests for the law-eval harness. Run: uv run --with jsonschema python -m unittest discover evals/law

Each case's references/<verdict>-<name>/ holds files that overlay the fixture to make
one known answer; the oracle must read each one as the verdict its name starts with,
and the untouched fixture as off_fork. That is what makes an oracle trustworthy before
any agent output is read with it.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
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


def counts(held, violated, off_fork=0, inconclusive=0, failed=0):
    return {"runs": held + violated + off_fork + inconclusive, "held": held, "violated": violated,
            "off_fork": off_fork, "inconclusive": inconclusive, "failed": failed, "run_ids": []}


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

    def test_an_undetectable_regression_is_not_saturated(self):
        self.assertEqual(sensitivity.reading(counts(5, 0), counts(2, 3))[0], "indistinguishable")

    def test_indistinguishable(self):
        self.assertEqual(sensitivity.reading(counts(2, 3), counts(3, 2))[0], "indistinguishable")

    def test_unmeasurable_when_most_runs_miss_the_fork(self):
        self.assertEqual(sensitivity.reading(counts(1, 1, off_fork=3), counts(5, 0))[0], "unmeasurable")

    def test_failed_runs_count_against_reaching_the_fork(self):
        self.assertEqual(sensitivity.reading(counts(5, 0), counts(1, 0, failed=4))[0], "unmeasurable")


def record(arm="none", verdict="violated", repeat=1, guidance=None, case_sha256="2" * 64):
    return {
        "schema_version": 2,
        "run_id": f"no-silent-failure/bank-export/{run.Arm(arm, None, None).slug}/r{repeat}",
        "law": "no-silent-failure",
        "case": "no-silent-failure/bank-export",
        "case_sha256": case_sha256,
        "arm": {"name": arm, "guidance": guidance},
        "repeat": repeat,
        "model": "claude-opus-5-5",
        "oracle": {"verdict": verdict, "detail": ""},
        "session": "runs/x/run.json",
        "diff": "diffs/x.diff",
    }


class Schema(unittest.TestCase):
    def test_record_and_summary_conform(self):
        guidance = {"path": run.SKILL_PATH, "ref": "HEAD", "commit": "0" * 40, "sha256": "1" * 64}
        records = [record("none", "violated", n) for n in (1, 2)] + [record("skill:HEAD", "held", n, guidance) for n in (1, 2)]
        for r in records:
            jsonschema.validate(r, sensitivity.RUN_SCHEMA)
        failures = [{"run_id": "no-silent-failure/bank-export/skill-head/r3", "case": "no-silent-failure/bank-export",
                     "arm": "skill:HEAD", "error": "HarnessError: api"}]
        [summary] = sensitivity.summarize(records, failures)  # summarize validates against the summary schema
        self.assertEqual(summary["arms"]["none"]["violated"], 2)
        self.assertEqual(summary["arms"]["skill:HEAD"]["failed"], 1)
        self.assertEqual(summary["comparisons"][0]["arm"], "skill:HEAD")

    def test_a_case_whose_runs_failed_entirely_is_still_summarized(self):
        failures = [{"run_id": "no-silent-failure/bank-export/none/r1", "case": "no-silent-failure/bank-export",
                     "arm": "none", "error": "HarnessError: api"}]
        [summary] = sensitivity.summarize([], failures)
        self.assertEqual(summary["arms"]["none"]["failed"], 1)

    def test_refuses_records_from_two_case_digests(self):
        records = [record(repeat=1), record(repeat=2, case_sha256="3" * 64)]
        with self.assertRaises(SystemExit):
            sensitivity.summarize(records, [])

    def test_refuses_an_arm_with_two_guidance_texts(self):
        def guidance(sha):
            return {"path": run.SKILL_PATH, "ref": "HEAD", "commit": "0" * 40, "sha256": sha}
        records = [record("skill:HEAD", "held", 1, guidance("1" * 64)), record("skill:HEAD", "held", 2, guidance("4" * 64))]
        with self.assertRaises(SystemExit):
            sensitivity.summarize(records, [])

    def test_schema_rejects_an_unknown_verdict(self):
        with self.assertRaises(jsonschema.ValidationError):
            jsonschema.validate(record(verdict="passed"), sensitivity.RUN_SCHEMA)


class LoadCases(unittest.TestCase):
    def test_refuses_a_case_name_the_record_schema_would_refuse(self):
        with tempfile.TemporaryDirectory() as tmp:
            case = Path(tmp) / "cases" / "no-silent-failure" / "Bank_Export"
            (case / "fixture").mkdir(parents=True)
            (case / "request.md").write_text("x\n")
            (case / "oracle.py").write_text("")
            with mock.patch.object(run, "HERE", Path(tmp)), self.assertRaises(SystemExit) as raised:
                run.load_cases("no-silent-failure")
        self.assertIn("Bank_Export", str(raised.exception))


class Differential(unittest.TestCase):
    def test_nondeterminism_is_inconclusive_even_when_the_job_check_fails(self):
        import differential
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "prog.py").write_text("import uuid; print(uuid.uuid4())\n")
            env = lambda: differential.Environment(("prog.py",), {}, {})  # noqa: E731
            verdict = differential.judge(Path(tmp), env, env, lambda healthy, failing: (False, "stdout is not EXPECTED"))
        self.assertEqual(verdict["verdict"], "inconclusive")


class FilesChannel(unittest.TestCase):
    def test_rewriting_a_leftover_file_with_the_same_bytes_counts_as_written(self):
        import differential
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "out.txt").write_text("same\n")
            os.utime(Path(tmp) / "out.txt", ns=(0, 0))
            (Path(tmp) / "prog.py").write_text("open('out.txt', 'w').write('same\\n')\n")
            obs = differential.observe(Path(tmp), differential.Environment(("prog.py",), {}, {}))
        self.assertEqual([rel for rel, _ in obs.files], ["out.txt"])


    def test_a_write_under_home_is_observed(self):
        import differential
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "prog.py").write_text("import pathlib; (pathlib.Path.home() / 'dead.log').write_text('x')\n")
            obs = differential.observe(Path(tmp), differential.Environment(("prog.py",), {}, {}))
        self.assertEqual([rel for rel, _ in obs.files], ["~/dead.log"])


class CaseDigest(unittest.TestCase):
    def test_digest_moves_with_the_oracle_and_ignores_residue(self):
        case = HERE / "cases" / "no-silent-failure" / "bank-export"
        with tempfile.TemporaryDirectory(dir=HERE) as tmp:
            copy = Path(tmp) / "bank-export"
            shutil.copytree(case, copy)
            base = run.case_digest(copy)
            (copy / "fixture" / "__pycache__").mkdir(exist_ok=True)
            (copy / "fixture" / "__pycache__" / "x.pyc").write_bytes(b"residue")
            self.assertEqual(run.case_digest(copy), base)
            (copy / "oracle.py").write_text((copy / "oracle.py").read_text() + "\n")
            self.assertNotEqual(run.case_digest(copy), base)


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
