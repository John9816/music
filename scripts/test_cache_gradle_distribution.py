import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("gradle_cache", Path(__file__).with_name("cache_gradle_distribution.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DistributionTests(unittest.TestCase):
    def properties(self, payload):
        return "distributionUrl=https\\://services.gradle.org/distributions/gradle-9.1.0-all.zip\ndistributionSha256Sum=" + hashlib.sha256(payload).hexdigest()

    def opener(self, expected, body):
        def open_response(request, timeout):
            if "/tags/" in request.full_url:
                return io.BytesIO(json.dumps({"assets": [{
                    "name": "gradle-9.1.0-all.zip",
                    "digest": "sha256:" + hashlib.sha256(expected).hexdigest(),
                    "url": "https://api.github.com/repos/gradle/gradle-distributions/releases/assets/123",
                }]}).encode())
            self.assertEqual("application/octet-stream", request.get_header("Accept"))
            return io.BytesIO(body)
        return open_response

    def test_official_asset_populates_actual_wrapper_cache_path(self):
        with tempfile.TemporaryDirectory() as directory:
            target = module.cache_distribution(self.properties(b"archive"), Path(directory), self.opener(b"archive", b"archive"))
            self.assertEqual("7wzd0jkjit61aq2p43wpjgij9", target.parent.name)
            self.assertEqual(b"archive", target.read_bytes())
            module.cache_distribution(self.properties(b"archive"), Path(directory), lambda *_a, **_k: self.fail("verified cache downloaded again"))

    def test_corrupt_download_never_replaces_existing_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            props = self.properties(b"archive")
            target, _, _ = module.wrapper_target(props, Path(directory))
            target.parent.mkdir(parents=True)
            target.write_bytes(b"old")
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                module.cache_distribution(props, Path(directory), self.opener(b"archive", b"corrupt"))
            self.assertEqual(b"old", target.read_bytes())
            self.assertFalse(target.with_suffix(".download").exists())


if __name__ == "__main__":
    unittest.main()
