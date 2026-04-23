#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("suite_positional", nargs="?", help="Suite name")
    parser.add_argument("--suite", dest="suites", action="append", default=[])
    parser.add_argument("--case", dest="cases", action="append", default=[])
    return parser.parse_args()


def normalize_suites(args: argparse.Namespace) -> list[str]:
    suites = list(args.suites)
    if args.suite_positional:
        suites.append(args.suite_positional)
    return suites


def is_windows_platform() -> bool:
    return os.name == "nt" or sys.platform.startswith("win")


def selected_suite_dirs(root: Path) -> list[Path]:
    suites_root = root / "tests" / "suites"
    if is_windows_platform():
        return [suites_root / "shared", suites_root / "windows"]
    return [suites_root / "shared", suites_root / "unix"]


def discover_suite_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for suite_dir in selected_suite_dirs(root):
        if suite_dir.is_dir():
            files.extend(sorted(suite_dir.glob("*.vader")))
    return files


def suite_glob_target(root: Path) -> str:
    globs: list[str] = []
    for suite_dir in selected_suite_dirs(root):
        if suite_dir.is_dir():
            globs.append((suite_dir / "*.vader").as_posix())
    return " ".join(globs)


def resolve_suite_file(root: Path, suite: str) -> Path | None:
    suite_path = Path(suite)
    candidates: list[Path] = []

    if suite_path.suffix == ".vader":
        candidates.append(suite_path)
    else:
        candidates.append(Path(f"{suite}.vader"))

    for candidate in candidates:
        if candidate.is_absolute() and candidate.is_file():
            return candidate
        for suite_dir in selected_suite_dirs(root):
            path = suite_dir / candidate
            if path.is_file():
                return path
    return None


def is_header(line: str) -> bool:
    prefixes = ("Before", "After", "Given", "Execute", "Do", "Then", "Expect", "Include")
    for prefix in prefixes:
        if line.startswith(prefix):
            rest = line[len(prefix):]
            if rest.startswith(":") or rest.startswith(";") or rest.startswith("(") or rest.startswith(" "):
                return line.rstrip().endswith(":") or line.rstrip().endswith(";")
    return False


def header_kind(line: str) -> str:
    line = line.rstrip()
    if line.endswith(":") or line.endswith(";"):
        line = line[:-1]
    for stop in (" ", "("):
        idx = line.find(stop)
        if idx >= 0:
            line = line[:idx]
            break
    return line


def filter_vader_case(src: Path, dst: Path, case_patterns: list[str]) -> None:
    keep_current = False
    current_kind = ""
    global_kinds = {"Before", "After", "Given", "Include"}

    with src.open("r", encoding="utf-8") as fh:
        lines = fh.readlines()

    out: list[str] = []
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


def build_runner_vim(path: Path, root_dir: Path, vader_dir: Path, mode: str, target: str) -> None:
    script = f"""execute 'set runtimepath^=' .. fnameescape('{root_dir.as_posix()}')
execute 'set runtimepath^=' .. fnameescape('{vader_dir.as_posix()}')
filetype off
runtime plugin/vader.vim
let s:mode = '{mode}'
let s:target = '{target}'
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

    root_dir = Path(__file__).resolve().parent.parent
    tests_dir = root_dir / "tests"
    vader_dir = root_dir / ".deps" / "vader.vim"
    debug = os.environ.get("DEBUG", "")
    vim_bin = os.environ.get("VIM_BIN", "vim")
    vim_exe = shutil.which(vim_bin)

    if not vader_dir.is_dir():
        print(f"vader.vim not found: {vader_dir}", file=sys.stderr)
        return 1

    if vim_exe is None:
        print(f"vim executable not found: {vim_bin}", file=sys.stderr)
        return 1

    available_suites = discover_suite_files(root_dir)

    for suite in suites:
        suite_file = resolve_suite_file(root_dir, suite)
        if suite_file is None:
            print(f"suite not found: {suite}", file=sys.stderr)
            return 1

    tmpdir_obj = tempfile.TemporaryDirectory(prefix="vim-src-tests-")
    tmpdir = Path(tmpdir_obj.name)

    try:
        mode = "glob"
        target = suite_glob_target(root_dir)
        selected_targets = list(available_suites)
        list_path = tmpdir / "suites.txt"

        if suites:
            if len(suites) == 1 and not args.cases:
                mode = "file"
                target = resolve_suite_file(root_dir, suites[0]).as_posix()  # type: ignore[union-attr]
            else:
                mode = "list"
                target = list_path.as_posix()
                target_suites: list[Path] = []
                for suite in suites:
                    src = resolve_suite_file(root_dir, suite)
                    assert src is not None
                    if args.cases:
                        filtered = tmpdir / f"{suite}.vader"
                        filter_vader_case(src, filtered, args.cases)
                        target_suites.append(filtered)
                    else:
                        target_suites.append(src)
                selected_targets = target_suites
        elif args.cases:
            mode = "list"
            target = list_path.as_posix()
            selected: list[Path] = []
            for src in available_suites:
                filtered = tmpdir / src.name
                filter_vader_case(src, filtered, args.cases)
                if filtered.read_text(encoding="utf-8").strip():
                    selected.append(filtered)
            selected_targets = selected

        if mode == "list":
            list_path.write_text(
                "\n".join(path.as_posix() for path in selected_targets)
                + ("\n" if selected_targets else ""),
                encoding="utf-8",
            )

        runner_vim = tmpdir / "run.vim"
        build_runner_vim(runner_vim, root_dir, vader_dir, mode, target)

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

        proc = subprocess.run(
            [vim_exe, "-Nu", "NONE", "-n", "-i", "NONE", "-es", "-S", str(runner_vim)],
            cwd=root_dir,
            stdin=subprocess.DEVNULL,
        )

        if debug:
            print(f"EXIT_CODE={proc.returncode}")
            print(f"TMP_DIR={tmpdir}")

        return proc.returncode
    finally:
        if debug:
            tmpdir_obj.cleanup = lambda: None  # type: ignore[attr-defined]
        else:
            tmpdir_obj.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
