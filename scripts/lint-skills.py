#!/usr/bin/env python3
"""lint-skills.py — L2 skill-doc linter for the plugin monorepo.

A no-LLM structural linter that asserts invariants across plugins/** and root
docs, and freezes 2026-06-01 cross-plugin audit findings as permanent rules.
Each rule reports a `file:line` location. See evals/README.md for the rule
catalog, severity policy, and how to add a rule.

Severity:
  ERROR  — high-confidence structural violation; fails the gate (exit 1).
  WARN   — fuzzy/heuristic signal; reported but does not fail (exit 0),
           until proven low-false-positive and promoted to ERROR.

Usage:
  python3 scripts/lint-skills.py            # report; fail only on ERROR
  python3 scripts/lint-skills.py --strict   # fail on WARN too

Exit codes:
  0  — no ERROR findings (WARN allowed unless --strict)
  1  — at least one ERROR (or any WARN under --strict)
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

ERROR = "ERROR"
WARN = "WARN"


@dataclass(frozen=True)
class Finding:
    severity: str
    path: str
    line: int
    rule: str
    message: str


# --- file discovery -------------------------------------------------------

def plugin_markdown_files() -> list[Path]:
    return sorted(REPO_ROOT.joinpath("plugins").rglob("*.md"))


def skill_files() -> list[Path]:
    return sorted(REPO_ROOT.joinpath("plugins").rglob("SKILL.md"))


def rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8").splitlines()


FENCE_RE = re.compile(r"^\s*(```|~~~)")


def prose_lines(path: Path):
    """Yield (lineno, line) for lines outside fenced code blocks."""
    in_fence = False
    for n, line in enumerate(read_lines(path), 1):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if not in_fence:
            yield n, line


def strip_fences(text: str) -> str:
    out, in_fence = [], False
    for line in text.splitlines():
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if not in_fence:
            out.append(line)
    return "\n".join(out)


BACKTICK_FLAG_RE = re.compile(r"`(--[a-z][a-z0-9-]+)`")


def documented_flags(path: Path) -> set[str]:
    """A skill's own flags: backtick-wrapped `--flag` tokens in prose (not in
    shell snippets, where `--json`/`--cached` are CLI noise, not the interface)."""
    return set(BACKTICK_FLAG_RE.findall(strip_fences(path.read_text(encoding="utf-8"))))


# --- Rule: frontmatter present -------------------------------------------

def rule_frontmatter(findings: list[Finding]) -> None:
    for skill in skill_files():
        lines = read_lines(skill)
        if not lines or lines[0].strip() != "---":
            findings.append(Finding(ERROR, rel(skill), 1, "frontmatter",
                                    "SKILL.md must open with a YAML frontmatter block (`---`)"))
            continue
        end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
        if end is None:
            findings.append(Finding(ERROR, rel(skill), 1, "frontmatter",
                                    "frontmatter block is not closed with `---`"))
            continue
        block = "\n".join(lines[1:end])
        for key in ("name", "description"):
            if not re.search(rf"^{key}:\s*\S", block, re.MULTILINE):
                findings.append(Finding(ERROR, rel(skill), 1, "frontmatter",
                                        f"frontmatter is missing required `{key}:` field"))


# --- Rule: include directives resolve ------------------------------------

INCLUDE_RE = re.compile(r"<!--\s*include:\s*(\S+?)\s*-->")


def rule_includes(findings: list[Finding]) -> None:
    for md in plugin_markdown_files():
        for n, line in prose_lines(md):
            for m in INCLUDE_RE.finditer(line):
                target = m.group(1)
                candidates = [REPO_ROOT / target, md.parent / target]
                if not any(c.exists() for c in candidates):
                    findings.append(Finding(ERROR, rel(md), n, "include",
                                            f"include directive target not found: {target}"))


# --- Rule: relative markdown links + _shared citations resolve -----------

LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
SHARED_CITE_RE = re.compile(r"plugins/_shared/[A-Za-z0-9._/-]+\.md")
SKIP_LINK_PREFIXES = ("http://", "https://", "mailto:", "#", "tel:")


def _resolve_link(md: Path, target: str) -> Path | None:
    target = target.strip()
    if not target or target.startswith(SKIP_LINK_PREFIXES) or target.startswith("<"):
        return None
    target = target.split()[0]            # drop optional "title"
    target = target.split("#", 1)[0]      # drop anchor
    target = target.split("?", 1)[0]
    if not target:
        return None                       # pure in-doc anchor
    if target.startswith("/"):
        return REPO_ROOT / target.lstrip("/")
    return (md.parent / target)


def rule_links(findings: list[Finding]) -> None:
    targets = plugin_markdown_files() + [REPO_ROOT / "README.md"]
    for md in targets:
        if not md.exists():
            continue
        for n, line in prose_lines(md):
            for m in LINK_RE.finditer(line):
                resolved = _resolve_link(md, m.group(1))
                if resolved is not None and not resolved.exists():
                    findings.append(Finding(ERROR, rel(md), n, "link",
                                            f"relative link target not found: {m.group(1)}"))
            for m in SHARED_CITE_RE.finditer(line):
                cite = m.group(0)
                if not (REPO_ROOT / cite).exists():
                    findings.append(Finding(ERROR, rel(md), n, "shared-citation",
                                            f"_shared citation path not found: {cite}"))


# --- Rule: stale develop branch references -------------------------------
# Many `develop` mentions are legitimate: the v3→v4 migration surfaces, v3
# legacy-detection guards, and negative references ("there is no develop").
# Flag only references that look like a live branch target and are not covered
# by the migration/legacy allowlist, a negative-context phrasing, or an inline
# `lint-allow-develop` marker.

DEVELOP_FILE_ALLOWLIST = {
    "plugins/flowkit/MIGRATION-v4.md",
    "plugins/flowkit/README.md",
    "plugins/flowkit/skills/migrate-v4/SKILL.md",
    "plugins/flowkit/skills/ship/SKILL.md",
    "plugins/flowkit/skills/pr/SKILL.md",
    "plugins/sessionkit/README.md",
    "plugins/sessionkit/skills/roadmap/SKILL.md",
    "plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md",
}

DEVELOP_BRANCHREF_RE = re.compile(
    r"`develop`"
    r"|\bdevelop/"
    r"|/develop\b"
    r"|--base\s+develop"
    r"|\borigin\s+develop\b"
    r"|\bdevelop\s+main\b"
    r"|\bdevelop\|"
    r"|^\s*-\s*develop\s*$"
)
DEVELOP_NEGATIVE_RE = re.compile(
    r"\b(no|not|never|without|reintroduce)\b[^.]*develop"
    r"|develop[^.]*\b(intermediary|split|probe)\b"
    r"|develop\|main",  # branch-protection alternation, e.g. grep -E '^(develop|main'
    re.IGNORECASE,
)


def _develop_scan_files() -> list[Path]:
    files = plugin_markdown_files() + [REPO_ROOT / "README.md"]
    wf = REPO_ROOT / ".github" / "workflows"
    if wf.exists():
        files += sorted(wf.glob("*.yml")) + sorted(wf.glob("*.yaml"))
    return [f for f in files if f.exists()]


def rule_develop(findings: list[Finding]) -> None:
    for f in _develop_scan_files():
        relpath = rel(f)
        if relpath in DEVELOP_FILE_ALLOWLIST:
            continue
        scan = prose_lines(f) if f.suffix == ".md" else enumerate(read_lines(f), 1)
        for n, line in scan:
            if "lint-allow-develop" in line:
                continue
            if not DEVELOP_BRANCHREF_RE.search(line):
                continue
            if DEVELOP_NEGATIVE_RE.search(line):
                continue
            findings.append(Finding(ERROR, relpath, n, "develop",
                                    "stale `develop` branch reference (single-trunk repo "
                                    "targets `main`); allowlist legitimate uses in the linter "
                                    "or add a `lint-allow-develop` marker"))


# --- Rule: settings.json allowlist script paths exist --------------------

ALLOWLIST_PATH_RE = re.compile(r"(plugins/[A-Za-z0-9._/-]+\.sh)")


def rule_settings_allowlist(findings: list[Finding]) -> None:
    settings = REPO_ROOT / ".claude" / "settings.json"
    if not settings.exists():
        return
    data = json.loads(settings.read_text(encoding="utf-8"))
    allow = data.get("permissions", {}).get("allow", [])
    lines = read_lines(settings)
    for entry in allow:
        for m in ALLOWLIST_PATH_RE.finditer(entry):
            script = m.group(1)
            if not (REPO_ROOT / script).exists():
                line_no = next((i + 1 for i, ln in enumerate(lines) if entry[:40] in ln), 1)
                findings.append(Finding(ERROR, ".claude/settings.json", line_no,
                                        "allowlist",
                                        f"allowlist entry references a non-existent script: {script}"))


# --- Rule (WARN): argument section present where flags are used ----------

ARG_HEADING_RE = re.compile(r"^#{2,3}\s+.*\b(Input|Arguments?|Flags?|Usage|Options?)\b", re.IGNORECASE)


def rule_input_present(findings: list[Finding]) -> None:
    for skill in skill_files():
        flags = documented_flags(skill)
        if not flags:
            continue
        if any(ARG_HEADING_RE.match(ln) for ln in read_lines(skill)):
            continue
        findings.append(Finding(WARN, rel(skill), 1, "input-table",
                                f"documents flags ({', '.join(sorted(flags)[:4])}) but has no "
                                "Input/Arguments/Flags section"))


# --- Rule (WARN): README flag drift --------------------------------------

def rule_flag_matrix(findings: list[Finding]) -> None:
    for plugin_dir in sorted(REPO_ROOT.joinpath("plugins").iterdir()):
        readme = plugin_dir / "README.md"
        if not readme.exists():
            continue
        readme_text = readme.read_text(encoding="utf-8")
        for skill in sorted(plugin_dir.rglob("SKILL.md")):
            skill_flags = documented_flags(skill)
            missing = sorted(f for f in skill_flags if f not in readme_text)
            if missing:
                findings.append(Finding(WARN, rel(skill), 1, "flag-matrix",
                                        f"flags not mentioned in {rel(readme)}: {', '.join(missing[:6])}"))


# --- Rule (WARN): shared specs cited, not paraphrased --------------------

PR_BODY_MARKERS = ("## Summary", "## Changes", "## Test plan")


def rule_paraphrase(findings: list[Finding]) -> None:
    for md in plugin_markdown_files():
        relpath = rel(md)
        if relpath.endswith("_shared/pr-body.md"):
            continue
        text = md.read_text(encoding="utf-8")
        if all(marker in text for marker in PR_BODY_MARKERS) and "pr-body.md" not in text:
            findings.append(Finding(WARN, relpath, 1, "paraphrase",
                                    "inlines the PR-body section shape without citing "
                                    "plugins/_shared/pr-body.md"))


RULES = (
    rule_frontmatter,
    rule_includes,
    rule_links,
    rule_develop,
    rule_settings_allowlist,
    rule_input_present,
    rule_flag_matrix,
    rule_paraphrase,
)


def main(argv: list[str]) -> int:
    strict = "--strict" in argv
    findings: list[Finding] = []
    for rule in RULES:
        rule(findings)

    findings.sort(key=lambda f: (f.severity != ERROR, f.path, f.line, f.rule))
    errors = [f for f in findings if f.severity == ERROR]
    warns = [f for f in findings if f.severity == WARN]

    for f in findings:
        print(f"{f.severity}: {f.path}:{f.line} [{f.rule}] {f.message}")

    print()
    print(f"lint-skills: {len(errors)} error(s), {len(warns)} warning(s)")

    if errors or (strict and warns):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
