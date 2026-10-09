"""Host-only safety, ABI, and packaging tests for the Stage C module."""

from __future__ import annotations

import importlib.util
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
SYSTEM_VENDOR = ROOT / "system/vendor"
SCRIPTS = (
    "pre-mount.sh",
    "post-fs-data.sh",
    "late-load.sh",
    "post-mount.sh",
    "service.sh",
    "audio-reload.sh",
    "validate-service.sh",
)
SERVICE_SHA256 = "3360d5eddc319830310be921c22cfcf2a42f3cbfa2a000c1ab46bdf0d87a1d85"
HOOK_SHA256 = "195f355f436931e4c161c21966e807bc44d25bb9fec93c6c6011da5ea88a95f3"
COMPAT_SHA256 = {
    "android.hardware.audio.effect-V2-ndk.so":
        "665982cb368fcd15b8aad5a3a31f79fd89bc7eded79fac6cb6a3e1303a8be190",
    "android.hardware.audio.common-V3-ndk.so":
        "ad5e918bb9ac6b40474b0c7b575b39e9254431a2f8d250962e070b989cc9e33c",
    "android.media.audio.common.types-V3-ndk.so":
        "6bc927c58c168eb8d1d2d96d6d0d9c163827114ad970b84eeead0bb65e0eb387",
}


