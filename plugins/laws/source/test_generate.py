"""Tests for generate.py. Run: python3 -m unittest discover plugins/laws/source"""
from __future__ import annotations

import json
import re
import shutil
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

import generate


class SourceTree:
    """A scratch copy of the sources, the committed outputs and their counts, safe to edit."""

    def __enter__(self) -> "SourceTree":
        self.dir = Path(tempfile.mkdtemp())
        self.source = self.dir / "code"
        self.skill_dir = self.dir / "skill"
        self.target = self.skill_dir / "SKILL.md"
        self.counts = self.dir / "counts.json"
        shutil.copytree(generate.SOURCE, self.source)
        shutil.copytree(generate.SKILL_DIR, self.skill_dir)
        shutil.copy(generate.COUNTS, self.counts)
        return self

    def args(self) -> list[str]:
        return ["--source", str(self.source), "--skill-dir", str(self.skill_dir), "--counts", str(self.counts)]

    def __exit__(self, *exc) -> None:
        shutil.rmtree(self.dir)

    def edit(self, relative: str, old: str, new: str, count: int | None = None) -> None:
        """Replace old, which must occur exactly once - or, given count, at least once, replacing the first count."""
        path = self.source / relative
        text = path.read_text()
        found = text.count(old)
        if found != 1 and not (count and found >= 1):
            raise AssertionError(f"{relative}: expected one {old!r}, found {found}")
        path.write_text(text.replace(old, new, count or 1))

    def check(self) -> tuple[int, str]:
        with redirect_stderr(StringIO()) as err, redirect_stdout(StringIO()):
            code = generate.main(["--check", *self.args()])
        return code, err.getvalue()

    def generate(self) -> tuple[int, str, str]:
        with redirect_stderr(StringIO()) as err, redirect_stdout(StringIO()) as out:
            code = generate.main(self.args())
        return code, out.getvalue(), err.getvalue()


def paragraphs(text: str) -> list[str]:
    return [p.strip() for p in text.split("\n\n") if p.strip()]


def section(text: str, law: str) -> str:
    """The law's section: its heading up to the next heading or rule."""
    start = text.index(f"## [LAW:{law}] - ")
    ends = [i for i in (text.find("\n## ", start + 1), text.find("\n---\n", start)) if i != -1]
    return text[start:min(ends)]


def skill_text() -> str:
    return generate.build().outputs[0].text


class CommittedSkill(unittest.TestCase):
    def test_committed_outputs_are_current(self):
        for output in generate.build().outputs:
            with self.subTest(output=output.path):
                self.assertEqual(
                    (generate.SKILL_DIR / output.path).read_text(),
                    output.text,
                    f"{output.path} is stale: run python3 plugins/laws/source/generate.py",
                )

    def test_committed_counts_are_current_and_skill_is_within_budget(self):
        # The cap test. Counting needs the API, so count.py records counts and this holds them
        # to the current text: a stale count fails here exactly like a count over budget.
        self.assertEqual(generate.count_problems(generate.build(), generate.read_counts(generate.COUNTS)), [])

    def test_no_single_line_comment_reaches_the_skill(self):
        # Every directive is a single-line comment; the skill's one real comment spans lines.
        leaked = [l for l in skill_text().splitlines()
                  if l.strip().startswith("<!--") and l.strip().endswith("-->")]
        self.assertEqual(leaked, [])

    def test_generated_notice_closes_the_frontmatter(self):
        lines = skill_text().splitlines(keepends=True)
        self.assertEqual(lines[0], "---\n")
        self.assertEqual(lines[lines.index("---\n", 1) - 1], generate.NOTICE)

    def test_index_lists_every_included_law_in_skeleton_order(self):
        skeleton = (generate.SOURCE / "skeleton.md").read_text()
        included = re.findall(r"^<!-- include: laws/(.+)\.md -->$", skeleton, re.M)
        text = skill_text()
        index = text.split("Laws (cited in code as `[LAW:<token>]`):\n", 1)[1].split("\n\n", 1)[0]
        self.assertEqual(re.findall(r"`([^`]+)`", index), included)
        self.assertTrue(all(len(l) <= generate.INDEX_WIDTH for l in index.splitlines()))

    def test_run_reports_what_it_built(self):
        with SourceTree() as tree:
            code, out, _ = tree.generate()
        self.assertEqual(code, 0)
        self.assertRegex(out, r"wrote nothing in .*: 24 laws, 2 framings, marked paragraphs S=\d+ M=\d+\n$")


