#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List, Optional, Tuple


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("suite_positionals", nargs="*", metavar="SUITE", help="Suite name or path")
    parser.add_argument("--suite", dest="suites", action="append", default=[])
    parser.add_argument("--case", dest="cases", action="append", default=[])
    parser.add_argument("--list-suites", action="store_true")
    parser.add_argument("--list-cases", metavar="SUITE")
    return parser.parse_args()


def normalize_suites(args: argparse.Namespace) -> List[str]:
    """Return selected suites: $SUITE first, then --suite and positionals."""
    env_suite = os.environ.get("SUITE", "")
    return ([env_suite] if env_suite else []) + args.suites + args.suite_positionals


def normalize_cases(args: argparse.Namespace) -> List[str]:
    """Return case patterns: $CASE first, then --case."""
    env_case = os.environ.get("CASE", "")
    return ([env_case] if env_case else []) + args.cases


def is_windows_platform() -> bool:
    return os.name == "nt" or sys.platform.startswith("win")


def selected_suite_dirs(root: Path) -> List[Path]:
    suites_root = root / "tests" / "suites"
    if is_windows_platform():
        return [suites_root / "shared", suites_root / "windows"]
    return [suites_root / "shared", suites_root / "unix"]


def discover_suite_files(root: Path) -> List[Path]:
    files: List[Path] = []
    for suite_dir in selected_suite_dirs(root):
        if suite_dir.is_dir():
            files.extend(sorted(suite_dir.glob("*.vader")))
    return files


def validate_unique_suites(files: List[Path]) -> Optional[str]:
    seen = set()
    for suite in files:
        if suite.stem in seen:
            return suite.stem
        seen.add(suite.stem)
    return None


def resolve_suite_file(root: Path, suite: str) -> Optional[Path]:
    suite_path = Path(suite)
    candidates: List[Path] = []

    if suite_path.suffix == ".vader":
        candidates.append(suite_path)
    else:
        candidates.append(Path(f"{suite}.vader"))

    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
        for suite_dir in selected_suite_dirs(root):
            path = suite_dir / candidate
            if path.is_file():
                return path
    return None


def is_header(line: str) -> bool:
    if parse_include(line) is not None:
        return True
    prefixes = ("Before", "After", "Given", "Execute", "Do", "Then", "Expect", "Include")
    for prefix in prefixes:
        if line.startswith(prefix):
            rest = line[len(prefix):]
            if rest.startswith(":") or rest.startswith(";") or rest.startswith("(") or rest.startswith(" "):
                return line.rstrip().endswith(":") or line.rstrip().endswith(";")
    return False


def header_kind(line: str) -> str:
    if parse_include(line) is not None:
        return "Include"
    line = line.rstrip()
    if line.endswith(":") or line.endswith(";"):
        line = line[:-1]
    for stop in (" ", "("):
        idx = line.find(stop)
        if idx >= 0:
            line = line[:idx]
            break
    return line


def parse_include(line: str) -> Optional[Tuple[str, str]]:
    match = re.match(r"^(Include(?:\s*\([^)]*\))?)\s*:\s*(.*?)\s*$", line)
    if match is None or not match.group(2):
        return None
    return match.group(1), match.group(2)


def prepare_case_suite(src: Path, dst: Path) -> Optional[str]:
    output = []
    for line in src.read_text(encoding="utf-8").splitlines(keepends=True):
        include = parse_include(line.rstrip("\r\n"))
        if include is None:
            output.append(line)
            continue

        include_prefix, include_spec = include
        include_file = Path(include_spec)
        if not include_file.is_absolute():
            include_file = src.parent / include_file
        if not include_file.is_file():
            return f"cannot inspect Vader Include during case filtering: {include_spec}"
        text = include_file.read_text(encoding="utf-8")
        if any(parse_include(included_line) is not None for included_line in text.splitlines()):
            return f"nested Vader Include is not supported during case filtering: {include_spec}"
        if any(
            is_header(line) and header_kind(line) in {"Execute", "Do"}
            for line in text.splitlines()
        ):
            return f"included Vader file contains test cases: {include_spec}"
        output.append(f"{include_prefix}: {include_file.resolve().as_posix()}\n")

    dst.write_text("".join(output), encoding="utf-8")
    return None


def filter_vader_case(src: Path, dst: Path, case_patterns: List[str]) -> int:
    keep_current = False
    current_kind = ""
    global_kinds = {"Before", "After", "Given", "Include"}

    with src.open("r", encoding="utf-8") as fh:
        lines = fh.readlines()

    out: List[str] = []
    matched_cases = 0
    for line in lines:
        if is_header(line):
            kind = header_kind(line)
            if kind in global_kinds:
                keep_current = True
                current_kind = "global"
                out.append(line)
                continue

            if kind in {"Execute", "Do"}:
                keep_current = not case_patterns or any(pattern in line for pattern in case_patterns)
                current_kind = "case"
                if keep_current:
                    matched_cases += 1
                    out.append(line)
                continue

            if kind in {"Then", "Expect"}:
                if current_kind == "case" and keep_current:
                    out.append(line)
                else:
                    keep_current = False
                current_kind = "case-tail"
                continue

        if keep_current:
            out.append(line)

    dst.write_text("".join(out), encoding="utf-8")
    return matched_cases


