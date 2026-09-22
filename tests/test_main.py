import asyncio
import csv
import logging
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from src.main import (
    build_csv_bytes,
    configure_logging,
    fetch_all_users,
    write_csv,
)


class FakePage:
    def __init__(self, users, next_link=None):
        self.value = users
        self.odata_next_link = next_link


class FakeNextPageBuilder:
    def __init__(self, page):
        self.page = page

    async def get(self):
        return self.page


class FakeUsersBuilder:
    def __init__(self, pages):
        self.pages = pages
        self.request_configuration = None
        self.requested_links = []

    async def get(self, request_configuration=None):
        self.request_configuration = request_configuration
        return self.pages[0]

    def with_url(self, raw_url):
        self.requested_links.append(raw_url)
        page_index = len(self.requested_links)
        return FakeNextPageBuilder(self.pages[page_index])


def make_user(
    display_name,
    upn,
    mail=None,
    department=None,
    job_title=None,
    account_enabled=True,
):
    return SimpleNamespace(
        display_name=display_name,
        user_principal_name=upn,
        mail=mail,
        department=department,
        job_title=job_title,
        account_enabled=account_enabled,
    )


class FetchAllUsersTests(unittest.TestCase):
    def test_fetch_all_users_reads_every_page(self):
        pages = [
            FakePage(
                [make_user("Ana", "ana@example.com")],
                "next-page-2",
            ),
            FakePage(
                [make_user("Bruno", "bruno@example.com")],
                "next-page-3",
            ),
            FakePage(
                [make_user("Carla", "carla@example.com")],
            ),
        ]
        users_builder = FakeUsersBuilder(pages)
        graph_client = SimpleNamespace(users=users_builder)
        request_configuration = object()
        logger = logging.getLogger("pagination_test")

        users = asyncio.run(
            fetch_all_users(
                graph_client,
                request_configuration,
                logger,
            )
        )

        self.assertEqual(len(users), 3)
        self.assertIs(
            users_builder.request_configuration,
            request_configuration,
        )
        self.assertEqual(
            users_builder.requested_links,
            ["next-page-2", "next-page-3"],
        )


class CsvExportTests(unittest.TestCase):
    def test_build_csv_bytes_adds_excel_bom(self):
        users = [make_user("Ana", "ana@example.com")]

        csv_content = build_csv_bytes(users)

        self.assertTrue(csv_content.startswith(b"\xef\xbb\xbf"))
        self.assertIn(b"ana@example.com", csv_content)

    def test_write_csv_uses_semicolon_and_sorts_users(self):
        users = [
            make_user(
                "Zulu",
                "zulu@example.com",
                department="IT",
                job_title="Analyst",
            ),
            make_user(
                "Ana",
                "ana@example.com",
                mail="ana@example.com",
                department="HR",
                job_title="Manager",
                account_enabled=False,
            ),
        ]

        with tempfile.TemporaryDirectory() as temp_directory:
            output_path = Path(temp_directory) / "m365_users.csv"
            write_csv(output_path, users)

            with output_path.open(
                encoding="utf-8-sig",
                newline="",
            ) as csv_file:
                rows = list(csv.reader(csv_file, delimiter=";"))

        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0][0], "display_name")
        self.assertEqual(rows[1][0], "Ana")
        self.assertEqual(rows[2][0], "Zulu")
        self.assertEqual(rows[1][5], "False")

    def test_write_csv_leaves_unknown_status_empty(self):
        users = [
            make_user(
                "Unknown",
                "unknown@example.com",
                account_enabled=None,
            )
        ]

        with tempfile.TemporaryDirectory() as temp_directory:
            output_path = Path(temp_directory) / "m365_users.csv"
            write_csv(output_path, users)

            with output_path.open(
                encoding="utf-8-sig",
                newline="",
            ) as csv_file:
                rows = list(csv.reader(csv_file, delimiter=";"))

        self.assertEqual(rows[1][5], "")


class LoggingTests(unittest.TestCase):
    def test_configure_logging_creates_log_file(self):
        with tempfile.TemporaryDirectory() as temp_directory:
            log_path = Path(temp_directory) / "logs" / "inventory.log"
            logger = configure_logging(log_path)
            logger.info("test message")

            for handler in logger.handlers:
                handler.flush()

            content = log_path.read_text(encoding="utf-8")

            for handler in logger.handlers:
                handler.close()
            logger.handlers.clear()

        self.assertIn("INFO | test message", content)


if __name__ == "__main__":
    unittest.main()
