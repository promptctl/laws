"""Tests for generate.py. Run: python3 -m unittest discover plugins/laws/source"""
from __future__ import annotations

import re
import shutil
import tempfile
import unittest
from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path

import generate

DIRECTIVE_TEXT = re.compile(r"<!-- (include|rung|law-index|framing-index|generated-notice)\b")


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

    def edit(self, relative: str, old: str, new: str) -> None:
        path = self.source / relative
        text = path.read_text()
        found = text.count(old)
        if found != 1:
            raise AssertionError(f"{relative}: expected one {old!r}, found {found}")
        path.write_text(text.replace(old, new))

    def check(self) -> int:
        with redirect_stderr(StringIO()):
            return generate.main(["--check", "--source", str(self.source), "--target", str(self.target)])


class CommittedSkill(unittest.TestCase):
    def test_committed_skill_is_current(self):
        self.assertEqual(
            generate.TARGET.read_text(),
            generate.render(),
            "plugins/laws/skills/code/SKILL.md is stale: run python3 plugins/laws/source/generate.py",
        )

    def test_no_directive_text_reaches_the_skill(self):
        leaked = [l for l in generate.render().splitlines() if DIRECTIVE_TEXT.search(l)]
        self.assertEqual(leaked, [])

    def test_generated_notice_follows_the_frontmatter(self):
        lines = generate.render().splitlines(keepends=True)
        self.assertEqual(lines[0], "---\n")
        self.assertEqual(lines[lines.index("---\n", 1) + 1], generate.NOTICE)

    def test_index_lists_every_law_heading_in_document_order(self):
        text = generate.render()
        headings = re.findall(r"^## \[LAW:([a-z-]+)\]", text, re.M)
        index = text.split("Laws (cited in code as `[LAW:<token>]`):\n", 1)[1].split("\n\n", 1)[0]
        self.assertEqual(re.findall(r"`([a-z-]+)`", index), headings)
        self.assertTrue(all(len(l) <= generate.INDEX_WIDTH for l in index.splitlines()))


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
            self.assertIn("`escape-local-minima` · `zz-new`", generate.render(tree.source))


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


if __name__ == "__main__":
    unittest.main()
