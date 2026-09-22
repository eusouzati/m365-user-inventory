import asyncio
import csv
import io
import logging
import time
from datetime import datetime
from pathlib import Path

from azure.identity.aio import ClientSecretCredential
from dotenv import dotenv_values
from kiota_abstractions.api_error import APIError
from kiota_abstractions.base_request_configuration import RequestConfiguration
from msgraph import GraphServiceClient
from msgraph.generated.users.users_request_builder import UsersRequestBuilder


def configure_logging(log_path):
    log_path.parent.mkdir(parents=True, exist_ok=True)

    logger = logging.getLogger("m365_user_inventory")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()

    handler = logging.FileHandler(
        log_path,
        encoding="utf-8",
    )
    handler.setFormatter(
        logging.Formatter(
            "%(asctime)s | %(levelname)s | %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
    )
    logger.addHandler(handler)

    return logger


async def fetch_all_users(
    graph_client,
    request_configuration,
    logger,
):
    all_users = []
    page_number = 1

    response = await graph_client.users.get(
        request_configuration=request_configuration
    )

    while response is not None:
        page_users = response.value or []
        all_users.extend(page_users)

        logger.info(
            "Page %s retrieved: %s users",
            page_number,
            len(page_users),
        )

        next_link = response.odata_next_link

        if not next_link:
            break

        page_number += 1
        response = await graph_client.users.with_url(next_link).get()

    return all_users


def build_csv_bytes(users):
    sorted_users = sorted(
        users,
        key=lambda user: (user.display_name or "").casefold(),
    )

    csv_file = io.StringIO(newline="")
    writer = csv.writer(csv_file, delimiter=";")

    writer.writerow(
        [
            "display_name",
            "user_principal_name",
            "email",
            "department",
            "job_title",
            "account_enabled",
        ]
    )

    for user in sorted_users:
        account_enabled = (
            user.account_enabled
            if user.account_enabled is not None
            else ""
        )

        writer.writerow(
            [
                user.display_name or "",
                user.user_principal_name or "",
                user.mail or "",
                user.department or "",
                user.job_title or "",
                account_enabled,
            ]
        )

    return csv_file.getvalue().encode("utf-8-sig")


def write_csv(output_path, users):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(build_csv_bytes(users))


def build_users_request_configuration():
    query_params = (
        UsersRequestBuilder.UsersRequestBuilderGetQueryParameters(
            select=[
                "displayName",
                "userPrincipalName",
                "mail",
                "department",
                "jobTitle",
                "accountEnabled",
            ],
            top=100,
        )
    )

    return RequestConfiguration(query_parameters=query_params)


async def main():
    base_path = Path(__file__).resolve().parent.parent
    env_path = base_path / ".env"
    output_path = base_path / "output" / "m365_users.csv"
    log_path = base_path / "logs" / "m365_inventory.log"

    logger = configure_logging(log_path)
    started_at = datetime.now().astimezone()
    started_counter = time.perf_counter()
    credential = None

    logger.info(
        "Execution started at %s",
        started_at.isoformat(timespec="seconds"),
    )

    try:
        config = dotenv_values(env_path)

        tenant_id = config.get("TENANT_ID")
        client_id = config.get("CLIENT_ID")
        client_secret = config.get("CLIENT_SECRET")

        if not tenant_id or not client_id or not client_secret:
            raise ValueError(
                "Credentials were not found in the .env file"
            )

        request_configuration = build_users_request_configuration()

        credential = ClientSecretCredential(
            tenant_id=tenant_id,
            client_id=client_id,
            client_secret=client_secret,
        )

        graph_client = GraphServiceClient(
            credentials=credential,
            scopes=["https://graph.microsoft.com/.default"],
        )

        users = await fetch_all_users(
            graph_client,
            request_configuration,
            logger,
        )

        write_csv(output_path, users)

        logger.info("Users exported: %s", len(users))
        logger.info("File created: %s", output_path)

        print(f"Users exported: {len(users)}")
        print(f"File created: {output_path}")
        print(f"Log created: {log_path}")

        return 0

    except PermissionError:
        message = (
            "Close m365_users.csv in Excel and run the script again."
        )
        logger.error(message)
        print(f"ERROR: {message}")
        return 1

    except APIError as exc:
        logger.exception("Microsoft Graph request failed: %s", exc)
        print(
            "ERROR: Microsoft Graph request failed. "
            f"See the log file: {log_path}"
        )
        return 1

    except Exception as exc:
        logger.exception("Unexpected error: %s", exc)
        print(f"ERROR: {exc}")
        print(f"See the log file: {log_path}")
        return 1

    finally:
        if credential is not None:
            await credential.close()

        duration = time.perf_counter() - started_counter
        finished_at = datetime.now().astimezone()

        logger.info(
            "Execution finished at %s | Duration: %.2f seconds",
            finished_at.isoformat(timespec="seconds"),
            duration,
        )


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
