"""Compose 설정만 해석한다. Docker 컨테이너나 실제 DB는 실행하지 않는다."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ProductionComposeTest(unittest.TestCase):
    def render(self, values):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            shutil.copy(ROOT / "docker-compose.production.yml", path)
            (path / ".env").write_text(
                "".join(f"{key}='{value}'\n" for key, value in values.items())
            )
            # 개발자의 셸에 설정된 실제 DB 환경 변수는 테스트에 사용하지 않는다.
            environment = {
                key: value for key, value in os.environ.items()
                if not key.startswith(("DB_", "MCP_", "COMPOSE_"))
            }
            return subprocess.run(
                ["docker", "compose", "--env-file", str(path / ".env"),
                 "-f", str(path / "docker-compose.production.yml"),
                 "config", "--format", "json"],
                env=environment, capture_output=True, text=True, timeout=10,
            )

    def settings(self):
        return {
            "DB_HOST": "production-postgres",
            "DB_PORT": "5433",
            "DB_USER": "mcp-reader",
            "DB_PASSWORD": "fixture$literal-password",
            "DB_NAME": "analysis-data",
            "MCP_DB_NETWORK": "existing-backend-network",
        }

    def test_uses_configured_database_and_existing_network_only(self):
        settings = self.settings()
        result = self.render(settings)
        self.assertEqual(result.returncode, 0, result.stderr)
        config = json.loads(result.stdout)
        self.assertEqual(set(config["services"]), {"app"})
        app = config["services"]["app"]
        for key, value in settings.items():
            if key.startswith("DB_"):
                # config 출력은 다시 Compose로 읽을 수 있도록 $를 이스케이프한다.
                self.assertEqual(app["environment"][key], value.replace("$", "$$"))
        self.assertFalse(app.get("depends_on"))
        self.assertEqual(set(app["networks"]), {"backend"})
        network = config["networks"]["backend"]
        self.assertEqual(network["name"], settings["MCP_DB_NETWORK"])
        self.assertTrue(network["external"])
        self.assertFalse(config.get("volumes"))

    def test_missing_required_settings_fail_before_deployment(self):
        for key in ("DB_HOST", "DB_USER", "DB_PASSWORD", "DB_NAME", "MCP_DB_NETWORK"):
            with self.subTest(key=key):
                settings = self.settings()
                del settings[key]
                result = self.render(settings)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(key, result.stderr)

    def test_empty_required_settings_fail_before_deployment(self):
        for key in ("DB_HOST", "DB_USER", "DB_PASSWORD", "DB_NAME", "MCP_DB_NETWORK"):
            with self.subTest(key=key):
                settings = self.settings()
                settings[key] = ""
                self.assertNotEqual(self.render(settings).returncode, 0)

    def test_database_port_defaults_to_postgres_port(self):
        settings = self.settings()
        del settings["DB_PORT"]
        result = self.render(settings)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout)["services"]["app"]["environment"]["DB_PORT"],
            "5432",
        )


if __name__ == "__main__":
    unittest.main()
