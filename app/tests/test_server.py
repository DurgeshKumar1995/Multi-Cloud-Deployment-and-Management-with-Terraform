import json
import os
import threading
import unittest
from http.client import HTTPConnection

from app.server import Handler, ThreadingHTTPServer


class ServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ["CLOUD_PROVIDER"] = "test-cloud"
        os.environ["CLOUD_REGION"] = "test-region"
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def request(self, path):
        connection = HTTPConnection("127.0.0.1", self.server.server_port)
        connection.request("GET", path)
        response = connection.getresponse()
        body = response.read().decode("utf-8")
        connection.close()
        return response.status, response.getheader("Content-Type"), body

    def test_health(self):
        status, content_type, body = self.request("/health")
        self.assertEqual(status, 200)
        self.assertEqual(content_type, "application/json")
        payload = json.loads(body)
        self.assertEqual(payload["status"], "healthy")
        self.assertEqual(payload["cloud"], "test-cloud")

    def test_metrics(self):
        status, content_type, body = self.request("/metrics")
        self.assertEqual(status, 200)
        self.assertIn("text/plain", content_type)
        self.assertIn("multicloud_demo_requests_total", body)

    def test_not_found(self):
        status, _, body = self.request("/missing")
        self.assertEqual(status, 404)
        self.assertEqual(json.loads(body)["status"], "not_found")


if __name__ == "__main__":
    unittest.main()

