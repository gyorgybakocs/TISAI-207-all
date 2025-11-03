import os
from locust import HttpUser, task, between, constant

class BenchmarkUser(HttpUser):
    wait_time = constant(0.0)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.flow_id = os.getenv("FLOW_ID")
        self.api_key = os.getenv("API_KEY")

    @task
    def run_flow(self):
        if not self.flow_id or not self.api_key:
            return

        payload = {
            "input_value": "hello from locust",
            "input_type": "text",
            "output_type": "text"
        }
        headers = {
            "x-api-key": self.api_key
        }

        self.client.post(
            f"/api/v1/run/{self.flow_id}?stream=false",
            json=payload,
            headers=headers,
            name="/api/v1/run/[flow_id]"
        )
