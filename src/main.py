import asyncio
import csv
from pathlib import Path

from azure.identity.aio import ClientSecretCredential
from dotenv import dotenv_values
from msgraph import GraphServiceClient
from msgraph.generated.users.users_request_builder import UsersRequestBuilder
from kiota_abstractions.base_request_configuration import RequestConfiguration


async def main():
    base_path = Path(__file__).resolve().parent.parent
    env_path = base_path / ".env"
    output_path = base_path / "output" / "m365_users.csv"

    config = dotenv_values(env_path)

    tenant_id = config.get("TENANT_ID")
    client_id = config.get("CLIENT_ID")
    client_secret = config.get("CLIENT_SECRET")

    if not tenant_id or not client_id or not client_secret:
        raise ValueError("Credentials were not found in the .env file")

    credential = ClientSecretCredential(
        tenant_id=tenant_id,
        client_id=client_id,
        client_secret=client_secret,
    )

    scopes = ["https://graph.microsoft.com/.default"]

    graph_client = GraphServiceClient(
        credentials=credential,
        scopes=scopes,
    )

    query_params = (
        UsersRequestBuilder.UsersRequestBuilderGetQueryParameters(
            select=[
                "displayName",
                "userPrincipalName",
                "mail",
                "department",
                "jobTitle",
                "accountEnabled",
            ]
        )
    )

    request_configuration = RequestConfiguration(
        query_parameters=query_params
    )

    users = await graph_client.users.get(
        request_configuration=request_configuration
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(
        output_path,
        "w",
        newline="",
        encoding="utf-8-sig",
    ) as csv_file:

        writer = csv.writer(csv_file)

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

        for user in users.value:
            writer.writerow(
                [
                    user.display_name or "",
                    user.user_principal_name or "",
                    user.mail or "",
                    user.department or "",
                    user.job_title or "",
                    user.account_enabled,
                ]
            )

    print(f"Users exported: {len(users.value)}")
    print(f"File created: {output_path}")

    await credential.close()


if __name__ == "__main__":
    asyncio.run(main())