class Projections(unittest.TestCase):
    def outputs(self) -> dict[str, str]:
        return {o.path: o.text for o in generate.build().outputs}

    def test_s_is_inside_m_is_inside_l(self):
        out = self.outputs()
        all_l = generate.read_source().render(generate.uniform("L", generate.read_source().laws), "all-L")
        for inner, outer in (("references/rung-s.md", out["references/rung-m.md"]), ("references/rung-m.md", all_l)):
            with self.subTest(inner=inner):
                outside = [p for p in paragraphs(out[inner])[1:] if p not in paragraphs(outer)]
                self.assertEqual(outside, [])

    def test_s_holds_only_the_s_marked_paragraphs(self):
        s = section(self.outputs()["references/rung-s.md"], "no-mode-explosion")
        self.assertIn("**New flags, options, and modes", s)
        self.assertIn("Diagnostic: *who deletes this flag", s)
        self.assertIn("Instance of `[LAW:one-type-per-behavior]`", s)
        self.assertNotIn("The temptation arrives", s)
        self.assertNotIn("mixing board", s)

    def test_m_adds_the_temptation_and_nothing_unmarked(self):
        m = section(self.outputs()["references/rung-m.md"], "no-mode-explosion")
        self.assertIn("The temptation arrives", m)
        self.assertNotIn("mixing board", m)

    def test_references_carry_no_frontmatter(self):
        for path, text in self.outputs().items():
            if path.startswith("references/"):
                with self.subTest(path=path):
                    self.assertTrue(text.startswith("<!-- Generated by plugins/laws/source/generate.py"))
                    self.assertNotIn("\nname: code\n", text)

    def test_one_line_profile_edit_changes_only_that_laws_section(self):
        with SourceTree() as tree:
            before = tree.target.read_text()
            tree.edit("profiles/default.toml", 'no-mode-explosion = "L"', 'no-mode-explosion = "S"')
            after = generate.build(tree.source).outputs[0].text
        self.assertNotEqual(section(before, "no-mode-explosion"), section(after, "no-mode-explosion"))
        self.assertEqual(before.replace(section(before, "no-mode-explosion"), ""),
                         after.replace(section(after, "no-mode-explosion"), ""))


class TokenCap(unittest.TestCase):
    def test_profile_over_budget_fails_and_names_the_overage(self):
        with SourceTree() as tree:
            tokens = json.loads(tree.counts.read_text())["SKILL.md"]["tokens"]
            tree.edit("profiles/default.toml", f"budget = {tokens}", f"budget = {tokens - 40}")
            code, err = tree.check()
        self.assertEqual(code, 1)
        self.assertIn(f"SKILL.md is 40 tokens over the default profile's budget: {tokens} counted", err)

    def test_count_for_other_text_fails(self):
        with SourceTree() as tree:
            tree.edit("profiles/default.toml", 'no-mode-explosion = "L"', 'no-mode-explosion = "S"')
            self.assertEqual(tree.generate()[0], 1)
            code, err = tree.check()
        self.assertEqual(code, 1)
        self.assertIn("SKILL.md: no token count for its current text", err)

    def test_count_on_another_model_fails(self):
        with SourceTree() as tree:
            tree.edit("profiles/default.toml", 'model = "claude-opus-5-5"', 'model = "claude-sonnet-5-5"')
            code, err = tree.check()
        self.assertEqual(code, 1)
        self.assertIn("no token count for its current text on claude-sonnet-5-5", err)


