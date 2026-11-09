import calendar
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import secrets
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from typing import ClassVar
from unittest.mock import patch

SCRIPT_PATH = Path(__file__).resolve().parent.parent / "scripts" / "op-secret"


def load_script_module():
    loader = importlib.machinery.SourceFileLoader("op_secret", str(SCRIPT_PATH))
    spec = importlib.util.spec_from_loader("op_secret", loader)
    if spec.loader is None:
        raise RuntimeError("Unable to load op-secret script")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


op_secret = load_script_module()

# Stands in for the 1Password CLI: resolves {{ op://... }} from FAKE_OP_VALUES,
# fails like a denied prompt when FAKE_OP_FAIL is set, and logs its argv and
# process session to FAKE_OP_LOG.
FAKE_OP = r"""#!/usr/bin/env python3
import json, os, re, sys
with open(os.environ["FAKE_OP_LOG"], "a") as f:
    f.write(json.dumps({"argv": sys.argv[1:], "sid": os.getsid(0)}) + "\n")
if os.environ.get("FAKE_OP_FAIL"):
    sys.stderr.write("[ERROR] 2026/11/09 14:00:00 authorization denied\n")
    sys.exit(1)
values = json.loads(os.environ["FAKE_OP_VALUES"])
def resolve(m):
    if m.group(1) not in values:
        sys.stderr.write(f"[ERROR] could not find item {m.group(1)}\n")
        sys.exit(1)
    return values[m.group(1)]
sys.stdout.write(re.sub(r"\{\{ (op://[^}]+?) \}\}", resolve, sys.stdin.read()))
"""


class ParsePsLineTest(unittest.TestCase):
    def test_parses_padded_day_and_command_with_spaces(self):
        line = "70541     1 Mon Nov  9 13:46:29 2026     /Users/x/Application Support/claude --x"
        pid, ppid, start, command = op_secret.parse_ps_line(line)
        self.assertEqual((pid, ppid), (70541, 1))
        self.assertEqual(command, "/Users/x/Application Support/claude --x")
        self.assertEqual(
            start,
            calendar.timegm(
                time.strptime("Mon Nov 9 13:46:29 2026", "%a %b %d %H:%M:%S %Y")
            ),
        )

    def test_rejects_garbage(self):
        self.assertIsNone(op_secret.parse_ps_line("not a ps line"))


class IsDescendantTest(unittest.TestCase):
    # pid: (ppid, start, command)
    TABLE: ClassVar[dict] = {
        1: (0, 0, "launchd"),
        50: (1, 100, "claude"),
        60: (50, 200, "bash"),
        70: (60, 300, "op-secret"),
        80: (1, 150, "node mcp"),
    }

    def test_direct_and_indirect_children(self):
        self.assertTrue(op_secret.is_descendant(self.TABLE, 70, 50, 100))
        self.assertTrue(op_secret.is_descendant(self.TABLE, 50, 50, 100))

    def test_unrelated_process(self):
        self.assertFalse(op_secret.is_descendant(self.TABLE, 80, 50, 100))

    def test_wrong_start_time_means_reused_pid(self):
        self.assertFalse(op_secret.is_descendant(self.TABLE, 70, 50, 99))

    def test_parent_newer_than_child_is_rejected(self):
        table = dict(self.TABLE)
        table[60] = (50, 400, "bash")  # started after its "child" 70
        self.assertFalse(op_secret.is_descendant(table, 70, 50, 100))

    def test_unknown_pid(self):
        self.assertFalse(op_secret.is_descendant(self.TABLE, 999, 50, 100))


