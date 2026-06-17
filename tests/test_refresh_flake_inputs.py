import importlib.machinery
import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT_PATH = (
    Path(__file__).resolve().parent.parent / "scripts" / "refresh-flake-inputs"
)


def load_script_module():
    loader = importlib.machinery.SourceFileLoader(
        "refresh_flake_inputs", str(SCRIPT_PATH)
    )
    spec = importlib.util.spec_from_loader("refresh_flake_inputs", loader)
    if spec.loader is None:
        raise RuntimeError("Unable to load refresh-flake-inputs script")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RunRefreshTest(unittest.TestCase):
    def test_loader_error_is_not_skipped_under_optimized_python(self):
        with patch.object(
            importlib.util,
            "spec_from_loader",
            return_value=importlib.machinery.ModuleSpec("refresh_flake_inputs", None),
        ):
            with self.assertRaisesRegex(
                RuntimeError,
                "Unable to load refresh-flake-inputs script",
            ):
                load_script_module()

    def test_runs_multiple_hash_fix_passes_until_build_succeeds(self):
        module = load_script_module()
        build_results = [1, 1, 0]
        diffs = [
            "",
            "rusty-v8 hash diff",
            "rusty-v8 hash diff",
            "rusty-v8 and cargo hash diff",
        ]
        builds = []
        hash_fixes = []
        updates = []

        def fake_build(args, *, cwd, text):
            builds.append((tuple(args), cwd, text))
            return subprocess.CompletedProcess(args, build_results.pop(0))

        def fake_run(*args, cwd, capture_output=False):
            if args == ("git", "diff", "--no-ext-diff", "--full-index"):
                return subprocess.CompletedProcess(args, 0, stdout=diffs.pop(0))
            updates.append((args, cwd, capture_output))
            return subprocess.CompletedProcess(args, 0)

        def fake_hash_fixer(command, *, cwd):
            hash_fixes.append((command, cwd))

        with (
            patch.object(module.subprocess, "run", side_effect=fake_build),
            patch.object(module, "run", side_effect=fake_run),
            patch.object(module, "run_hash_fixer", side_effect=fake_hash_fixer),
        ):
            try:
                module.run_refresh(
                    cwd=Path("/repo"),
                    selected=["codex"],
                    build_target=".#homeConfigurations.coneill.activationPackage",
                    fix_hashes_command="determinate-nixd fix hashes --auto-apply",
                )
            except subprocess.CalledProcessError as exc:
                self.fail(
                    f"run_refresh stopped before all hash fixes were applied: {exc}"
                )

        self.assertEqual(
            [
                (
                    ("nix", "flake", "update", "codex"),
                    Path("/repo"),
                    False,
                )
            ],
            updates,
        )
        self.assertEqual(3, len(builds))
        self.assertEqual(
            [
                ("determinate-nixd fix hashes --auto-apply", Path("/repo")),
                ("determinate-nixd fix hashes --auto-apply", Path("/repo")),
            ],
            hash_fixes,
        )
        self.assertEqual([], build_results)
        self.assertEqual([], diffs)

    def test_stops_when_hash_fixer_makes_no_new_changes(self):
        module = load_script_module()
        build_count = 0
        diff = "existing flake update diff"

        def fake_build(args, *, cwd, text):
            nonlocal build_count
            build_count += 1
            return subprocess.CompletedProcess(args, 1)

        def fake_run(*args, cwd, capture_output=False):
            if args == ("git", "diff", "--no-ext-diff", "--full-index"):
                return subprocess.CompletedProcess(args, 0, stdout=diff)
            return subprocess.CompletedProcess(args, 0)

        with (
            patch.object(module.subprocess, "run", side_effect=fake_build),
            patch.object(module, "run", side_effect=fake_run),
            patch.object(module, "run_hash_fixer", return_value=None),
        ):
            with self.assertRaisesRegex(
                SystemExit,
                "Build still fails and hash fixer made no changes",
            ):
                module.run_refresh(
                    cwd=Path("/repo"),
                    selected=["codex"],
                    build_target=".#homeConfigurations.coneill.activationPackage",
                    fix_hashes_command="determinate-nixd fix hashes --auto-apply",
                )

        self.assertEqual(1, build_count)


if __name__ == "__main__":
    unittest.main()