def build_runner_vim(path: Path) -> None:
    script = """execute 'set runtimepath^=' .. fnameescape($ROOT_DIR)
execute 'set runtimepath^=' .. fnameescape($VADER_DIR)
filetype off
runtime plugin/vader.vim
let s:mode = $RUN_MODE
let s:target = $RUN_TARGET
if s:mode ==# 'glob'
  execute 'Vader! ' .. s:target
elseif s:mode ==# 'file'
  execute 'Vader! ' .. fnameescape(s:target)
elseif s:mode ==# 'list'
  let s:suites = readfile(s:target)
  if empty(s:suites)
    cquit 1
  endif
  execute 'Vader! ' .. join(map(copy(s:suites), 'fnameescape(v:val)'), ' ')
else
  cquit 2
endif
"""
    path.write_text(script, encoding="utf-8")


def main() -> int:
    args = parse_args()
    suites = normalize_suites(args)
    cases = normalize_cases(args)

    root_dir = Path(__file__).resolve().parent.parent
    vader_dir = Path(os.environ.get("VADER_DIR", root_dir / ".deps" / "vader.vim"))
    debug = os.environ.get("DEBUG", "0") == "1"
    keep_tmp = os.environ.get("KEEP_TMP", "0") == "1"
    vim_bin = os.environ.get("VIM_BIN", "vim")
    vim_exe = shutil.which(vim_bin)
    available_suites = discover_suite_files(root_dir)
    duplicate_suite = validate_unique_suites(available_suites)
    if duplicate_suite is not None:
        print(f"duplicate suite name: {duplicate_suite}", file=sys.stderr)
        return 1
    if any(case == "" for case in cases):
        print("case pattern must not be empty", file=sys.stderr)
        return 2

    if args.list_suites:
        if suites or cases or args.list_cases:
            print("--list-suites cannot be combined with suite/case selection", file=sys.stderr)
            return 2
        for suite in available_suites:
            print(suite.stem)
        return 0

    if args.list_cases:
        if suites or cases:
            print("--list-cases cannot be combined with suite/case selection", file=sys.stderr)
            return 2
        suite_file = resolve_suite_file(root_dir, args.list_cases)
        if suite_file is None:
            print(f"suite not found: {args.list_cases}", file=sys.stderr)
            return 1
        with suite_file.open(encoding="utf-8") as fh:
            for line in fh:
                if is_header(line) and header_kind(line) in {"Execute", "Do"}:
                    print(line.rstrip())
        return 0

    if not vader_dir.is_dir():
        print(f"vader.vim not found: {vader_dir}", file=sys.stderr)
        return 1

    if vim_exe is None:
        print(f"vim executable not found: {vim_bin}", file=sys.stderr)
        return 1

    for suite in suites:
        suite_file = resolve_suite_file(root_dir, suite)
        if suite_file is None:
            print(f"suite not found: {suite}", file=sys.stderr)
            return 1

    tmpdir = Path(tempfile.mkdtemp(prefix="vim-src-tests-"))

    try:
        if not suites and not cases:
            mode = "glob"
            target = "tests/suites/shared/*.vader " + (
                "tests/suites/windows/*.vader" if is_windows_platform() else "tests/suites/unix/*.vader"
            )
        else:
            sources = [resolve_suite_file(root_dir, suite) for suite in suites] or available_suites
            selected: List[Path] = []
            for index, src in enumerate(sources):
                assert src is not None
                if not cases:
                    selected.append(src)
                    continue
                prepared = tmpdir / f"{index:03d}-prepared-{src.name}"
                include_error = prepare_case_suite(src, prepared)
                if include_error is not None:
                    print(include_error, file=sys.stderr)
                    return 1
                filtered = tmpdir / f"{index:03d}-{src.name}"
                if filter_vader_case(prepared, filtered, cases):
                    selected.append(filtered)

            if not selected:
                print("no test case matched the requested pattern(s)", file=sys.stderr)
                return 1

            if len(selected) == 1:
                mode = "file"
                target = selected[0].as_posix()
            else:
                mode = "list"
                list_path = tmpdir / "suites.txt"
                list_path.write_text("".join(f"{path.as_posix()}\n" for path in selected), encoding="utf-8")
                target = list_path.as_posix()

        runner_vim = tmpdir / "run.vim"
        build_runner_vim(runner_vim)

        if debug:
            print(f"ROOT_DIR={root_dir}")
            print(f"VADER_DIR={vader_dir}")
            print(f"VIM_BIN={vim_bin}")
            print(f"VIM_EXE={vim_exe}")
            print(f"RUN_MODE={mode}")
            print(f"RUN_TARGET={target}")
            print(f"RUNNER_VIM={runner_vim}")
            print("----- run.vim -----")
            print(runner_vim.read_text(encoding="utf-8"), end="")
            print("-------------------")
            print(f"TMP_DIR={tmpdir}")

        run_env = os.environ.copy()
        run_env.update(
            ROOT_DIR=str(root_dir),
            VADER_DIR=str(vader_dir),
            RUN_MODE=mode,
            RUN_TARGET=target,
        )

        proc = subprocess.run(
            [vim_exe, "-Nu", "NONE", "-n", "-i", "NONE", "-es", "-S", str(runner_vim)],
            cwd=root_dir,
            stdin=subprocess.DEVNULL,
            env=run_env,
        )

        if debug:
            print(f"EXIT_CODE={proc.returncode}")

        return proc.returncode
    finally:
        if not keep_tmp:
            shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
