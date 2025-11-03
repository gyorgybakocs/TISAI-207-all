import os
import sys
import glob
import requests
import time

LANGFLOW_URL = os.getenv("LANGFLOW_URL", "http://localhost:7860")

SUPERUSER = os.getenv("LANGFLOW_SUPERUSER")
SUPERUSER_PASSWORD = os.getenv("LANGFLOW_SUPERUSER_PASSWORD")

if not SUPERUSER or not SUPERUSER_PASSWORD:
    print("Error: LANGFLOW_SUPERUSER or LANGFLOW_SUPERUSER_PASSWORD not set")
    sys.exit(1)

# langflow user credentials
LANGFLOW_USERNAME = os.getenv("LANGFLOW_USERNAME", "langflow")
LANGFLOW_PASSWORD = os.getenv("LANGFLOW_PASSWORD", "langflow")


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

MAX_RETRIES = 15
RETRY_DELAY_SECONDS = 2
ACCESS_TOKEN = None

print(f"--- Attempting to connect to Langflow at {LANGFLOW_URL} ---")

for attempt in range(MAX_RETRIES):
    try:
        print(f"Login attempt {attempt + 1}/{MAX_RETRIES} for user '{SUPERUSER}'...")
        # --- Step 1: Login as superuser ---
        login_resp = requests.post(
            f"{LANGFLOW_URL}/api/v1/login",
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            data={
                "username": SUPERUSER,
                "password": SUPERUSER_PASSWORD,
                "grant_type": "password",
            },
            timeout=5
        )

        if login_resp.status_code == 200 and "access_token" in login_resp.json():
            print("Superuser login successful!")
            ACCESS_TOKEN = login_resp.json()["access_token"]
            break
        else:
            print(f"Superuser login failed with status {login_resp.status_code}. Retrying in {RETRY_DELAY_SECONDS} seconds...")

    except requests.exceptions.ConnectionError as e:
        print(f"Connection failed: {e}. Service might not be ready. Retrying in {RETRY_DELAY_SECONDS} seconds...")

    time.sleep(RETRY_DELAY_SECONDS)


if not ACCESS_TOKEN:
    print("FATAL: Could not get access token for superuser after multiple retries. Aborting.")
    sys.exit(1)


print("Got superuser access token")
headers = {"Authorization": f"Bearer {ACCESS_TOKEN}"}

# --- Step 2: Check if 'langflow' user exists ---
users_resp = requests.get(f"{LANGFLOW_URL}/api/v1/users/", headers=headers)
users = users_resp.json().get("users", [])

user = next((u for u in users if u.get("username") == LANGFLOW_USERNAME), None)
user_id = user.get("id") if user else None

if not user_id:
    print("Creating user: langflow")
    create_user_resp = requests.post(
        f"{LANGFLOW_URL}/api/v1/users/",
        headers={**headers, "Content-Type": "application/json"},
        json={
            "username": LANGFLOW_USERNAME,
            "password": LANGFLOW_PASSWORD,
            "is_superuser": False,
            "is_active": False,
            "optins": {"github_starred": False, "dialog_dismissed": True, "discord_clicked": False}
        },
    )

    if create_user_resp.status_code != 201:
        print("Failed to create user:", create_user_resp.text)
        sys.exit(1)
    user_id = create_user_resp.json().get("id")
    print(f"Created user with ID: {user_id}")

print("Reactivating user")
requests.patch(
    f"{LANGFLOW_URL}/api/v1/users/{user_id}",
    headers={**headers, "Content-Type": "application/json"},
    json={"is_active": True},
)
print("User reactivated")

# --- Step 3: Login as 'langflow' user ---
login_user_resp = requests.post(
    f"{LANGFLOW_URL}/api/v1/login",
    headers={"Content-Type": "application/x-www-form-urlencoded"},
    data={
        "username": LANGFLOW_USERNAME,
        "password": LANGFLOW_PASSWORD,
        "grant_type": "password",
    },
)