class StalenessCheck(unittest.TestCase):
    def test_unedited_sources_pass(self):
        with SourceTree() as tree:
            self.assertEqual(tree.check(), (0, ""))

    def test_edited_source_without_regenerating_fails(self):
        with SourceTree() as tree:
            tree.edit("laws/one-way-deps.md", "water flows downhill", "water flows uphill")
            code, err = tree.check()
            self.assertEqual(code, 1)
            self.assertIn("SKILL.md is stale", err)

    def test_new_law_enters_the_index(self):
        with SourceTree() as tree:
            (tree.source / "laws" / "zz-new.md").write_text(
                "## [LAW:zz-new] - new\n\n<!-- rung: S -->\n**Stated.**\n\n<!-- rung: S -->\nDiagnostic: *x?*\n"
            )
            tree.edit("skeleton.md", "<!-- include: laws/escape-local-minima.md -->\n",
                      "<!-- include: laws/escape-local-minima.md -->\n\n<!-- include: laws/zz-new.md -->\n")
            tree.edit("profiles/default.toml", 'escape-local-minima = "L"\n', 'escape-local-minima = "L"\nzz-new = "L"\n')
            self.assertIn("`escape-local-minima` · `zz-new`", generate.build(tree.source).outputs[0].text)

    def test_edited_source_is_written_and_reported(self):
        with SourceTree() as tree:
            tree.edit("laws/one-way-deps.md", "water flows downhill", "water flows uphill")
            code, out, err = tree.generate()
            self.assertIn("water flows uphill", tree.target.read_text())
            self.assertIn("water flows uphill", (tree.skill_dir / "references/rung-m.md").read_text())
        self.assertIn("wrote SKILL.md, references/rung-s.md, references/rung-m.md in", out)
        self.assertEqual(code, 1, "a regenerated output's old count no longer holds")
        self.assertIn("run count.py", err)


