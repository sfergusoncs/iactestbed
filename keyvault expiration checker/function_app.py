"""
Azure Function App: Key Vault secret expiration checker.

Runs on a timer trigger (default: once every 24 hours). Lists all secrets in a
configured Key Vault, checks each secret's expiration date, builds an HTML
status table, and emails it to a distribution list via Azure Communication
Services (ACS) Email ONLY when at least one secret expires within the
configured threshold (default 30 days).

Auth model: Managed Identity (DefaultAzureCredential) for both Key Vault and
ACS Email. No secrets or connection strings are stored in app settings.

Required app settings (see README.md):
    KEY_VAULT_URL           e.g. https://my-vault.vault.azure.net/
    ACS_ENDPOINT             e.g. https://my-acs-resource.communication.azure.com
    SENDER_ADDRESS           verified sender address from the ACS Email domain
    DISTRO_RECIPIENTS        comma-separated list of recipient addresses
    EXPIRY_THRESHOLD_DAYS    optional, default "30"
    TIMER_SCHEDULE           NCRONTAB expression, default "0 0 0 * * *" (daily, 00:00 UTC)

References (Microsoft Learn, current as of 2026-07-13):
    Timer trigger:      https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-timer
    Key Vault Secrets:  https://learn.microsoft.com/en-us/python/api/overview/azure/keyvault-secrets-readme
    ACS Email:          https://learn.microsoft.com/en-us/python/api/overview/azure/communication-email-readme
    DefaultAzureCredential: https://learn.microsoft.com/en-us/python/api/overview/azure/identity-readme
"""

import datetime
import logging
import os

import azure.functions as func
from azure.communication.email import EmailClient
from azure.core.exceptions import HttpResponseError, ResourceNotFoundError
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

app = func.FunctionApp()

DEFAULT_THRESHOLD_DAYS = 30
DEFAULT_SCHEDULE = "0 0 0 * * *"  # once every 24 hours, at 00:00 UTC


def _get_threshold_days() -> int:
    raw = os.environ.get("EXPIRY_THRESHOLD_DAYS", str(DEFAULT_THRESHOLD_DAYS))
    try:
        return int(raw)
    except ValueError:
        logging.warning(
            "EXPIRY_THRESHOLD_DAYS=%r is not an integer; falling back to %d",
            raw,
            DEFAULT_THRESHOLD_DAYS,
        )
        return DEFAULT_THRESHOLD_DAYS


def _collect_secret_status(vault_url: str, credential: DefaultAzureCredential):
    """Return a list of dicts: name, expires_on (datetime|None), days_remaining (int|None)."""
    client = SecretClient(vault_url=vault_url, credential=credential)
    now = datetime.datetime.now(datetime.timezone.utc)
    rows = []

    for secret_property in client.list_properties_of_secrets():
        if not secret_property.enabled:
            # Disabled secrets are not actionable; skip them from the report.
            continue

        expires_on = secret_property.expires_on  # tz-aware UTC datetime, or None
        days_remaining = None
        if expires_on is not None:
            days_remaining = (expires_on - now).days

        rows.append(
            {
                "name": secret_property.name,
                "expires_on": expires_on,
                "days_remaining": days_remaining,
            }
        )

    rows.sort(key=lambda r: (r["days_remaining"] is None, r["days_remaining"]))
    return rows


