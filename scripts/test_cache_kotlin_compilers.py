import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "kotlin_cache", Path(__file__).with_name("cache_kotlin_compilers.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class KotlinCacheTests(unittest.TestCase):
    def test_verified_bytes_use_gradle_content_address_and_skip_redownload(self):
        body = b"compiler"
        with tempfile.TemporaryDirectory() as directory:
            target = module.cache_compiler("2.2.20", hashlib.sha256(body).hexdigest(),
                                           Path(directory), lambda *_a, **_k: io.BytesIO(body))
            self.assertEqual(hashlib.sha1(body).hexdigest().lstrip("0"), target.parent.name)
            self.assertEqual(body, target.read_bytes())
            module.cache_compiler("2.2.20", hashlib.sha256(body).hexdigest(), Path(directory),
                                  lambda *_a, **_k: self.fail("verified cache downloaded again"))

    def test_network_failure_uses_second_official_download(self):
        body = b"compiler"
        requests = []
        def opener(request, timeout):
            requests.append(request.full_url)
            if len(requests) == 1:
                raise OSError("504")
            return io.BytesIO(body)
        with tempfile.TemporaryDirectory() as directory:
            target = module.cache_compiler("2.2.20", hashlib.sha256(body).hexdigest(),
                                           Path(directory), opener)
            self.assertEqual(body, target.read_bytes())
            self.assertIn("maven-central.storage-download.googleapis.com", requests[1])

    def test_corrupt_download_never_enters_gradle_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                module.cache_compiler("2.2.20", "0" * 64, Path(directory),
                                      lambda *_a, **_k: io.BytesIO(b"corrupt"))
            self.assertFalse(list(Path(directory).rglob("*.jar")))
            self.assertFalse(list(Path(directory).rglob("*.download")))


if __name__ == "__main__":
    unittest.main()
