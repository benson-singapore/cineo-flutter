"""Create throwaway device bindings on the dedicated local test Hub only."""
import http.cookiejar
import json
import os
import urllib.request

BASE = "http://127.0.0.1:18764"
path = os.environ["CINEO_ISOLATED_FIXTURE"]
if not os.path.abspath(path).startswith("/tmp/cineo-e2e-"):
    raise ValueError("fixture must be in /tmp/cineo-e2e-*")
jar = http.cookiejar.CookieJar()
client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

def post(path, data, csrf=None):
    headers = {"Content-Type": "application/json"}
    if csrf:
        headers["X-CSRF-Token"] = csrf
    request = urllib.request.Request(BASE + path, json.dumps(data).encode(), headers, method="POST")
    with client.open(request) as response:
        return json.load(response)["data"]

csrf = post("/api/v1/admin/auth/login", {"username": "isolated", "password": "isolated-test-only"})["csrf_token"]
pin = post("/api/v1/admin/pins", {}, csrf)["pin"]
phone = post("/api/v1/device/bind", {"pin": pin, "device_name": "isolated phone", "device_type": "flutter"})
tv_pin = post("/api/v1/admin/pins", {}, csrf)["pin"]
fixture = {"tv_pin": tv_pin, "phone": phone, "csrf": csrf, "cookies": {c.name: c.value for c in jar}}
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w") as stream:
    json.dump(fixture, stream)
