"""Client for the shipping service's order webhook."""
import json
import os
import urllib.request


def notify(order_id, total):
    body = json.dumps({"order_id": order_id, "total": str(total)}).encode()
    request = urllib.request.Request(
        os.environ["WEBHOOK_URL"],
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        response.read()