if login_user_resp.status_code != 200 or "access_token" not in login_user_resp.json():
    print("Login failed for 'langflow' user")
    print(login_user_resp.text)
    sys.exit(1)

NEW_ACCESS_TOKEN = login_user_resp.json()["access_token"]
print("Got access token for 'langflow' user")
print(NEW_ACCESS_TOKEN)

# --- Step 4: Create API key for 'langflow' user ---
api_key_resp = requests.post(
    f"{LANGFLOW_URL}/api/v1/api_key/",
    headers={
        "Authorization": f"Bearer {NEW_ACCESS_TOKEN}",
        "Content-Type": "application/json",
    },
    json={"name": "public_flows_key"},
)

print("API_KEY_RESPONSE:", api_key_resp.text)

LANGFLOW_API_KEY = api_key_resp.json().get("api_key")
if not LANGFLOW_API_KEY:
    print("Failed to create API key for 'langflow' user")
    sys.exit(1)

print(f"Created API key for 'langflow' user: {LANGFLOW_API_KEY}")

add_value_to_env_file(env_file_path, "LANGFLOW_PUBLIC_SECRET_KEY", LANGFLOW_API_KEY)


api_headers = {"x-api-key": LANGFLOW_API_KEY, "accept": "application/json"}

# --- Step 5: Upload top-level public flows ---
for flow_file in glob.glob("/app/init/public_flows/*.json"):
    print(f"Uploading top-level public flow: {flow_file}")
    with open(flow_file, "rb") as f:
        upload_resp = requests.post(
            f"{LANGFLOW_URL}/api/v1/flows/upload/",
            headers=api_headers,
            files={"file": (os.path.basename(flow_file), f, "application/json")},
        )
    if upload_resp.status_code != 201:
        print(f"Failed to upload {flow_file}: {upload_resp.text}")
    else:
        print(f"Done: {flow_file}")

# --- Step 6: Upload flows from subdirectories as projects ---
projects_resp = requests.get(f"{LANGFLOW_URL}/api/v1/projects/", headers=api_headers)
projects = projects_resp.json() if projects_resp.status_code == 201 else []

for project_dir in glob.glob("/app/init/public_flows/*/"):
    if not os.path.isdir(project_dir):
        continue
    project_name = os.path.basename(os.path.normpath(project_dir))
    print(f"Processing public project: {project_name}")

    project = next((p for p in projects if p.get("name") == project_name), None)
    project_id = project.get("id") if project else None

    if not project_id:
        print(f"Creating project: {project_name}")
        create_project_resp = requests.post(
            f"{LANGFLOW_URL}/api/v1/projects/",
            headers={**api_headers, "Content-Type": "application/json"},
            json={
                "name": project_name,
                "description": "Public project created via script",
                "components_list": [],
                "flows_list": [],
            },
        )
        if create_project_resp.status_code != 201:
            print(f"Failed to create project {project_name}: {create_project_resp.text}")
            continue
        project_id = create_project_resp.json().get("id")
        print(f"Created project {project_name} with ID: {project_id}")

        # Refresh projects list
        projects_resp = requests.get(f"{LANGFLOW_URL}/api/v1/projects/", headers=api_headers)
        projects = projects_resp.json() if projects_resp.status_code == 201 else []
    else:
        print(f"Public project already exists: {project_name} (ID: {project_id})")

    # Upload flows in project
    for flow_file in glob.glob(os.path.join(project_dir, "*.json")):
        print(f"Uploading flow: {flow_file} to project {project_name}")
        with open(flow_file, "rb") as f:
            upload_resp = requests.post(
                f"{LANGFLOW_URL}/api/v1/flows/upload/?folder_id={project_id}",
                headers=api_headers,
                files={"file": (os.path.basename(flow_file), f, "application/json")},
            )
        if upload_resp.status_code != 201:
            print(f"Failed to upload {flow_file}: {upload_resp.text}")
        else:
            print(f"Done: {flow_file}")

print("All public flows uploaded successfully!")
