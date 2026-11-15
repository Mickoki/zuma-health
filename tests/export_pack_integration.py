"""Check that dynamically loaded game scenes are included in a Godot export pack.

Usage: python tests/export_pack_integration.py GODOT_CONSOLE_EXE
Uses disposable fixture scenes, never the user's game data.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
GODOT = str(Path(sys.argv[1]).resolve())
WORKSPACE = (ROOT / ".godot").resolve()


def run_godot(*args, cwd):
    result = subprocess.run([GODOT, "--headless", *map(str, args)], cwd=cwd,
                            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90)
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    if result.returncode or "SCRIPT ERROR" in result.stdout + result.stderr or "ERROR:" in result.stdout + result.stderr:
        raise RuntimeError("Godot command failed")
    return result.stdout + result.stderr


with tempfile.TemporaryDirectory(prefix="zuma-pack-test-", dir=WORKSPACE) as directory:
    temporary = Path(directory).resolve()
    if temporary.parent != WORKSPACE or not temporary.name.startswith("zuma-pack-test-"):
        raise RuntimeError("Temporary project is outside the intended workspace")
    project = temporary / "project"
    project.mkdir()
    for name in ("project.godot", "export_presets.cfg"):
        shutil.copy2(ROOT / name, project / name)
    shutil.copytree(ROOT / "scripts", project / "scripts")
    shutil.copytree(ROOT / "scenes", project / "scenes")
    for folder in ("addons",):
        shutil.copytree(ROOT / folder, project / folder)
    games = project / "scenes" / "games"
    games.mkdir()
    scene = '[gd_scene format=3]\n\n[node name="Fixture" type="Control"]\n'
    for name in ("reaction.tscn", "memory.tscn"):
        (games / name).write_text(scene, encoding="utf-8")
    tests = project / "tests"
    tests.mkdir()
    (tests / "excluded_fixture.tscn").write_text(scene, encoding="utf-8")
    smoke = '''extends SceneTree
func _initialize() -> void:
    for path in ["res://scenes/games/reaction.tscn", "res://scenes/games/memory.tscn"]:
        if not ResourceLoader.exists(path, "PackedScene"):
            push_error("Missing dynamically loaded game scene: " + path)
            quit(1)
            return
        var scene := load(path) as PackedScene
        if scene == null:
            push_error("Could not load game scene: " + path)
            quit(1)
            return
    if ResourceLoader.exists("res://tests/excluded_fixture.tscn", "PackedScene"):
        push_error("Test fixture was included in the export")
        quit(1)
        return
    print("EXPORTED GAME SCENES TEST PASSED")
    quit()
'''
    (project / "scripts" / "pack_smoke.gd").write_text(smoke, encoding="utf-8")
    pack = temporary / "fixture.pck"
    run_godot("--path", project, "--editor", "--quit", cwd=temporary)
    run_godot("--path", project, "--export-pack", "Windows Desktop", pack, cwd=temporary)
    isolated_cwd = temporary / "empty"
    isolated_cwd.mkdir()
    output = run_godot("--main-pack", pack, "--script", "res://scripts/pack_smoke.gd", cwd=isolated_cwd)
    if "EXPORTED GAME SCENES TEST PASSED" not in output or "ERROR:" in output:
        raise RuntimeError("Exported game scene verification failed")
