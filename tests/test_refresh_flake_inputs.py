import contextlib
import importlib.machinery
import importlib.util
import io
import json
import subprocess
import tempfile
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
            if args == ("nix", "eval", "--json", ".#lib.refreshableFixedOutputs"):
                return subprocess.CompletedProcess(args, 0, stdout="[]")
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
                    selected=["nixpkgs"],
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
                    ("nix", "flake", "update", "nixpkgs"),
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
            if args == ("nix", "eval", "--json", ".#lib.refreshableFixedOutputs"):
                return subprocess.CompletedProcess(args, 0, stdout="[]")
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
                    selected=["nixpkgs"],
                    build_target=".#homeConfigurations.coneill.activationPackage",
                    fix_hashes_command="determinate-nixd fix hashes --auto-apply",
                )

        self.assertEqual(1, build_count)

    def test_refreshes_declared_fixed_outputs_before_build(self):
        module = load_script_module()
        manifest = [
            {
                "input": "codex",
                "file": "flake.nix",
                "attrPath": ["rustyV8Archives", "aarch64-darwin", "hash"],
                "url": "https://example.test/aarch64-darwin.tar.gz",
                "hashType": "sha256",
            },
            {
                "input": "codex",
                "file": "flake.nix",
                "attrPath": ["rustyV8Archives", "aarch64-linux", "hash"],
                "url": "https://example.test/aarch64-linux.tar.gz",
                "hashType": "sha256",
            },
            {
                "input": "codex",
                "file": "flake.nix",
                "attrPath": ["rustyV8Archives", "x86_64-linux", "hash"],
                "url": "https://example.test/x86_64-linux.tar.gz",
                "hashType": "sha256",
            },
            {
                "input": "nixpkgs",
                "file": "flake.nix",
                "attrPath": ["ignoredArchives", "x86_64-linux", "hash"],
                "url": "https://example.test/ignored.tar.gz",
                "hashType": "sha256",
            },
        ]
        prefetch_hashes = {
            "https://example.test/aarch64-darwin.tar.gz": "sha256-new-darwin",
            "https://example.test/aarch64-linux.tar.gz": "sha256-new-arm",
            "https://example.test/x86_64-linux.tar.gz": "sha256-new-x86",
        }
        flake_nix = """{
  outputs = { self, nixpkgs }:
    let
      rustyV8Archives = {
        aarch64-darwin = {
          platform = "aarch64-apple-darwin";
          hash = "sha256-old-darwin";
        };
        aarch64-linux = {
          platform = "aarch64-unknown-linux-gnu";
          hash = "sha256-old-arm";
        };
        x86_64-linux = {
          platform = "x86_64-unknown-linux-gnu";
          hash = "sha256-old-x86";
        };
      };
      ignoredArchives = {
        x86_64-linux = {
          hash = "sha256-old-ignored";
        };
      };
    in {};
}
"""

        with tempfile.TemporaryDirectory() as tempdir:
            repo = Path(tempdir)
            (repo / "flake.nix").write_text(flake_nix)
            events = []

            def fake_build(args, *, cwd, text):
                events.append(("build", tuple(args)))
                return subprocess.CompletedProcess(args, 0)

            def fake_run(*args, cwd, capture_output=False):
                events.append(("run", args))
                if args == ("nix", "flake", "update", "codex"):
                    return subprocess.CompletedProcess(args, 0)
                if args == ("nix", "eval", "--json", ".#lib.refreshableFixedOutputs"):
                    return subprocess.CompletedProcess(
                        args,
                        0,
                        stdout=json.dumps(manifest),
                    )
                if args[:6] == (
                    "nix",
                    "store",
                    "prefetch-file",
                    "--json",
                    "--hash-type",
                    "sha256",
                ):
                    return subprocess.CompletedProcess(
                        args,
                        0,
                        stdout=json.dumps({"hash": prefetch_hashes[args[6]]}),
                    )
                self.fail(f"unexpected command: {args}")

            with (
                patch.object(module.subprocess, "run", side_effect=fake_build),
                patch.object(module, "run", side_effect=fake_run),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                module.run_refresh(
                    cwd=repo,
                    selected=["codex"],
                    build_target=".#homeConfigurations.coneill.activationPackage",
                    fix_hashes_command="determinate-nixd fix hashes --auto-apply",
                )

            updated_flake = (repo / "flake.nix").read_text()
            self.assertIn('hash = "sha256-new-darwin";', updated_flake)
            self.assertIn('hash = "sha256-new-arm";', updated_flake)
            self.assertIn('hash = "sha256-new-x86";', updated_flake)
            self.assertIn('hash = "sha256-old-ignored";', updated_flake)
            build_index = next(
                index for index, event in enumerate(events) if event[0] == "build"
            )
            prefetch_indexes = [
                index
                for index, event in enumerate(events)
                if event[0] == "run"
                and event[1][:3] == ("nix", "store", "prefetch-file")
            ]
            self.assertTrue(prefetch_indexes)
            self.assertLess(max(prefetch_indexes), build_index)


class FlakeCodexPackagingTest(unittest.TestCase):
    def test_codex_refresh_manifest_tracks_release_packages(self):
        result = subprocess.run(
            ["nix", "eval", "--json", ".#lib.refreshableFixedOutputs"],
            cwd=SCRIPT_PATH.parent.parent,
            check=True,
            text=True,
            capture_output=True,
        )
        records = json.loads(result.stdout)
        codex_records = [record for record in records if record.get("input") == "codex"]

        self.assertEqual(3, len(codex_records))
        for record in codex_records:
            self.assertEqual("flake.nix", record["file"])
            self.assertEqual("sha256", record["hashType"])
            self.assertEqual("codexReleasePackages", record["attrPath"][0])
            self.assertEqual("hash", record["attrPath"][-1])
            self.assertIn(
                "/codex-package-",
                record["url"],
            )
            self.assertTrue(record["url"].endswith(".tar.gz"))


if __name__ == "__main__":
    unittest.main()