def sha256(path: pathlib.Path) -> str:
    import hashlib

    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_packager():
    path = ROOT / "tools/package_stage_c.py"
    spec = importlib.util.spec_from_file_location("package_stage_c", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class StageCSafetyTests(unittest.TestCase):
    def test_vendor_layout_is_real_and_hook_is_not_mountable(self) -> None:
        self.assertTrue(SYSTEM_VENDOR.is_dir())
        self.assertFalse(SYSTEM_VENDOR.is_symlink())
        self.assertFalse((ROOT / "system/lib64/libaudiohal@aidl.so").exists())
        self.assertFalse((ROOT / "system/lib64/aml.so").exists())
        self.assertTrue((ROOT / "staging/hook/aml.so").is_file())

    def test_prebuilt_binaries_are_byte_identical(self) -> None:
        self.assertEqual(
            sha256(SYSTEM_VENDOR / "bin/hw/vendor.aml.effect-service"),
            SERVICE_SHA256,
        )
        self.assertEqual(sha256(ROOT / "staging/hook/aml.so"), HOOK_SHA256)

    def test_frozen_aidl_payload_hashes(self) -> None:
        for name, expected in COMPAT_SHA256.items():
            self.assertEqual(
                sha256(SYSTEM_VENDOR / "lib64/pixaml" / name), expected
            )

    def test_compatibility_libraries_are_private_to_aml(self) -> None:
        vendor_lib64 = SYSTEM_VENDOR / "lib64"
        self.assertEqual(
            sorted(path.name for path in vendor_lib64.iterdir()), ["pixaml"]
        )
        self.assertTrue((vendor_lib64 / "pixaml").is_dir())
        for name in COMPAT_SHA256:
            self.assertFalse((vendor_lib64 / name).exists())

    def test_manifest_records_frozen_interface_hashes(self) -> None:
        manifest = (ROOT / "compat-manifest.txt").read_text()
        for interface_hash in (
            "54d5a2e1d59066b57e35eb7bcb5ebc72a1259c1c",
            "57ce9506b87e721f0d994b16d7cd16a494f699b9",
            "0c86a38729dd5d560fe3a0eca6aa9d8cf83efb00",
        ):
            self.assertIn(interface_hash, manifest)

    def test_no_active_policy_or_legacy_patcher_at_module_root(self) -> None:
        for name in (
            "sepolicy.rule",
            "patch.sh",
            "permissions.sh",
            "aml.sh",
            "v4a.sh",
            "patchelf",
            "aml_map.txt",
        ):
            self.assertFalse((ROOT / name).exists(), name)

    def test_scripts_are_posix_shell_syntax(self) -> None:
        for name in ("customize.sh", *SCRIPTS):
            result = subprocess.run(
                ["sh", "-n", str(ROOT / name)],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, f"{name}: {result.stderr}")

    def test_audio_reload_is_late_load_only_bounded_and_hook_free(self) -> None:
        combined = "\n".join((ROOT / name).read_text() for name in SCRIPTS)
        self.assertNotIn("patchelf", combined)
        self.assertNotIn("killall", combined)
        self.assertNotIn("mount -o", combined)
        self.assertNotIn("while sleep", combined)
        self.assertNotIn("libaudiohal@aidl.so", (ROOT / "service.sh").read_text())
        reload_script = (ROOT / "audio-reload.sh").read_text()
        self.assertIn("unsafe_audio_restart_disabled", reload_script)
        self.assertNotIn("ctl.restart", reload_script)
        self.assertNotIn("setprop", reload_script)
        self.assertNotIn("while true", reload_script)
        self.assertNotIn(
            "vendor.aml.effect-service", (ROOT / "post-fs-data.sh").read_text()
        )
        self.assertNotIn(
            "vendor.aml.effect-service", (ROOT / "late-load.sh").read_text()
        )

    def test_audio_reload_entrypoint_is_disabled(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            module = pathlib.Path(tmp) / "module"
            state = module / "state"
            module.mkdir()
            shutil.copy2(ROOT / "audio-reload.sh", module / "audio-reload.sh")
            env = os.environ.copy()
            env.update({"PIXAML_STATE_DIR": str(state), "KSU_LATE_LOAD": "1"})
            result = subprocess.run(
                ["sh", str(module / "audio-reload.sh")],
                check=False,
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                (state / "audio-reload.status").read_text(),
                "SKIPPED reason=unsafe_audio_restart_disabled\n",
            )

    def test_service_autostart_is_standalone_and_gated(self) -> None:
        options = (ROOT / "options.conf").read_text()
        self.assertIn("PIXAML_SERVICE_AUTOSTART=1", options)
        service = (ROOT / "service.sh").read_text()
        self.assertIn("PIXAML_SERVICE_AUTOSTART=1", service)
        self.assertIn("post_mount_not_ready", service)
        self.assertIn("binder_registration_timeout", service)
        self.assertIn('CONFIG="$MODDIR/config/audio_effects_config.xml"', service)
        self.assertIn('"$SERVICE" "$CONFIG"', service)
        self.assertIn('kill "$pid"', service)
        self.assertIn('wait "$pid"', service)
        self.assertIn('before_binder_registration code=%s', service)
        self.assertNotIn("while true", service)

    def test_customize_overrides_generic_partition_rewrite(self) -> None:
        command = r"""
handle_partition() { printf 'generic-rewrite-called\n'; }
ui_print() { :; }
abort() { exit 97; }
set_perm_recursive() { :; }
set_perm() { :; }
MODPATH=$1
. "$2"
handle_partition vendor
"""
        with tempfile.TemporaryDirectory() as tmp:
            module = pathlib.Path(tmp) / "module"
            shutil.copytree(
                ROOT / "system",
                module / "system",
                copy_function=shutil.copy2,
            )
            shutil.copytree(
                ROOT / "staging",
                module / "staging",
                copy_function=shutil.copy2,
            )
            shutil.copytree(ROOT / "config", module / "config", copy_function=shutil.copy2)
            shutil.copy2(ROOT / "options.conf", module / "options.conf")
            shutil.copy2(
                ROOT / "compat-manifest.txt", module / "compat-manifest.txt"
            )
            for name in SCRIPTS:
                shutil.copy2(ROOT / name, module / name)
            result = subprocess.run(
                [
                    "sh",
                    "-c",
                    command,
                    "installer-test",
                    str(module),
                    str(ROOT / "customize.sh"),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertTrue((module / "system/vendor").is_dir())
            self.assertFalse((module / "system/vendor").is_symlink())

    def test_pre_mount_accepts_valid_late_load_layout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            module = pathlib.Path(tmp) / "module"
            shutil.copytree(ROOT / "system", module / "system")
            shutil.copytree(ROOT / "config", module / "config")
            shutil.copy2(ROOT / "pre-mount.sh", module / "pre-mount.sh")
            result = subprocess.run(
                ["sh", str(module / "pre-mount.sh"), "late-load"],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                (module / "state/pre-mount.status").read_text().strip(),
                "READY stage=late-load layout=system/vendor hook=disabled",
            )
            self.assertFalse((module / "skip_mount").exists())

    def test_pre_mount_fails_closed_for_symlink_layout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            module = pathlib.Path(tmp) / "module"
            (module / "vendor/bin/hw").mkdir(parents=True)
            (module / "vendor/etc").mkdir(parents=True)
            (module / "system").mkdir()
            (module / "system/vendor").symlink_to("../vendor")
            shutil.copy2(ROOT / "pre-mount.sh", module / "pre-mount.sh")
            result = subprocess.run(
                ["sh", str(module / "pre-mount.sh"), "post-fs-data"],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue((module / "skip_mount").is_file())
            self.assertIn(
                "system_vendor_is_symlink",
                (module / "state/pre-mount.status").read_text(),
            )


    def test_no_mountable_vendor_audio_effects_config_payload(self) -> None:
        self.assertFalse((SYSTEM_VENDOR / "etc/audio_effects_config.xml").exists())
        self.assertFalse((ROOT / "system/vendor/etc/audio_effects_config.xml").exists())
        self.assertTrue((ROOT / "config/audio_effects_config.xml").is_file())

    def test_configuration_is_well_formed_xml(self) -> None:
        root = ET.parse(ROOT / "config/audio_effects_config.xml").getroot()
        self.assertTrue(root.tag.endswith("audio_effects_conf"))

    def test_release_archive_has_exact_safe_allowlist(self) -> None:
        packager = load_packager()
        props = (ROOT / "module.prop").read_text()
        self.assertIn("version=v0.9.6-rc1-service-diagnostics", props)
        self.assertIn("versionCode=106", props)
        with tempfile.TemporaryDirectory() as tmp:
            output = pathlib.Path(tmp) / "module.zip"
            packager.build(output)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.namelist(), list(packager.PAYLOADS))
                names = set(archive.namelist())
                self.assertNotIn("sepolicy.rule", names)
                self.assertFalse(
                    any(name.startswith("system/lib64/") for name in names)
                )
                self.assertNotIn("patchelf", names)
                self.assertIn("late-load.sh", names)
                self.assertIn("audio-reload.sh", names)
                self.assertIn("config/audio_effects_config.xml", names)
                self.assertNotIn("system/vendor/etc/audio_effects_config.xml", names)
                for name in COMPAT_SHA256:
                    self.assertIn(f"system/vendor/lib64/pixaml/{name}", names)

    def test_private_compat_path_is_used_for_link_and_launch(self) -> None:
        post_mount = (ROOT / "post-mount.sh").read_text()
        service = (ROOT / "service.sh").read_text()
        validator = (ROOT / "validate-service.sh").read_text()
        for text in (post_mount, service, validator):
            self.assertIn("COMPAT_DIR=/vendor/lib64/pixaml", text)
        self.assertIn('LD_LIBRARY_PATH="$COMPAT_DIR"', post_mount)
        self.assertIn('LD_LIBRARY_PATH="$COMPAT_DIR"', service)

    def test_author_credit_order(self) -> None:
        props = (ROOT / "module.prop").read_text().splitlines()
        author = next(line for line in props if line.startswith("author="))
        self.assertTrue(author.startswith("author=lightningzahah,"))

    def test_compat_rebuild_script_is_shell_syntax(self) -> None:
        result = subprocess.run(
            ["sh", "-n", str(ROOT / "tools/build_aidl_compat.sh")],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_elf_compatibility_audit(self) -> None:
        env = os.environ.copy()
        if not (env.get("ANDROID_SDK_ROOT") or env.get("ANDROID_HOME")):
            self.skipTest("Android SDK not configured")
        result = subprocess.run(
            ["python3", str(ROOT / "tools/verify_elf_compat.py")],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("23 service AIDL symbols", result.stdout)


if __name__ == "__main__":
    unittest.main()
