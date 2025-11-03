import os
import sys
import time
import requests
import json

LANGFLOW_URL = os.getenv("LANGFLOW_URL", "http://localhost:7860").rstrip("/")
USERNAME = os.getenv("LANGFLOW_SUPERUSER")
PASSWORD = os.getenv("LANGFLOW_SUPERUSER_PASSWORD")

if not USERNAME or not PASSWORD:
    sys.exit("Error: Superuser credentials not set.")

def die(msg, err=None):
    details = f" | Details: {err}" if err else ""
    print(f"FATAL: {msg}{details}", file=sys.stderr)
    sys.exit(1)

# === Login and API Key creation (This part is correct) ===
try:
    print("Benchmark Prep: Logging in as superuser...")
    login_data = {"username": USERNAME, "password": PASSWORD, "grant_type": "password"}
    resp = requests.post(
        f"{LANGFLOW_URL}/api/v1/login",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        data=login_data
    )
    resp.raise_for_status()
    token = resp.json().get("access_token")
    if not token: die("Login successful, but no access_token was returned.")
    print("Benchmark Prep: Login successful.")
except Exception as e: die("Login failed", e)

headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

try:
    print("Benchmark Prep: Creating a dedicated API key...")
    key_payload = {"name": f"benchmark-key-{int(time.time())}"}
    resp = requests.post(f"{LANGFLOW_URL}/api/v1/api_key/", headers=headers, json=key_payload)
    resp.raise_for_status()
    api_key = resp.json().get("api_key")
    if not api_key: die("API key created, but the key itself was not returned.")
    print("Benchmark Prep: API key created successfully.")
except Exception as e: die("Failed to create API key", e)

flow_name = f"BENCHMARK_FINAL_{int(time.time())}"
flow_payload = {
    "name": flow_name,
    "description": "Final, working benchmark flow.",
    "data": {
        "nodes": [
            {
                "id": "TextInput-1",
                "type": "genericNode",
                "position": {"x": 350, "y": 200},
                "data": {
                    "node": {
                        "template": {
                            "_type": "Component",
                            "code": {"type": "code", "show": True, "value": "from langflow.base.io.text import TextComponent\nfrom langflow.io import MultilineInput, Output\nfrom langflow.schema.message import Message\n\n\nclass TextInputComponent(TextComponent):\n    display_name = \"Text Input\"\n    description = \"Get text inputs from the Playground.\"\n    icon = \"type\"\n    name = \"TextInput\"\n\n    inputs = [\n        MultilineInput(\n            name=\"input_value\",\n            display_name=\"Text\",\n            info=\"Text to be passed as input.\",\n        ),\n    ]\n    outputs = [\n        Output(display_name=\"Message\", name=\"text\", method=\"text_response\"),\n    ]\n\n    def text_response(self) -> Message:\n        return Message(\n            text=self.input_value,\n        )\n", "name": "code", "advanced": True},
                            "input_value": {"trace_as_input": True, "multiline": True, "required": False, "show": True, "name": "input_value", "value": "", "display_name": "Text", "advanced": False, "input_types": ["Message"], "type": "str"}
                        },
                        "description": "Get text inputs from the Playground.",
                        "icon": "type",
                        "base_classes": ["Message"],
                        "display_name": "Text Input",
                        "outputs": [{"types": ["Message"], "selected": "Message", "name": "text", "display_name": "Message", "method": "text_response"}]
                    },
                    "type": "TextInput",
                    "id": "TextInput-1"
                }
            },
            {
                "id": "TextOutput-1",
                "type": "genericNode",
                "position": {"x": 750, "y": 200},
                "data": {
                    "node": {
                        "template": {
                            "_type": "Component",
                            "code": {"type": "code", "show": True, "value": "import time\nfrom langflow.base.io.text import TextComponent\nfrom langflow.io import MultilineInput, Output\nfrom langflow.schema.message import Message\n\n\nclass TextOutputComponent(TextComponent):\n    display_name = \"Text Output\"\n    description = \"Display a text output in the Playground.\"\n    icon = \"type\"\n    name = \"TextOutput\"\n\n    inputs = [\n        MultilineInput(\n            name=\"input_value\",\n            display_name=\"Text\",\n            info=\"Text to be passed as output.\",\n        ),\n    ]\n    outputs = [\n        Output(display_name=\"Message\", name=\"text\", method=\"text_response\"),\n    ]\n\n    def text_response(self) -> Message:\n        time.sleep(0.5)\n        message = Message(\n            text=self.input_value,\n        )\n        self.status = self.input_value\n        return message\n", "name": "code", "advanced": True},
                            "input_value": {"multiline": True, "required": False, "show": True, "name": "input_value", "value": "", "display_name": "Text", "advanced": False, "input_types": ["Message"], "type": "str"}
                        },
                        "description": "Display a text output in the Playground.",
                        "icon": "type",
                        "base_classes": ["Message"],
                        "display_name": "Text Output",
                        "edited": True,  # <--- EZ VOLT A LÉNYEG!
                        "outputs": [{"types": ["Message"], "selected": "Message", "name": "text", "display_name": "Message", "method": "text_response"}]
                    },
                    "type": "TextOutput",
                    "id": "TextOutput-1"
                }
            }
        ],
        "edges": [
            {
                "source": "TextInput-1",
                "target": "TextOutput-1",
                "data": {
                    "sourceHandle": {"dataType": "TextInput", "id": "TextInput-1", "name": "text", "output_types": ["Message"]},
                    "targetHandle": {"fieldName": "input_value", "id": "TextOutput-1", "inputTypes": ["Message"], "type": "str"}
                }
            }
        ],
        "viewport": {"x": 0, "y": 0, "zoom": 1}
    }
}


try:
    print(f"Benchmark Prep: Creating benchmark flow '{flow_name}'...")
    resp = requests.post(f"{LANGFLOW_URL}/api/v1/flows/", headers=headers, json=flow_payload)
    resp.raise_for_status()
    flow_id = resp.json().get("id")
    if not flow_id: die("Flow created, but no ID was returned.")
    print(f"Benchmark Prep: Flow created with ID: {flow_id}")
except Exception as e: die("Flow creation failed", e)

print(f"BENCHMARK_DATA:FLOW_ID={flow_id}")
print(f"BENCHMARK_DATA:API_KEY={api_key}")
