"""Security baseline regression tests for Story 1.4."""

from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from src.config import Settings
from src.security_checks import validate_mobile_artifact_secrets


class SettingsSecurityBaselineTests(unittest.TestCase):
    def test_production_rejects_wildcard_cors(self):
        settings = Settings(
            _env_file=None,
            environment="production",
            cors_origins=["*"],
            session_secret="strong-session-secret",
        )

        with self.assertRaisesRegex(ValueError, "wildcard"):
            settings.validate_security_baseline()

    def test_production_requires_non_default_session_secret(self):
        settings = Settings(
            _env_file=None,
            environment="production",
            cors_origins=["https://mobile.example.com"],
            session_secret="change-me",
        )

        with self.assertRaisesRegex(ValueError, "SESSION_SECRET"):
            settings.validate_security_baseline()

    def test_production_requires_strong_session_secret(self):
        settings = Settings(
            _env_file=None,
            environment="production",
            cors_origins=["https://mobile.example.com"],
            session_secret="short-secret",
        )

        with self.assertRaisesRegex(ValueError, "SESSION_SECRET"):
            settings.validate_security_baseline()

    def test_invalid_environment_value_is_rejected(self):
        settings = Settings(
            _env_file=None,
            environment="prodution",
            cors_origins=["https://mobile.example.com"],
            session_secret="this-is-a-long-enough-session-secret-value",
        )

        with self.assertRaisesRegex(ValueError, "ENVIRONMENT"):
            settings.validate_security_baseline()

    def test_development_allows_relaxed_defaults(self):
        settings = Settings(
            _env_file=None,
            environment="development",
            cors_origins=["*"],
            session_secret="change-me",
        )

        settings.validate_security_baseline()


class MobileArtifactSecretHygieneTests(unittest.TestCase):
    def test_mobile_artifact_templates_have_no_privileged_keys(self):
        issues = validate_mobile_artifact_secrets()
        self.assertEqual([], issues, "\n".join(issues))

    def test_scanner_detects_export_lowercase_prohibited_keys(self):
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / ".env.production").write_text(
                "export er_password=super-secret\n",
                encoding="utf-8",
            )

            issues = validate_mobile_artifact_secrets(root)
            self.assertTrue(any("ER_PASSWORD" in issue for issue in issues), "\n".join(issues))

    def test_scanner_detects_commented_prohibited_assignments(self):
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / ".env.example").write_text(
                "# SUPABASE_SERVICE_ROLE_KEY=real-token-should-not-be-here\n",
                encoding="utf-8",
            )

            issues = validate_mobile_artifact_secrets(root)
            self.assertTrue(
                any("SUPABASE_SERVICE_ROLE_KEY" in issue for issue in issues),
                "\n".join(issues),
            )

    def test_scanner_detects_legacy_dotenv_reference_in_dart(self):
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / ".env.example").write_text(
                "SUPABASE_ANON_KEY=anon-key\n",
                encoding="utf-8",
            )
            lib_dir = root / "lib"
            lib_dir.mkdir(parents=True, exist_ok=True)
            (lib_dir / "main.dart").write_text(
                "final v = dotenv.env['ER_PASSWORD'];\n",
                encoding="utf-8",
            )

            issues = validate_mobile_artifact_secrets(root)
            self.assertTrue(
                any("legacy mobile dotenv reference 'ER_PASSWORD'" in issue for issue in issues),
                "\n".join(issues),
            )

    def test_scanner_detects_whitespace_and_case_variant_dotenv_reference(self):
        with TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / ".env.example").write_text(
                "SUPABASE_ANON_KEY=anon-key\n",
                encoding="utf-8",
            )
            lib_dir = root / "lib"
            lib_dir.mkdir(parents=True, exist_ok=True)
            (lib_dir / "main.dart").write_text(
                "final token = dotenv . env [ 'earthranger_token' ];\n",
                encoding="utf-8",
            )

            issues = validate_mobile_artifact_secrets(root)
            self.assertTrue(
                any("legacy mobile dotenv reference 'EARTHRANGER_TOKEN'" in issue for issue in issues),
                "\n".join(issues),
            )

if __name__ == "__main__":
    unittest.main()