def _build_html_table(rows, threshold_days: int) -> str:
    header = (
        "<table style='border-collapse:collapse;font-family:Segoe UI,Arial,sans-serif;"
        "font-size:14px;'>"
        "<tr>"
        "<th style='border:1px solid #ccc;padding:8px;background:#f2f2f2;text-align:left;'>Secret Name</th>"
        "<th style='border:1px solid #ccc;padding:8px;background:#f2f2f2;text-align:left;'>Expiration Date (UTC)</th>"
        "<th style='border:1px solid #ccc;padding:8px;background:#f2f2f2;text-align:left;'>Days Remaining</th>"
        "</tr>"
    )

    body_rows = []
    for row in rows:
        if row["expires_on"] is None:
            bg_color = "#e0e0e0"  # neutral gray: no expiration set
            expires_str = "No expiration set"
            days_str = "N/A"
        elif row["days_remaining"] < threshold_days:
            bg_color = "#f4cccc"  # red
            expires_str = row["expires_on"].strftime("%Y-%m-%d")
            days_str = str(row["days_remaining"])
        else:
            bg_color = "#d9ead3"  # green
            expires_str = row["expires_on"].strftime("%Y-%m-%d")
            days_str = str(row["days_remaining"])

        body_rows.append(
            "<tr style='background:{bg}'>"
            "<td style='border:1px solid #ccc;padding:8px;'>{name}</td>"
            "<td style='border:1px solid #ccc;padding:8px;'>{expires}</td>"
            "<td style='border:1px solid #ccc;padding:8px;'>{days}</td>"
            "</tr>".format(
                bg=bg_color,
                name=row["name"],
                expires=expires_str,
                days=days_str,
            )
        )

    return header + "".join(body_rows) + "</table>"


def _send_email(html_table: str, expiring_count: int, threshold_days: int):
    acs_endpoint = os.environ["ACS_ENDPOINT"]
    sender_address = os.environ["SENDER_ADDRESS"]
    recipients_raw = os.environ["DISTRO_RECIPIENTS"]
    recipients = [addr.strip() for addr in recipients_raw.split(",") if addr.strip()]

    if not recipients:
        raise ValueError("DISTRO_RECIPIENTS app setting is empty or unset.")

    credential = DefaultAzureCredential()
    client = EmailClient(acs_endpoint, credential)

    run_date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    subject = f"[ACTION REQUIRED] {expiring_count} Key Vault secret(s) expiring within {threshold_days} days"

    html_body = (
        "<html><body>"
        f"<p>Key Vault secret expiration check run on {run_date} (UTC).</p>"
        f"<p>{expiring_count} secret(s) expire within {threshold_days} days. "
        "Full status below.</p>"
        f"{html_table}"
        "</body></html>"
    )
    plain_body = (
        f"Key Vault secret expiration check run on {run_date} (UTC). "
        f"{expiring_count} secret(s) expire within {threshold_days} days. "
        "View this email in an HTML-capable client for the full table."
    )

    message = {
        "content": {
            "subject": subject,
            "plainText": plain_body,
            "html": html_body,
        },
        "recipients": {
            "to": [{"address": addr} for addr in recipients],
        },
        "senderAddress": sender_address,
    }

    poller = client.begin_send(message)
    result = poller.result()
    logging.info("ACS Email send result: %s", result)


@app.function_name(name="KeyVaultExpiryCheck")
@app.timer_trigger(
    schedule="%TIMER_SCHEDULE%",
    arg_name="timer",
    run_on_startup=False,
    use_monitor=True,
)
def keyvault_expiry_check(timer: func.TimerRequest) -> None:
    if timer.past_due:
        logging.warning("Timer trigger is past due.")

    vault_url = os.environ["KEY_VAULT_URL"]
    threshold_days = _get_threshold_days()

    credential = DefaultAzureCredential()

    try:
        rows = _collect_secret_status(vault_url, credential)
    except (HttpResponseError, ResourceNotFoundError):
        logging.exception("Failed to read secret properties from Key Vault %s", vault_url)
        raise

    if not rows:
        logging.info("No enabled secrets found in %s. Nothing to report.", vault_url)
        return

    expiring_rows = [
        r for r in rows if r["days_remaining"] is not None and r["days_remaining"] < threshold_days
    ]

    logging.info(
        "Checked %d secret(s) in %s. %d expiring within %d days.",
        len(rows),
        vault_url,
        len(expiring_rows),
        threshold_days,
    )

    if not expiring_rows:
        # No action needed; no email sent this run.
        return

    html_table = _build_html_table(rows, threshold_days)

    try:
        _send_email(html_table, len(expiring_rows), threshold_days)
    except HttpResponseError:
        logging.exception("Failed to send expiration notification email via ACS Email.")
        raise