class Refusals(unittest.TestCase):
    def assertRefused(self, tree: SourceTree, *fragments: str) -> None:
        with self.assertRaises(generate.SourceError) as caught:
            generate.build(tree.source)
        for fragment in fragments:
            self.assertIn(fragment, str(caught.exception))

    def test_law_without_s_marked_diagnostic_is_named(self):
        with SourceTree() as tree:
            tree.edit("laws/one-way-deps.md", "<!-- rung: S -->\nDiagnostic:", "Diagnostic:")
            self.assertRefused(tree, "'one-way-deps'", "Diagnostic")

    def test_law_without_s_marked_statement_is_named(self):
        with SourceTree() as tree:
            tree.edit("laws/single-enforcer.md", "<!-- rung: S -->\n**", "**")
            self.assertRefused(tree, "'single-enforcer'", "statement")

    def test_misspelled_directive_is_refused(self):
        with SourceTree() as tree:
            tree.edit("laws/one-way-deps.md", "<!-- rung: M -->", "<!-- rung:M -->")
            self.assertRefused(tree, "unknown directive")

    def test_directive_with_stray_whitespace_is_refused(self):
        for stray in ("<!-- rung: M --> ", "  <!-- rung: M -->"):
            with self.subTest(stray=stray), SourceTree() as tree:
                tree.edit("laws/one-way-deps.md", "<!-- rung: M -->", stray)
                self.assertRefused(tree, "unknown directive")

    def test_marker_inside_a_paragraph_is_refused(self):
        with SourceTree() as tree:
            tree.edit("laws/one-way-deps.md", "\nare forbidden.**", "\n<!-- rung: S -->\nare forbidden.**")
            self.assertRefused(tree, "inside a paragraph")

    def test_bad_marker_outside_a_law_is_refused(self):
        with SourceTree() as tree:
            tree.edit("recap.md", "\n\n", "\n\n<!-- rung: X -->\n", count=1)
            self.assertRefused(tree, "recap.md:", "rung must be one of")

    def test_nested_law_file_is_refused(self):
        with SourceTree() as tree:
            (tree.source / "laws" / "sub").mkdir()
            (tree.source / "laws" / "one-way-deps.md").rename(tree.source / "laws" / "sub" / "one-way-deps.md")
            tree.edit("skeleton.md", "laws/one-way-deps.md", "laws/sub/one-way-deps.md")
            self.assertRefused(tree, "is nested")

    def test_nested_law_file_left_out_is_refused(self):
        with SourceTree() as tree:
            (tree.source / "laws" / "sub").mkdir()
            (tree.source / "laws" / "sub" / "x.md").write_text("## [LAW:x] - x\n")
            self.assertRefused(tree, "laws/sub/x.md")

    def test_unknown_rung_is_refused(self):
        with SourceTree() as tree:
            tree.edit("laws/one-way-deps.md", "<!-- rung: M -->", "<!-- rung: X -->")
            self.assertRefused(tree, "rung must be one of")

    def test_marker_without_a_paragraph_is_refused(self):
        with SourceTree() as tree:
            tree.edit("laws/one-way-deps.md", "<!-- rung: M -->\n", "<!-- rung: M -->\n\n")
            self.assertRefused(tree, "not followed by a paragraph")

    def test_file_name_must_match_heading(self):
        with SourceTree() as tree:
            tree.edit("laws/one-way-deps.md", "[LAW:one-way-deps]", "[LAW:one-way-dependencies]")
            self.assertRefused(tree, "one-way-dependencies")

    def test_malformed_heading_is_refused(self):
        for heading in ("## [LAW:one-way-deps2] - ", "## [LAW:one-way-deps] — ", "\n## [LAW:one-way-deps] - "):
            with self.subTest(heading=heading), SourceTree() as tree:
                tree.edit("laws/one-way-deps.md", "## [LAW:one-way-deps] - ", heading)
                self.assertRefused(tree, "laws/one-way-deps.md:1")

    def test_statement_marker_moved_off_the_statement_is_refused(self):
        with SourceTree() as tree:
            tree.edit("laws/carrying-cost.md", "<!-- rung: S -->\n**Judge", "**Judge")
            tree.edit("laws/carrying-cost.md", "\n**YAGNI**", "\n<!-- rung: S -->\n**YAGNI**")
            self.assertRefused(tree, "'carrying-cost'", "under the heading")

    def test_law_left_out_of_the_skeleton_is_refused(self):
        with SourceTree() as tree:
            tree.edit("skeleton.md", "<!-- include: laws/one-way-deps.md -->\n", "")
            self.assertRefused(tree, "one-way-deps")

    def test_include_of_a_missing_file_is_refused(self):
        with SourceTree() as tree:
            tree.edit("skeleton.md", "<!-- include: laws/one-way-deps.md -->", "<!-- include: laws/nope.md -->")
            self.assertRefused(tree, "skeleton.md:", "'laws/nope.md' does not exist")

    def test_profile_missing_a_law_is_refused(self):
        with SourceTree() as tree:
            tree.edit("profiles/default.toml", 'one-way-deps = "L"\n', "")
            self.assertRefused(tree, "default.toml", "missing ['one-way-deps']")

    def test_profile_naming_an_unknown_law_is_refused(self):
        with SourceTree() as tree:
            tree.edit("profiles/default.toml", "[rungs]\n", '[rungs]\nno-such-law = "S"\n')
            self.assertRefused(tree, "unknown ['no-such-law']")

    def test_profile_with_an_unknown_rung_is_refused(self):
        with SourceTree() as tree:
            tree.edit("profiles/default.toml", 'one-way-deps = "L"', 'one-way-deps = "XL"')
            self.assertRefused(tree, "'one-way-deps': 'XL'")

    def test_profile_without_a_budget_is_refused(self):
        with SourceTree() as tree:
            tree.edit("profiles/default.toml", "\nbudget = ", "\nbudge = ")
            self.assertRefused(tree, "exactly model, budget and [rungs]")

    def test_include_without_a_file_is_refused(self):
        with SourceTree() as tree:
            tree.edit("skeleton.md", "<!-- include: recap.md -->", "<!-- include -->")
            self.assertRefused(tree, "include names no file")


if __name__ == "__main__":
    unittest.main()
