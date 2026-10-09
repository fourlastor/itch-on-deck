#!/usr/bin/env python3
"""Opt-in live test of an exported app and real butler, in a fresh temp folder.

Reads one credential from --source-db without modifying that database. Signs
into a NEW database containing no installed games, installs the timer through
a systemctl stand-in, and updates only a scratch copy of --app from itch.io.
No timer is enabled and no real installation/configuration is changed.
"""
import argparse
import atexit
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile


class Daemon:
    def __init__(self, butler, db, env):
        self.proc = subprocess.Popen([str(butler), "--json", "--dbpath", str(db), "daemon", "--transport", "stdio", "--destiny-pid", str(os.getpid())], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=env)
        self.id = 0

    def request(self, method, params=None):
        self.id += 1
        self.proc.stdin.write(json.dumps(dict(jsonrpc="2.0", id=self.id, method=method, params=params or {})) + "\n")
        self.proc.stdin.flush()
        for line in self.proc.stdout:
            msg = json.loads(line)
            if msg.get("id") == self.id and "method" not in msg:
                if "error" in msg: raise RuntimeError(f"{method} failed (code {msg['error'].get('code')})")
                return msg["result"]
        raise RuntimeError("The real butler daemon stopped")

    def close(self):
        self.proc.terminate()
        self.proc.wait(timeout=10)
        self.proc.stdin.close()
        self.proc.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--butler", required=True, type=Path)
    parser.add_argument("--source-db", required=True, type=Path)
    parser.add_argument("--patch-from-build", type=int, help="Also install this older published build into a second scratch folder and patch it through the native helper")
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix="itch-self-update-live-"))
    print(f"Isolated live test: {root}", flush=True)
    install, data, config, cache, bin_dir = [root / name for name in ("install", "data", "config", "cache", "bin")]
    for path in (install, data, config, cache, bin_dir): path.mkdir()
    # Test reports remain useful, but the temporary database need not retain
    # a copy of the account's API credential after this process finishes.
    atexit.register(shutil.rmtree, data / "db", ignore_errors=True)
    app = install / args.app.name
    shutil.copy2(args.app, app)
    (data / "butler").mkdir()
    (data / "butler/15.31.0").symlink_to(args.butler.resolve().parent, target_is_directory=True)
    fake_systemctl = bin_dir / "systemctl"
    fake_systemctl.write_text("#!/bin/sh\nexit 0\n")
    fake_systemctl.chmod(0o755)
    env = dict(os.environ, ITCH_ON_DECK_DATA=str(data), ITCH_ON_DECK_CONFIG=str(config), XDG_DATA_HOME=str(root / "xdg-data"), XDG_CONFIG_HOME=str(root / "xdg-config"), XDG_CACHE_HOME=str(cache), PATH=str(bin_dir) + ":" + os.environ["PATH"])
    env.pop("ITCH_ON_DECK_DEBUG", None)
    source = sqlite3.connect(args.source_db.resolve().as_uri() + "?mode=ro", uri=True)
    row = source.execute("SELECT api_key FROM profiles WHERE api_key <> '' LIMIT 1").fetchone()
    source.close()
    if not row: raise RuntimeError("No saved API credential available")
    (data / "db").mkdir()
    daemon = Daemon(args.butler.resolve(), data / "db/butler.db", env)
    try:
        profile = daemon.request("Profile.LoginWithAPIKey", dict(apiKey=row[0]))["profile"]
        uploads = daemon.request("Fetch.GameUploads", dict(gameId=5100889, compatible=False, fresh=True))["uploads"]
        upload = next(u for u in uploads if "linux" in u.get("platforms", {}) and u.get("build"))
        target = upload["build"]["userVersion"]
    finally:
        daemon.close()
    print(f"Fresh test database signed in; target build: {target}", flush=True)
    (config / "config.json").write_text(json.dumps(dict(profile_id=profile["id"], schedule="off", self_update=True)))
    old_cache = cache / "itch-on-deck/update-run"
    old_cache.mkdir(parents=True)
    (old_cache / "old-app").write_bytes(b"previous launcher cache")
    # Write the actual packaged launcher/helper; systemctl is isolated above.
    setup = subprocess.run([str(app), "--headless", "--audio-driver", "Dummy", "--", "schedule", "off"], env=env, capture_output=True, text=True, timeout=20)
    (root / "schedule.log").write_text(setup.stdout + setup.stderr)
    if setup.returncode: raise RuntimeError("Packaged timer setup failed; see schedule.log")
    helper = data / "update-helper"
    assert helper.is_file() and os.access(helper, os.X_OK), "Embedded helper was not extracted"
    assert not old_cache.exists(), "Old full executable cache was not removed"
    print(f"Packaged helper installed: {helper.stat().st_size} bytes; old cache removed", flush=True)
    before = hashlib.sha256(app.read_bytes()).hexdigest()
    # A separate window marker proves headless startup/exit does not delete it.
    marker = data / "window.pid"
    marker.write_text(str(os.getpid()))
    blocked = subprocess.run([str(data / "update-run"), str(app)], env=env, capture_output=True, text=True, timeout=180)
    (root / "open-window.log").write_text(blocked.stdout + blocked.stderr)
    assert blocked.returncode == 0, "Open-window run failed"
    assert marker.read_text() == str(os.getpid()), "Headless run removed another window's marker"
    assert hashlib.sha256(app.read_bytes()).hexdigest() == before, "Open app was changed"
    skipped = json.loads((data / "state.json").read_text())["runs"][0]
    assert skipped["skipped"][0]["reason"] == "the app was open", skipped
    marker.unlink()
    print("Real exported run preserved the open window and skipped self-update", flush=True)
    result = subprocess.run([str(data / "update-run"), str(app)], env=env, capture_output=True, text=True, timeout=180)
    (root / "update.log").write_text(result.stdout + result.stderr)
    assert result.returncode == 0, "Real self-update failed; see update.log"
    assert "text file busy" not in result.stderr.lower(), "ETXTBSY during self-update"
    record = json.loads((data / "state.json").read_text())["runs"][0]
    assert record["outcome"] == "updated" and not record["errors"], record
    assert record["updated"][0]["version"] == target, record
    assert hashlib.sha256(app.read_bytes()).hexdigest() != before, "The executable was not replaced"
    assert (install / ".itch/receipt.json.gz").is_file(), "Butler receipt is missing"
    assert not (data / "update.lock").exists(), "Update lock was left behind"
    assert not old_cache.exists(), "Launcher recreated the full executable copy"
    assert not (cache / "itch-on-deck/self-update").exists(), "Staging was not cleaned"
    # The resulting published executable itself must still load.
    check = subprocess.run([str(app), "--headless", "--audio-driver", "Dummy", "--", "check"], env=env, capture_output=True, text=True, timeout=20)
    (root / "updated-check.log").write_text(check.stdout + check.stderr)
    assert check.returncode == 0 and "0 failed" in check.stdout, "The updated executable does not load"
    report = dict(result="passed", target=target, helper_bytes=helper.stat().st_size, record=record, scratch=str(root))
    if args.patch_from_build:
        patch_install, patch_stage, driver = [root / name for name in ("patch-install", "patch-stage", "driver")]
        patch_install.mkdir(); driver.mkdir()
        game = dict(id=5100889, url="https://fourlastor.itch.io/itch-on-deck", title="itch on Deck", classification="tool", type="default")
        base = dict(noCave=True, installFolder=str(patch_install), stagingFolder=str(patch_stage), game=game, upload=upload, profileId=profile["id"])
        daemon = Daemon(args.butler.resolve(), data / "db/butler.db", env)
        try:
            older = dict(id=args.patch_from_build, userVersion=f"build {args.patch_from_build}")
            queued = daemon.request("Install.Queue", dict(base, build=older))
            daemon.request("Install.Perform", dict(id=queued["id"], stagingFolder=str(patch_stage)))
            queued = daemon.request("Install.Queue", dict(base, build=upload["build"]))
        finally:
            daemon.close()
        print(f"Real older build {args.patch_from_build} installed; patch queued for helper", flush=True)
        # The packaged Godot->helper handoff was tested above. This driver
        # lets the SAME helper apply an actual patch to an unmodified older
        # published executable, without having to publish a test release.
        sys.path.insert(0, str(Path(__file__).parent / "tests"))
        from test_update_helper import APP_SOURCE
        source = driver / "app.rs"
        source.write_text(APP_SOURCE)
        driver_app = driver / "app"
        subprocess.run(["rustc", "-o", str(driver_app), str(source)], check=True)
        patch_record = dict(at=int(__import__('time').time()), outcome="nothing", updated=[], skipped=[], left=[], errors=[])
        job = dict(id=queued["id"], stagingFolder=str(patch_stage), installFolder=str(patch_install), title="itch on Deck", version=target, butler=str(args.butler.resolve()), db=str(data / "db/butler.db"), bandwidth=0, record=patch_record)
        template = driver / "job.json"
        template.write_text(json.dumps(job))
        patch_env = dict(env, TEST_JOB=str(template), TEST_APP_PID=str(driver / "app.pid"), TEST_OWNER=str(driver / "owner.pid"), TEST_APP_CODE="0")
        patched = subprocess.run([str(helper), str(driver_app)], env=patch_env, capture_output=True, text=True, timeout=180)
        (root / "patch.log").write_text(patched.stdout + patched.stderr)
        assert patched.returncode == 0, "Real patch failed; see patch.log"
        patch_record = json.loads((data / "state.json").read_text())["runs"][0]
        assert patch_record["outcome"] == "updated", patch_record
        assert "patch" in patch_record["updated"][0]["how"], "Update did not use real delta patches"
        patch_app = patch_install / app.name
        assert hashlib.sha256(patch_app.read_bytes()).hexdigest() == hashlib.sha256(app.read_bytes()).hexdigest(), "Patched executable differs from the full published build"
        assert not patch_stage.exists(), "Patch staging was not cleaned"
        assert not (data / "update.lock").exists(), "Patch lock was left behind"
        report["patch_record"] = patch_record
    (root / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    main()
