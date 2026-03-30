"""Security hygiene checks for mobile-distributed artifacts.

Run as a build-time guard:
    python -m src.security_checks
"""

from __future__ import annotations

import re
from pathlib import Path


PROHIBITED_MOBILE_ENV_KEYS: set[str] = {
    "ER_USERNAME",
    "ER_PASSWORD",
    "EARTHRANGER_TOKEN",
    "SUPABASE_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
}

SERVICE_ROLE_MARKERS: tuple[str, ...] = (
    "service_role",
    "c2vydmljzv9yb2xl",  # base64-url marker for "service_role"
)

EXCLUDED_ENV_SCAN_DIRS: set[str] = {
    ".dart_tool",
    ".git",
    "build",
    "__pycache__",
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _mobile_root() -> Path:
    return _repo_root() / "mobile" / "epic-treeinfo-dart"


def _env_files_to_scan(mobile_root: Path) -> list[Path]:
    """Return all mobile env-like files that may ship with artifacts."""
    def _is_generated_or_tooling_path(path: Path) -> bool:
        return any(part in EXCLUDED_ENV_SCAN_DIRS for part in path.parts)

    return sorted(
        p for p in mobile_root.rglob(".env*")
        if p.is_file() and not _is_generated_or_tooling_path(p)
    )


def _dart_files_to_scan(mobile_root: Path) -> list[Path]:
    """Return mobile Dart source files where legacy env references may persist."""
    lib_root = mobile_root / "lib"
    if not lib_root.exists():
        return []
    return sorted(p for p in lib_root.rglob("*.dart") if p.is_file())


def _extract_assignment(raw_line: str) -> tuple[str, str] | None:
    """Extract KEY=VALUE from normal/commented/export env lines.

    Supports:
    - KEY=VALUE
    - export KEY=VALUE
    - # KEY=VALUE
    - # export KEY=VALUE
    """
    line = raw_line.strip()
    if not line or "=" not in line:
        return None

    if line.startswith("#"):
        line = line[1:].strip()

    if line.lower().startswith("export "):
        line = line[7:].strip()

    if "=" not in line:
        return None

    key, value = line.split("=", 1)
    return key.strip(), value.strip()


def scan_mobile_env_file(env_file: Path) -> list[str]:
    """Return a list of security issues found in a mobile env file."""
    if not env_file.exists():
        return []

    issues: list[str] = []
    for line_number, raw_line in enumerate(env_file.read_text(encoding="utf-8").splitlines(), start=1):
        assignment = _extract_assignment(raw_line)
        if assignment is None:
            continue

        key, value = assignment
        normalized_key = key.upper()

        if normalized_key in PROHIBITED_MOBILE_ENV_KEYS:
            issues.append(
                f"{env_file}: line {line_number} contains prohibited mobile key '{normalized_key}'."
            )

        lower_value = value.lower()
        if any(marker in lower_value for marker in SERVICE_ROLE_MARKERS):
            issues.append(
                f"{env_file}: line {line_number} appears to contain a Supabase service-role token marker."
            )

    return issues


def scan_mobile_source_for_legacy_env_refs(mobile_root: Path) -> list[str]:
    """Detect prohibited dotenv references that should not appear in mobile source."""
    issues: list[str] = []

    for dart_file in _dart_files_to_scan(mobile_root):
        content = dart_file.read_text(encoding="utf-8")
        for key in sorted(PROHIBITED_MOBILE_ENV_KEYS):
            pattern = re.compile(
                rf"dotenv\s*\.\s*env\s*\[\s*['\"]{re.escape(key)}['\"]\s*\]",
                re.IGNORECASE,
            )
            if pattern.search(content):
                issues.append(
                    f"{dart_file}: legacy mobile dotenv reference '{key}' detected; use approved keys only."
                )

    return issues


def validate_mobile_artifact_secrets(mobile_root: Path | None = None) -> list[str]:
    """Validate mobile artifact env files for privileged secret leakage."""
    root = mobile_root or _mobile_root()

    env_targets = _env_files_to_scan(root)

    issues: list[str] = []
    for target in env_targets:
        issues.extend(scan_mobile_env_file(target))

    issues.extend(scan_mobile_source_for_legacy_env_refs(root))

    return issues


def main() -> int:
    """CLI entrypoint for CI/build-time checks."""
    issues = validate_mobile_artifact_secrets()

    if issues:
        print("❌ Mobile artifact secret hygiene check failed:")
        for issue in issues:
            print(f"- {issue}")
        return 1

    print("✅ Mobile artifact secret hygiene check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
