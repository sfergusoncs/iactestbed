import os
import logging
from flask import Flask, render_template_string
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from azure.containerregistry import ContainerRegistryClient
import pyodbc
import redis

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

app = Flask(__name__)
credential = DefaultAzureCredential()

HTML = """
<!DOCTYPE html>
<html>
<head>
  <title>Infrastructure Health Check</title>
  <style>
    body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee; display: flex; justify-content: center; padding: 40px; }
    .card { background: #16213e; border-radius: 12px; padding: 30px; width: 480px; box-shadow: 0 4px 20px rgba(0,0,0,0.4); }
    h1 { font-size: 1.3rem; margin-bottom: 24px; color: #a8b2d8; letter-spacing: 1px; text-transform: uppercase; }
    .service { display: flex; justify-content: space-between; align-items: center; padding: 12px 0; border-bottom: 1px solid #0f3460; }
    .service:last-child { border-bottom: none; }
    .name { font-size: 0.95rem; }
    .badge { padding: 4px 14px; border-radius: 20px; font-size: 0.8rem; font-weight: bold; }
    .ok   { background: #1a4731; color: #4ade80; }
    .fail { background: #4a1a1a; color: #f87171; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Infrastructure Health Check</h1>
    {% for svc in services %}
    <div class="service">
      <span class="name">{{ svc.name }}</span>
      <span class="badge {{ 'ok' if svc.ok else 'fail' }}">{{ 'Connected' if svc.ok else 'Failed' }}</span>
    </div>
    {% endfor %}
  </div>
</body>
</html>
"""

def check_sql():
    try:
        server   = os.environ["SQL_SERVER"]
        database = os.environ["SQL_DATABASE"]
        username = os.environ["SQL_USERNAME"]
        password = os.environ["SQL_PASSWORD"]
        conn_str = (
            f"Driver={{ODBC Driver 18 for SQL Server}};"
            f"Server={server};Database={database};"
            f"UID={username};PWD={password};"
            f"TrustServerCertificate=yes;"
        )
        conn = pyodbc.connect(conn_str)
        conn.close()
        return True
    except Exception as e:
        log.error("SQL check failed: %s", e)
        return False

def check_redis():
    host     = os.environ["REDIS_HOST"]
    port     = int(os.environ.get("REDIS_PORT", 10000))
    clientid = os.environ["AZURE_CLIENT_ID"]
    try:
        log.info("Redis: acquiring token...")
        token = credential.get_token("https://redis.azure.com/.default").token
        log.info("Redis: token acquired, connecting to %s:%s", host, port)
        r = redis.StrictRedis(
            host=host, port=port, ssl=True,
            username=clientid, password=token
        )
        log.info("Redis: sending ping...")
        r.ping()
        log.info("Redis: ping succeeded")
        return True
    except Exception as e:
        log.error("Redis check failed at %s:%s — %s: %s", host, port, type(e).__name__, e)
        return False

def check_blob(env_var):
    try:
        account_url = os.environ[env_var]
        client = BlobServiceClient(account_url=account_url, credential=credential)
        next(iter(client.list_containers()), None)
        return True
    except Exception as e:
        log.error("Blob check failed (%s): %s", env_var, e)
        return False

def check_acr():
    try:
        acr_url = os.environ["ACR_URL"]
        client = ContainerRegistryClient(endpoint=acr_url, credential=credential)
        next(iter(client.list_repository_names()), None)
        return True
    except Exception as e:
        log.error("ACR check failed: %s", e)
        return False

@app.route("/")
def index():
    services = [
        {"name": "Azure SQL",              "ok": check_sql()},
        {"name": "Azure Redis Cache",      "ok": check_redis()},
        {"name": "Blob Storage (App)",     "ok": check_blob("BLOB_APP_URL")},
        {"name": "Blob Storage (Vendor)",  "ok": check_blob("BLOB_VENDOR_URL")},
        {"name": "Container Registry",     "ok": check_acr()},
    ]
    return render_template_string(HTML, services=services)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)