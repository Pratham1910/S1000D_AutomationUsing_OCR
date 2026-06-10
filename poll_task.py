import requests, time, json, os

url_upload = "http://127.0.0.1:8000/api/v1/tasks/upload"
filepath = "examples/source/code.png"

with open(filepath, "rb") as f:
    r = requests.post(url_upload, files={"file": f}, timeout=30)
r.raise_for_status()
task_id = r.json()["data"]["task_id"]
print(f"Task ID: {task_id}")

url_status = f"http://127.0.0.1:8000/api/v1/tasks/{task_id}"
snapshot_printed = False
start_time = time.time()
result = None

while time.time() - start_time < 90:
    r = requests.get(url_status, timeout=10)
    data = r.json()["data"]
    
    if not snapshot_printed and data.get("processed_pages") is not None:
        fields = ["processed_pages", "total_pages", "batch_index", "layout_count"]
        print("Snapshot: " + json.dumps({f: data.get(f) for f in fields}))
        snapshot_printed = True
        
    if data.get("status") in ("completed", "failed", "cancelled"):
        result = data
        break
    time.sleep(0.5)

if result:
    print(f"Status: {result.get('status')}")
    print(f"PackageZipPath: {result.get('package_zip_path')}")
else:
    print("Timeout or no result.")
