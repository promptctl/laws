"""Tests for generate.py. Run: python3 -m unittest discover plugins/laws/source"""
from __future__ import annotations

import re
import shutil
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

import generate


class SourceTree:
    """A scratch copy of the sources and the committed skill, safe to edit."""

    def __enter__(self) -> "SourceTree":
        self.dir = Path(tempfile.mkdtemp())
        self.source = self.dir / "code"
        self.target = self.dir / "SKILL.md"
        shutil.copytree(generate.SOURCE, self.source)
        shutil.copy(generate.TARGET, self.target)
        return self

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

    def check(self) -> int:
        with redirect_stderr(StringIO()), redirect_stdout(StringIO()):
            return generate.main(["--check", "--source", str(self.source), "--target", str(self.target)])


class CommittedSkill(unittest.TestCase):
    def test_committed_skill_is_current(self):
        self.assertEqual(
            generate.TARGET.read_text(),
            generate.render().text,
            "plugins/laws/skills/code/SKILL.md is stale: run python3 plugins/laws/source/generate.py",
        )

    def test_no_single_line_comment_reaches_the_skill(self):
        # Every directive is a single-line comment; the skill's one real comment spans lines.
        leaked = [l for l in generate.render().text.splitlines()
                  if l.strip().startswith("<!--") and l.strip().endswith("-->")]
        self.assertEqual(leaked, [])

    def test_generated_notice_closes_the_frontmatter(self):
        lines = generate.render().text.splitlines(keepends=True)
        self.assertEqual(lines[0], "---\n")
        self.assertEqual(lines[lines.index("---\n", 1) - 1], generate.NOTICE)

    def test_index_lists_every_included_law_in_skeleton_order(self):
        skeleton = (generate.SOURCE / "skeleton.md").read_text()
        included = re.findall(r"^<!-- include: laws/(.+)\.md -->$", skeleton, re.M)
        text = generate.render().text
        index = text.split("Laws (cited in code as `[LAW:<token>]`):\n", 1)[1].split("\n\n", 1)[0]
        self.assertEqual(re.findall(r"`([^`]+)`", index), included)
        self.assertTrue(all(len(l) <= generate.INDEX_WIDTH for l in index.splitlines()))

    def test_run_reports_what_it_built(self):
        with SourceTree() as tree, redirect_stdout(StringIO()) as out:
            code = generate.main(["--source", str(tree.source), "--target", str(tree.target)])
        self.assertEqual(code, 0)
        self.assertRegex(out.getvalue(), r"unchanged: 24 laws, 2 framings, marked paragraphs S=\d+ M=\d+\n$")


class StalenessCheck(unittest.TestCase):
    def test_unedited_sources_pass(self):
        with SourceTree() as tree:
            self.assertEqual(tree.check(), 0)

    def test_edited_source_without_regenerating_fails(self):
        with SourceTree() as tree:
            tree.edit("laws/one-way-deps.md", "water flows downhill", "water flows uphill")
            self.assertEqual(tree.check(), 1)

    def test_new_law_enters_the_index(self):
        with SourceTree() as tree:
            (tree.source / "laws" / "zz-new.md").write_text(
                "## [LAW:zz-new] - new\n\n<!-- rung: S -->\n**Stated.**\n\n<!-- rung: S -->\nDiagnostic: *x?*\n"
            )
            tree.edit("skeleton.md", "<!-- include: laws/escape-local-minima.md -->\n",
                      "<!-- include: laws/escape-local-minima.md -->\n\n<!-- include: laws/zz-new.md -->\n")
            self.assertIn("`escape-local-minima` · `zz-new`", generate.render(tree.source).text)

    def test_edited_source_is_written_and_reported(self):
        with SourceTree() as tree, redirect_stdout(StringIO()) as out:
            tree.edit("laws/one-way-deps.md", "water flows downhill", "water flows uphill")
            generate.main(["--source", str(tree.source), "--target", str(tree.target)])
            self.assertIn("water flows uphill", tree.target.read_text())
        self.assertIn(" written: 24 laws", out.getvalue())


class Refusals(unittest.TestCase):
    def assertRefused(self, tree: SourceTree, *fragments: str) -> None:
        with self.assertRaises(generate.SourceError) as caught:
            generate.render(tree.source)
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

    def test_include_without_a_file_is_refused(self):
        with SourceTree() as tree:
            tree.edit("skeleton.md", "<!-- include: recap.md -->", "<!-- include -->")
            self.assertRefused(tree, "include names no file")


if __name__ == "__main__":
    unittest.main()
