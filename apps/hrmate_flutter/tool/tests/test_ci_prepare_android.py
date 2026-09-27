"""Resource-budget regression checks; no Android SDK or secrets required."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "ci_prepare_android.py"
spec = importlib.util.spec_from_file_location("ci_prepare_android", SCRIPT)
prep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prep)


class GradleBudgetTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old_cwd = os.getcwd()
        os.chdir(self.tmp.name)
        Path("android").mkdir()
        self.props = Path("android/gradle.properties")
        self.props.write_text(
            "org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:+HeapDumpOnOutOfMemoryError\n"
            "android.useAndroidX=true\n"
        )

    def tearDown(self):
        os.chdir(self.old_cwd)
        self.tmp.cleanup()

    def prepare(self, env, release=False):
        with patch.dict(os.environ, env, clear=True), contextlib.redirect_stdout(io.StringIO()):
            prep.patch_gradle_props(release=release)
        return self.props.read_text()

    def test_debug_budget_and_idempotence(self):
        first = self.prepare({})
        self.assertEqual(first, self.prepare({}))
        for value in ["-Xmx2200m", "-XX:MaxMetaspaceSize=768m", "android.useAndroidX=true",
                      "org.gradle.daemon=false", "org.gradle.parallel=false", "org.gradle.workers.max=2"]:
            self.assertIn(value, first)
        self.assertNotIn("kotlin.compiler.execution.strategy", first)

    def test_release_uses_one_worker_and_one_compiler_jvm(self):
        self.props.write_text(self.props.read_text() +
                              "org.gradle.daemon=true\norg.gradle.parallel=true\n"
                              "org.gradle.workers.max=12\nkotlin.compiler.execution.strategy=daemon\n")
        env = {"GRADLE_XMX": "3g", "GRADLE_WORKERS": "1"}
        result = self.prepare(env, release=True)
        self.assertEqual(result, self.prepare(env, release=True))
        for value in ["-Xmx3g", "org.gradle.workers.max=1", "org.gradle.daemon=false",
                      "org.gradle.parallel=false", "kotlin.compiler.execution.strategy=in-process"]:
            self.assertIn(value, result)
        self.assertEqual(result.count("org.gradle.workers.max="), 1)
        self.assertEqual(result.count("kotlin.compiler.execution.strategy="), 1)

    def test_bad_worker_limit_does_not_rewrite_properties(self):
        before = self.props.read_text()
        for workers in ["0", "5", "many", "1.5"]:
            with self.subTest(workers=workers), self.assertRaises(ValueError):
                self.prepare({"GRADLE_WORKERS": workers}, release=True)
            self.assertEqual(before, self.props.read_text())


if __name__ == "__main__":
    unittest.main()