class ValidationTest(unittest.TestCase):
    def test_trailing_newline_is_rejected(self):
        with self.assertRaises(op_secret.Error):
            op_secret.check_name("FELIX\n")
        with self.assertRaises(op_secret.Error):
            op_secret.check_ref("op://v/item/field\n")

    def test_pid_one_is_refused(self):
        with self.assertRaises(op_secret.Error):
            op_secret.cmd_serve(["--session", "s", "--claude-pid", "1"])
        env = {"CLAUDE_CODE_SESSION_ID": "s", "CLAUDE_PID": "1"}
        with patch.dict(os.environ, env), self.assertRaises(op_secret.Error):
            op_secret.session_identity()

    def test_accepts_normal_assignments(self):
        refs = op_secret.parse_assignments(
            [
                "FELIX=op://infra/felix/api-server-key",
                "NOTION=op://Private/Notion/API Token",
            ]
        )
        self.assertEqual(refs["NOTION"], "op://Private/Notion/API Token")

    def test_rejects_dangerous_names(self):
        for name in (
            "PATH",
            "DYLD_INSERT_LIBRARIES",
            "OP_SERVICE_ACCOUNT_TOKEN",
            "CLAUDE_PID",
            "PYTHONPATH",
        ):
            with self.assertRaises(op_secret.Error, msg=name):
                op_secret.parse_assignments([f"{name}=op://a/b/c"])

    def test_rejects_bad_refs(self):
        for ref in ("https://x", "op://a/b/c}}", "op://a/b\n/c", ""):
            with self.assertRaises(op_secret.Error, msg=ref):
                op_secret.parse_assignments([f"X={ref}"])

    def test_rejects_missing_equals(self):
        with self.assertRaises(op_secret.Error):
            op_secret.parse_assignments(["X"])


class InjectTemplateTest(unittest.TestCase):
    def test_round_trip_with_multiline_value(self):
        refs = ["op://a/b/c", "op://d/e/f"]
        delim = secrets.token_hex(16)
        template = op_secret.build_template(refs, delim)
        # Simulate op inject substituting each {{ ref }}.
        output = template.replace("{{ op://a/b/c }}", "line1\nline2").replace(
            "{{ op://d/e/f }}", "plain-value"
        )
        values = op_secret.parse_injected(output + "\n", refs, delim)
        self.assertEqual(
            values, {"op://a/b/c": "line1\nline2", "op://d/e/f": "plain-value"}
        )

    def test_rejects_unexpected_output(self):
        with self.assertRaises(op_secret.Error):
            op_secret.parse_injected("garbage", ["op://a/b/c"], "x" * 32)


class MaskerTest(unittest.TestCase):
    def feed_all(self, masker, chunks):
        return b"".join(masker.feed(c) for c in chunks) + masker.finish()

    def test_overlapping_repeats_keep_buffer_small(self):
        m = op_secret.Masker([b"aaaaaaaa"])
        out = b""
        for _ in range(4):
            out += m.feed(b"a" * 4096)
            self.assertLess(len(m.buf), 8)
        self.assertEqual(out + m.finish(), b"<concealed>")

    def test_held_part_of_concealed_secret_never_prints(self):
        m = op_secret.Masker([b"abcabcab"])
        # The trailing "abcab" could start another overlapping copy; when the
        # output ends instead, it was already concealed and must not appear.
        self.assertEqual(
            self.feed_all(m, [b"x abcabcab", b"cab", b" y"]), b"x <concealed> y"
        )
        m = op_secret.Masker([b"abcabcab"])
        self.assertEqual(self.feed_all(m, [b"x abcabcab"]), b"x <concealed>")

    def test_masks_whole_value(self):
        m = op_secret.Masker([b"hunter2-secret"])
        self.assertEqual(
            self.feed_all(m, [b"pw=hunter2-secret ok\n"]), b"pw=<concealed> ok\n"
        )

    def test_masks_value_split_across_reads(self):
        m = op_secret.Masker([b"hunter2-secret"])
        self.assertEqual(
            self.feed_all(m, [b"pw=hunt", b"er2-sec", b"ret\n"]), b"pw=<concealed>\n"
        )

    def test_short_line_is_not_held_back(self):
        m = op_secret.Masker([b"hunter2-secret"])
        self.assertEqual(m.feed(b"still working...\n"), b"still working...\n")

    def test_holds_only_a_possible_prefix(self):
        m = op_secret.Masker([b"hunter2-secret"])
        self.assertEqual(m.feed(b"abc hunt"), b"abc ")
        self.assertEqual(m.finish(), b"hunt")

    def test_multiple_secrets_longest_first(self):
        m = op_secret.Masker([b"abcdefgh", b"abcdefghijkl"])
        self.assertEqual(
            self.feed_all(m, [b"x abcdefghijkl y abcdefgh\n"]),
            b"x <concealed> y <concealed>\n",
        )

    def test_full_secret_that_starts_a_longer_one_waits(self):
        m = op_secret.Masker([b"abcdefgh", b"abcdefgh-private-token"])
        self.assertEqual(
            self.feed_all(m, [b"x abcdefgh", b"-private-token\n"]), b"x <concealed>\n"
        )

    def test_secret_ending_in_the_start_of_another(self):
        m = op_secret.Masker([b"abcdefgh", b"fghijklm"])
        self.assertEqual(self.feed_all(m, [b"abcdefgh", b" ok\n"]), b"<concealed> ok\n")

    def test_overlapping_secrets_are_both_hidden(self):
        m = op_secret.Masker([b"abcdefgh", b"fghijklm"])
        self.assertEqual(self.feed_all(m, [b"abcdefghijklm\n"]), b"<concealed>\n")

    def test_overlap_completed_by_a_later_read(self):
        m = op_secret.Masker([b"abcdefgh", b"fghijklm"])
        self.assertEqual(self.feed_all(m, [b"abcdefgh", b"ijklm\n"]), b"<concealed>\n")

    def test_overlap_that_never_completes(self):
        m = op_secret.Masker([b"abcdefgh", b"fghijklm"])
        self.assertEqual(
            self.feed_all(m, [b"abcdefghij", b" done\n"]), b"<concealed>ij done\n"
        )


