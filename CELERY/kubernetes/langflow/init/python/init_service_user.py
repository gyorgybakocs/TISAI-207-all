import os
import sys
import json
import glob
import requests
import time

LANGFLOW_URL = os.getenv("LANGFLOW_URL", "http://localhost:7860")
USERNAME = os.getenv("LANGFLOW_SUPERUSER")
PASSWORD = os.getenv("LANGFLOW_SUPERUSER_PASSWORD")

env_file_path = "/app/tmp/.env.nextjs-langflow"
def add_value_to_env_file(file_path, key, value):
    lines = []
    if os.path.exists(file_path):
        with open(file_path, "r") as f:
            lines = f.readlines()

    new_line = f"{key}={value}\n"
    found = False
    for i, line in enumerate(lines):
        if line.strip().startswith(f"{key}="):
            lines[i] = new_line
            found = True
            break

    if not found:
        lines.append(new_line)

    with open(file_path, "w") as f:
        f.writelines(lines)

    print(f"Updated {env_file_path} with {key}={value}")


if not USERNAME or not PASSWORD:
    print("Error: LANGFLOW_SUPERUSER or LANGFLOW_SUPERUSER_PASSWORD not set")
    sys.exit(1)

MAX_RETRIES = 15
RETRY_DELAY_SECONDS = 2
ACCESS_TOKEN = None

print(f"--- Attempting to connect to Langflow at {LANGFLOW_URL} ---")

for attempt in range(MAX_RETRIES):
    try:
        print(f"Login attempt {attempt + 1}/{MAX_RETRIES} for user '{USERNAME}'...")
        login_data = {
            "username": USERNAME,
            "password": PASSWORD,
            "grant_type": "password"
        }
        response = requests.post(
            f"{LANGFLOW_URL}/api/v1/login",
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            data=login_data,
            timeout=5
        )

        if response.status_code == 200 and "access_token" in response.json():
            print("Login successful!")
            login_response = response.json()
            ACCESS_TOKEN = login_response.get("access_token")
            break
        else:
            print(f"Login failed with status {response.status_code}. Retrying in {RETRY_DELAY_SECONDS} seconds...")

    except requests.exceptions.ConnectionError as e:
        print(f"Connection failed: {e}. Service might not be ready. Retrying in {RETRY_DELAY_SECONDS} seconds...")

    time.sleep(RETRY_DELAY_SECONDS)


if not ACCESS_TOKEN:
    print("FATAL: Could not get access token for superuser after multiple retries. Aborting.")
    sys.exit(1)

print("Got access token")
headers = {"Authorization": f"Bearer {ACCESS_TOKEN}"}

# --- Step: Create API key for 'service_user' user ---
api_key_resp = requests.post(
    f"{LANGFLOW_URL}/api/v1/api_key/",
    headers={
        "Authorization": f"Bearer {ACCESS_TOKEN}",
        "Content-Type": "application/json",
    },
    json={"name": "secret_flows_key"},
)

print("API_KEY_RESPONSE:", api_key_resp.text)

LANGFLOW_API_KEY = api_key_resp.json().get("api_key")
if not LANGFLOW_API_KEY:
    print("Failed to create API key for 'langflow' user")
    sys.exit(1)

print(f"Created API key for 'langflow' user: {LANGFLOW_API_KEY}")

# Step: Update /app/tmp/.env.nextjs-langflow
add_value_to_env_file(env_file_path, "LANGFLOW_SERVICE_SECRET_KEY", LANGFLOW_API_KEY)


# Step 2: Get existing projects
projects_response = requests.get(f"{LANGFLOW_URL}/api/v1/projects/", headers=headers)
projects = projects_response.json() if projects_response.status_code == 200 else []

# Step 3: Handle subdirectories (projects)
for project_dir in glob.glob("/app/init/service_flows/*/"):
    if not os.path.isdir(project_dir):
        continue

    project_name = os.path.basename(os.path.normpath(project_dir))
    print(f"Processing project: {project_name}")

    # Check if project exists
    project_id = None
    for p in projects:
        if p.get("name") == project_name:
            project_id = p.get("id")
            break

    if not project_id:
        print(f"Creating project: {project_name}")
        create_payload = {
            "name": project_name,
            "description": "Created via script",
            "components_list": [],
            "flows_list": []
        }
        create_response = requests.post(
            f"{LANGFLOW_URL}/api/v1/projects/",
            headers={**headers, "Content-Type": "application/json"},
            json=create_payload
        )
        if create_response.status_code != 200:
            print(f"Failed to create project {project_name}: {create_response.text}")
            continue

        project_id = create_response.json().get("id")
        print(f"Created project {project_name} with ID: {project_id}")

        # Refresh projects list
        projects_response = requests.get(f"{LANGFLOW_URL}/api/v1/projects/", headers=headers)
        projects = projects_response.json() if projects_response.status_code == 200 else []
    else:
        print(f"Project already exists: {project_name} (ID: {project_id})")

    # Upload flows in subdirectory
    for flow_file in glob.glob(os.path.join(project_dir, "*.json")):
        print(f"Importing flow: {flow_file} into project {project_name}")
        with open(flow_file, "rb") as f:
            upload_response = requests.post(
                f"{LANGFLOW_URL}/api/v1/flows/upload/?folder_id={project_id}",
                headers={**headers, "accept": "application/json"},
                files={"file": (os.path.basename(flow_file), f, "application/json")}
            )
        if upload_response.status_code != 200:
            print(f"Failed to upload {flow_file}: {upload_response.text}")
        else:
            print(f"Done: {flow_file}")

# Step 4: Handle top-level JSON flows (no project_id)
for flow_file in glob.glob("/app/init/service_flows/*.json"):
    print(f"Importing top-level flow: {flow_file} (no project)")
    with open(flow_file, "rb") as f:
        upload_response = requests.post(
            f"{LANGFLOW_URL}/api/v1/flows/upload/",
            headers={**headers, "accept": "application/json"},
            files={"file": (os.path.basename(flow_file), f, "application/json")}
        )
    if upload_response.status_code != 200:
        print(f"Failed to upload {flow_file}: {upload_response.text}")
    else:
        print(f"Done: {flow_file}")

# Step 5: Get flows and extract "Basic Chatbot"
flows_response = requests.get(f"{LANGFLOW_URL}/api/v1/flows/", headers=headers)
if flows_response.status_code != 200:
    print(f"Failed to fetch flows: {flows_response.text}")
    sys.exit(1)

flows = flows_response.json() if isinstance(flows_response.json(), list) else []

basic_chatbot_id = None
email_categorization_id = None
email_auto_reply_id = None
ui_embedding_id = None
for flow in flows:
    if flow.get("name") == "Demo Chatbot":
        basic_chatbot_id = flow.get("id")
        continue

    if flow.get("name") == "Email Categorization":
        email_categorization_id = flow.get("id")
        continue
    if flow.get("name") == "Email Auto Response Generation":
        email_auto_reply_id = flow.get("id")
        continue

    if flow.get("name") == "UI Embedding":
        ui_embedding_id = flow.get("id")
        continue


add_value_to_env_file(env_file_path, "NEXT_PUBLIC_CHATBOT_FLOW_ID", basic_chatbot_id)
add_value_to_env_file(env_file_path, "NEXT_PUBLIC_EMAIL_CATEGORIZE_FLOW_ID", email_categorization_id)
add_value_to_env_file(env_file_path, "NEXT_PUBLIC_EMAIL_REPLY_FLOW_ID", email_auto_reply_id)
add_value_to_env_file(env_file_path, "NEXT_PUBLIC_VECTOR_DB_FLOW_ID", ui_embedding_id)
