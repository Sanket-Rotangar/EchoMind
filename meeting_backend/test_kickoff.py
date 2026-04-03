import requests
import time
import config
import argparse

def main():
    parser = argparse.ArgumentParser(description="Kick off meeting processing pipeline")
    parser.add_argument("--path", required=True, help="Audio file path in storage bucket")
    parser.add_argument("--user-id", default="local-test-user", help="User ID header value")
    parser.add_argument("--base-url", default="http://127.0.0.1:8000", help="Backend base URL")
    args = parser.parse_args()

    if not config.WEBHOOK_SECRET:
        print("Warning: WEBHOOK_SECRET is not set. Webhook verification may fail later.")

    url = f"{args.base_url}/api/meetings/process"
    headers = {
        "Content-Type": "application/json",
        "x-user-id": args.user_id,
    }
    body = {"path": args.path}

    response = requests.post(url, headers=headers, json=body, timeout=30)
    print(f"Trigger Response: {response.status_code}")
    try:
        print(response.json())
    except ValueError:
        print(response.text)

    time.sleep(1)
    print("Pipeline kickoff request completed.")


if __name__ == "__main__":
    main()
