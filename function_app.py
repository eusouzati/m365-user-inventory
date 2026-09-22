import logging
import os
import time
from datetime import datetime, timezone

import azure.functions as func
from azure.identity.aio import DefaultAzureCredential
from azure.storage.blob import ContentSettings
from azure.storage.blob.aio import BlobServiceClient
from msgraph import GraphServiceClient

from src.main import (
    build_csv_bytes,
    build_users_request_configuration,
    fetch_all_users,
)


app = func.FunctionApp()


def required_setting(name):
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Required setting is missing: {name}")
    return value


async def export_inventory_to_blob(logger):
    storage_account = required_setting("INVENTORY_STORAGE_ACCOUNT")
    container_name = os.getenv("INVENTORY_CONTAINER", "inventory")
    blob_name = os.getenv("INVENTORY_BLOB_NAME", "m365_users.csv")
    managed_identity_client_id = os.getenv("AZURE_CLIENT_ID")

    credential = DefaultAzureCredential(
        managed_identity_client_id=managed_identity_client_id
    )
    blob_service = BlobServiceClient(
        account_url=(
            f"https://{storage_account}.blob.core.windows.net"
        ),
        credential=credential,
    )

    try:
        graph_client = GraphServiceClient(
            credentials=credential,
            scopes=["https://graph.microsoft.com/.default"],
        )
        request_configuration = build_users_request_configuration()
        users = await fetch_all_users(
            graph_client,
            request_configuration,
            logger,
        )
        csv_content = build_csv_bytes(users)

        blob_client = blob_service.get_blob_client(
            container=container_name,
            blob=blob_name,
        )
        await blob_client.upload_blob(
            csv_content,
            overwrite=True,
            content_settings=ContentSettings(
                content_type="text/csv; charset=utf-8"
            ),
        )

        blob_url = (
            f"https://{storage_account}.blob.core.windows.net/"
            f"{container_name}/{blob_name}"
        )
        return len(users), blob_url
    finally:
        await blob_service.close()
        await credential.close()


@app.function_name(name="m365_inventory_timer")
@app.timer_trigger(
    schedule="%INVENTORY_SCHEDULE%",
    arg_name="timer",
    run_on_startup=False,
    use_monitor=True,
)
async def m365_inventory_timer(timer: func.TimerRequest) -> None:
    started_at = datetime.now(timezone.utc)
    started_counter = time.perf_counter()
    logger = logging.getLogger("m365_user_inventory")

    logger.info(
        "Execution started at %s",
        started_at.isoformat(timespec="seconds"),
    )

    if timer.past_due:
        logger.warning("Timer execution is past due")

    try:
        user_count, blob_url = await export_inventory_to_blob(logger)
        logger.info("Users exported: %s", user_count)
        logger.info("Blob updated: %s", blob_url)
    except Exception:
        logger.exception("Inventory execution failed")
        raise
    finally:
        duration = time.perf_counter() - started_counter
        logger.info("Execution duration: %.2f seconds", duration)
