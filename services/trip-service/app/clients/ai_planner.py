"""HTTP client for the internal AI Planner service (Backend B).

All calls are authenticated with a shared internal token. Transient failures
(connection errors, 5xx) are retried once; the caller receives an
``AIPlannerError`` carrying an appropriate HTTP status to relay to the user.
"""
import requests


class AIPlannerError(Exception):
    def __init__(self, message, status_code=502):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


class AIPlannerClient:
    def __init__(self, base_url, token, timeout=60.0):
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.timeout = timeout

    def _headers(self):
        return {"X-Internal-Token": self.token, "Content-Type": "application/json"}

    def plan(self, payload):
        return self._post("/api/plan", payload)

    def optimize(self, payload):
        return self._post("/api/optimize", payload)

    def _post(self, path, payload):
        url = f"{self.base_url}{path}"
        last_error = None
        for _ in range(2):  # initial attempt + one retry
            try:
                resp = requests.post(
                    url, json=payload, headers=self._headers(), timeout=self.timeout
                )
            except requests.exceptions.RequestException as exc:
                last_error = AIPlannerError(f"AI Planner unreachable: {exc}", 503)
                continue

            if resp.status_code >= 500:
                # 503 => downstream/provider unavailable (propagate as-is so the
                # UI can say "try again"); other 5xx => bad gateway.
                status = 503 if resp.status_code == 503 else 502
                last_error = AIPlannerError(
                    f"AI Planner returned {resp.status_code}", status
                )
                continue
            if resp.status_code >= 400:
                raise AIPlannerError(_extract_message(resp), 502)
            try:
                return resp.json()
            except ValueError:
                raise AIPlannerError("AI Planner returned invalid JSON", 502)

        raise last_error

    def health(self):
        try:
            resp = requests.get(f"{self.base_url}/health", timeout=5)
            return resp.status_code == 200
        except requests.exceptions.RequestException:
            return False


def _extract_message(resp):
    try:
        return f"AI Planner error: {resp.json().get('message', resp.text)}"
    except ValueError:
        return f"AI Planner error: {resp.text[:200]}"