class FakeOpTest(unittest.TestCase):
    """The real op_inject path against a fake `op`, so no Touch ID."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        op = Path(self.tmp.name) / "op"
        op.write_text(FAKE_OP)
        op.chmod(0o755)
        self.log = Path(self.tmp.name) / "op.log"
        self.env = {
            "HOME": os.path.expanduser("~"),
            "PATH": f"{self.tmp.name}:{os.environ['PATH']}",
            "FAKE_OP_LOG": str(self.log),
            "FAKE_OP_VALUES": json.dumps(
                {"op://a/b/c": "line1\nline2-value", "op://d/e/f": "plain-value-1"}
            ),
        }
        patcher = patch.object(op_secret, "clean_env", lambda: dict(self.env))
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.tmp.cleanup)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_resolves_batch_in_one_call_and_a_new_session(self):
        values = op_secret.op_inject(["op://a/b/c", "op://d/e/f"])
        self.assertEqual(
            values, {"op://a/b/c": "line1\nline2-value", "op://d/e/f": "plain-value-1"}
        )
        calls = self.calls()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["argv"], ["inject"])
        # Each call runs in its own process session so 1Password can't reuse
        # an earlier approval for a different item.
        self.assertNotEqual(calls[0]["sid"], os.getsid(0))

    def test_denial_passes_1password_message_through(self):
        self.env["FAKE_OP_FAIL"] = "1"
        with self.assertRaisesRegex(op_secret.Error, "authorization denied"):
            op_secret.op_inject(["op://a/b/c"])

    def test_unknown_item(self):
        with self.assertRaisesRegex(op_secret.Error, "could not find item op://x/y/z"):
            op_secret.op_inject(["op://x/y/z"])

    def test_carriage_returns_are_kept(self):
        self.env["FAKE_OP_VALUES"] = json.dumps({"op://a/b/c": "pass\r\nword-1"})
        self.assertEqual(
            op_secret.op_inject(["op://a/b/c"]), {"op://a/b/c": "pass\r\nword-1"}
        )

    def test_helper_end_to_end(self):
        helper = op_secret.Helper(f"test-{secrets.token_hex(4)}", os.getpid())
        self.assertTrue(helper.start())
        self.addCleanup(lambda: Path(helper.paths["log"]).unlink(missing_ok=True))
        self.addCleanup(helper.cleanup)

        def handle_one():
            with helper.server.accept()[0] as conn:
                helper.handle(conn)

        thread = threading.Thread(target=handle_one)
        thread.start()
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(helper.paths["sock"])
            request = {"op": "get", "token": helper.token, "refs": {"X": "op://d/e/f"}}
            s.sendall(json.dumps(request).encode() + b"\n")
            reply = json.loads(s.makefile().readline())
        thread.join()
        self.assertEqual(reply["values"], {"X": "plain-value-1"})


class HelperTest(unittest.TestCase):
    """Runs a helper inside the test process (as its own 'Claude process'),
    with a fake 1Password fetch."""

    def setUp(self):
        self.calls = []
        self.values = {
            "op://v/item/field": "s3cret-value-123",
            "op://v/item/short": "abc",
        }
        self.fail_with = None
        self.session = f"test-{secrets.token_hex(4)}"
        self.helper = op_secret.Helper(self.session, os.getpid(), fetch=self.fake_fetch)
        self.assertTrue(self.helper.start())

    def tearDown(self):
        self.helper.cleanup()
        try:
            os.unlink(self.helper.paths["log"])
        except FileNotFoundError:
            pass

    def fake_fetch(self, refs):
        self.calls.append(list(refs))
        if isinstance(self.fail_with, Exception):
            raise self.fail_with
        if self.fail_with:
            raise op_secret.Error(self.fail_with)
        return {ref: self.values[ref] for ref in refs}

    def serve(self, count=1):
        def loop():
            handled = 0
            deadline = time.monotonic() + 30
            while handled < count and time.monotonic() < deadline:
                try:
                    conn, _ = self.helper.server.accept()
                except TimeoutError:
                    continue
                with conn:
                    self.helper.handle(conn)
                handled += 1

        thread = threading.Thread(target=loop)
        thread.start()
        return thread

    def raw(self, payload, token=None):
        thread = self.serve()
        payload = dict(payload, token=self.helper.token if token is None else token)
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(self.helper.paths["sock"])
            s.sendall(json.dumps(payload).encode() + b"\n")
            data = b""
            while not data.endswith(b"\n"):
                chunk = s.recv(65536)
                if not chunk:
                    break
                data += chunk
        thread.join()
        return json.loads(data)

    def client(self, *args, input=None):
        env = dict(
            os.environ, CLAUDE_CODE_SESSION_ID=self.session, CLAUDE_PID=str(os.getpid())
        )
        # Without a listening test helper, the client would start a real one
        # that calls the real `op` (a Touch ID prompt mid-test). Fail instead.
        self.assertTrue(
            os.path.exists(self.helper.paths["sock"]), "test helper is not listening"
        )
        thread = self.serve()
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), *args],
            check=False,
            env=env,
            capture_output=True,
            text=True,
            input=input,
            timeout=60,
        )
        thread.join()
        return result

    def test_get_caches_after_first_fetch(self):
        get = {"op": "get", "refs": {"X": "op://v/item/field"}}
        self.assertEqual(self.raw(get)["values"], {"X": "s3cret-value-123"})
        self.assertEqual(self.raw(get)["values"], {"X": "s3cret-value-123"})
        self.assertEqual(self.calls, [["op://v/item/field"]])

    def test_refresh_files_keeps_tmp_cleaner_away(self):
        old = time.time() - 5 * 24 * 3600
        for kind in ("token", "lock", "log"):
            os.utime(self.helper.paths[kind], (old, old))
        self.helper.last_touch -= op_secret.TOUCH_INTERVAL
        # One idle poll: accept times out, then Claude is reported gone.
        idle = patch.object(self.helper, "server")
        gone = patch.object(self.helper, "claude_alive", return_value=False)
        with idle as server, gone:
            server.accept.side_effect = TimeoutError
            self.helper.serve_forever()
        for kind in ("token", "lock", "log"):
            st = os.stat(self.helper.paths[kind])
            self.assertGreater(st.st_mtime, time.time() - 60, kind)
            self.assertGreater(st.st_atime, time.time() - 60, kind)

    def test_wrong_token_is_refused(self):
        reply = self.raw(
            {"op": "get", "refs": {"X": "op://v/item/field"}}, token="nope"
        )
        self.assertFalse(reply["ok"])
        self.assertIn("token", reply["error"])
        self.assertEqual(self.calls, [])

    def test_failure_is_remembered_without_reprompting(self):
        self.fail_with = "1Password: authorization denied"
        get = {"op": "get", "refs": {"X": "op://v/item/field"}}
        self.assertIn("denied", self.raw(get)["error"])
        self.assertIn("ask the user", self.raw(get)["error"])
        self.assertEqual(len(self.calls), 1)

    def test_unexpected_failure_is_remembered_without_its_message(self):
        self.fail_with = UnicodeDecodeError("utf-8", b"\xffsecret", 0, 1, "bad")
        get = {"op": "get", "refs": {"X": "op://v/item/field"}}
        error = self.raw(get)["error"]
        self.assertIn("UnicodeDecodeError", error)
        self.assertNotIn("secret", error)
        self.assertIn("ask the user", self.raw(get)["error"])
        self.assertEqual(len(self.calls), 1)

    def test_short_value_is_refused(self):
        reply = self.raw({"op": "get", "refs": {"S": "op://v/item/short"}})
        self.assertFalse(reply["ok"])
        self.assertIn("shorter than", reply["error"])

    def test_forget_drops_cached_value(self):
        get = {"op": "get", "refs": {"X": "op://v/item/field"}}
        self.raw(get)
        self.assertTrue(
            self.raw({"op": "forget", "ref": "op://v/item/field"})["forgotten"]
        )
        self.raw(get)
        self.assertEqual(len(self.calls), 2)

    def test_check_hash_and_compare(self):
        refs = {"X": "op://v/item/field"}
        checks = self.raw({"op": "check", "refs": refs})["checks"]["X"]
        self.assertEqual(checks["length"], 16)
        self.assertEqual(len(checks["scrypt"]), 32)
        self.assertNotIn("s3cret", json.dumps(checks))
        same = self.raw({"op": "check", "refs": refs, "compare": "s3cret-value-123"})
        other = self.raw({"op": "check", "refs": refs, "compare": "different-value"})
        self.assertTrue(same["checks"]["X"]["matches"])
        self.assertFalse(other["checks"]["X"]["matches"])

    def test_run_masks_output_and_passes_env_and_exit_code(self):
        result = self.client(
            "run",
            "X=op://v/item/field",
            "--",
            "sh",
            "-c",
            'echo "got:$X"; [ "$X" = s3cret-value-123 ] && echo env-ok; echo "err:$X" >&2; exit 3',
        )
        self.assertEqual(result.returncode, 3)
        self.assertIn("got:<concealed>", result.stdout)
        self.assertIn("env-ok", result.stdout)
        self.assertIn("err:<concealed>", result.stderr)
        self.assertNotIn("s3cret", result.stdout + result.stderr)

    def test_check_stdin_from_client(self):
        result = self.client(
            "check", "--stdin", "X=op://v/item/field", input="s3cret-value-123\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("X: matches", result.stdout)

    def test_second_helper_for_same_session_loses_the_lock(self):
        other = op_secret.Helper(self.session, os.getpid(), fetch=self.fake_fetch)
        self.assertFalse(other.acquire_lock())

    def test_losing_helper_leaves_the_winners_files(self):
        signals = (signal.SIGTERM, signal.SIGHUP, signal.SIGINT)
        handlers = {s: signal.getsignal(s) for s in signals}
        try:
            rc = op_secret.cmd_serve(
                ["--session", self.session, "--claude-pid", str(os.getpid())]
            )
        finally:
            for s, h in handlers.items():
                signal.signal(s, h)
        self.assertEqual(rc, 0)
        for kind in ("sock", "token", "lock"):
            self.assertTrue(os.path.exists(self.helper.paths[kind]), kind)

    def test_run_ends_when_the_reader_goes_away(self):
        env = dict(
            os.environ, CLAUDE_CODE_SESSION_ID=self.session, CLAUDE_PID=str(os.getpid())
        )
        self.assertTrue(os.path.exists(self.helper.paths["sock"]))
        thread = self.serve()
        proc = subprocess.Popen(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "run",
                "X=op://v/item/field",
                "--",
                "yes",
            ],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            self.assertEqual(len(proc.stdout.read(10)), 10)
            proc.stdout.close()  # like `| head -c 10`
            proc.wait(timeout=20)
            stderr = proc.stderr.read().decode()
        finally:
            proc.kill()
            proc.stderr.close()
        thread.join()
        self.assertEqual(proc.returncode, 128 + signal.SIGPIPE)
        self.assertNotIn("Traceback", stderr)

    def test_run_does_not_wait_for_a_background_grandchild(self):
        start = time.monotonic()
        result = self.client(
            "run", "X=op://v/item/field", "--", "sh", "-c", "sleep 8 & echo started"
        )
        self.assertLess(time.monotonic() - start, 6)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("started", result.stdout)


class HelperProcessTest(unittest.TestCase):
    def test_other_process_tree_is_refused_and_helper_notices_exit(self):
        claude = subprocess.Popen(["sleep", "60"])
        helper = op_secret.Helper(
            f"test-{secrets.token_hex(4)}", claude.pid, fetch=lambda refs: {}
        )
        try:
            self.assertTrue(helper.start())

            def handle_one():
                with helper.server.accept()[0] as conn:
                    helper.handle(conn)

            thread = threading.Thread(target=handle_one)
            thread.start()
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(helper.paths["sock"])
                s.sendall(b"{}\n")
                reply = json.loads(s.makefile().readline())
            thread.join()
            self.assertIn("not part of this Claude session", reply["error"])
            self.assertTrue(helper.claude_alive())
            claude.kill()
            claude.wait()
            self.assertFalse(helper.claude_alive())
        finally:
            claude.kill()
            helper.cleanup()
            os.unlink(helper.paths["log"])

    def test_lock_is_released_when_holder_is_killed(self):
        with tempfile.TemporaryDirectory() as tmp:
            lock = os.path.join(tmp, "x.lock")
            holder = subprocess.Popen(
                [
                    sys.executable,
                    "-c",
                    (
                        "import fcntl,os,sys,time\n"
                        f"fd=os.open({lock!r},os.O_RDWR|os.O_CREAT)\n"
                        "fcntl.flock(fd,fcntl.LOCK_EX)\nprint('locked',flush=True)\ntime.sleep(60)"
                    ),
                ],
                stdout=subprocess.PIPE,
                text=True,
            )
            self.assertEqual(holder.stdout.readline().strip(), "locked")
            os.kill(holder.pid, signal.SIGKILL)
            holder.wait()
            holder.stdout.close()
            fd = os.open(lock, os.O_RDWR)
            import fcntl

            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)  # raises if still held
            os.close(fd)


class ReviewFixesTest(unittest.TestCase):
    def test_process_table_has_no_arguments(self):
        proc = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(20)", "secret-marker-xyz"]
        )
        try:
            time.sleep(0.2)
            program = op_secret.process_table()[proc.pid][2]
        finally:
            proc.kill()
            proc.wait()
        self.assertNotIn("secret-marker-xyz", program)
        self.assertIn("python", program)

    def test_list_never_deletes_files(self):
        session = f"test-{secrets.token_hex(4)}"
        paths = op_secret.helper_paths(session, 99999)
        Path(paths["log"]).write_text(json.dumps({"event": "start"}) + "\n")
        Path(paths["lock"]).write_text("")  # No helper PID: looks stopped.
        try:
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(op_secret.cmd_list([]), 0)
            self.assertIn(f"session {session}", out.getvalue())
            self.assertIn("stopped", out.getvalue())
            self.assertTrue(os.path.exists(paths["log"]))
            self.assertTrue(os.path.exists(paths["lock"]))
        finally:
            for kind in ("log", "lock"):
                os.unlink(paths[kind])

    def test_list_forgets_secrets_of_an_earlier_helper(self):
        session = f"test-{secrets.token_hex(4)}"
        log = Path(op_secret.helper_paths(session, 99999)["log"])
        events = [
            {"event": "start"},
            {"event": "fetched", "refs": ["op://a/old/x"]},
            {"event": "start"},
            {"event": "fetched", "refs": ["op://a/new/y"]},
        ]
        log.write_text("".join(json.dumps(e) + "\n" for e in events))
        try:
            entry = next(h for h in op_secret.helpers() if h["session"] == session)
        finally:
            log.unlink()
        self.assertEqual(entry["held"], ["op://a/new/y"])

    def test_runs_directly_through_its_shebang(self):
        result = subprocess.run(
            [str(SCRIPT_PATH)], check=False, capture_output=True, text=True, timeout=30
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("Usage", result.stderr)

    def test_works_without_user_or_a_terminal(self):
        env = {"PATH": os.environ["PATH"], "HOME": os.path.expanduser("~")}
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "stop", "--session", "no-such-session"],
            check=False,
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            start_new_session=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no matching helper", result.stdout)

    def test_helper_is_recognized_whatever_the_terminal_width(self):
        long_path = "/" + "a" * 110 + "/op-secret"
        proc = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(20)", long_path, "serve"]
        )
        try:
            time.sleep(0.2)
            with patch.dict(os.environ, {"COLUMNS": "40"}):
                self.assertTrue(op_secret.is_our_helper(proc.pid))
        finally:
            proc.kill()
            proc.wait()


if __name__ == "__main__":
    unittest.main()
