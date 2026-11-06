import builtins
import importlib.util
import json
import unittest
from contextlib import nullcontext
from datetime import date
from pathlib import Path
from unittest.mock import MagicMock, patch

from pydantic import ValidationError


class DocumentFieldsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        modules = {
            name: MagicMock()
            for name in [
                "celery", "django", "django.db", "django.db.models",
                "llama_index", "llama_index.core", "llama_index.core.llms",
                "documents", "documents.caching", "documents.models",
                "documents.tasks", "paperless", "paperless.config",
                "paperless_ai", "paperless_ai.client", "paperless_ai.db",
                "paperless_ai.exceptions", "paperless_ai.indexing",
            ]
        }
        modules["celery"].shared_task.side_effect = lambda **kwargs: lambda fn: fn
        modules["paperless_ai.exceptions"].LLMTimeoutError = TimeoutError
        modules["paperless_ai.db"].db_connection_released = nullcontext
        spec = importlib.util.spec_from_file_location(
            "document_custom_fields", Path(__file__).with_name("custom_fields.py"),
        )
        cls.module = importlib.util.module_from_spec(spec)
        dependencies = patch.dict("sys.modules", modules)
        dependencies.start()
        cls.addClassCleanup(dependencies.stop)
        spec.loader.exec_module(cls.module)
        cls.dependencies = modules

    def setUp(self):
        self.module.CustomField.reset_mock()
        self.module.CustomFieldInstance.reset_mock()
        self.dependencies["paperless_ai.client"].AIClient.reset_mock()
        self.module.Document.reset_mock()
        self.module.clear_document_caches.reset_mock()
        self.module.truncate_content.reset_mock()
        self.module.truncate_content.side_effect = lambda content, **kwargs: content
        self.module.AIConfig.return_value.ai_enabled = True
        self.module.AIConfig.return_value.llm_context_size = 196608
        self.module.AIConfig.return_value.llm_embedding_chunk_size = 1024
        self.dependencies["paperless_ai.client"].LLM_SYSTEM_PROMPT = "System instructions"
        self.document = self.module.Document.objects.get.return_value
        self.document.document_type = None
        self.document.content = "Invoice addressed to Sophie. Pay by 2026-11-15."
        owner_field = MagicMock()
        owner_field.extra_data = {"select_options": [
            {"label": "Sophie", "id": "sophie-option"},
            {"label": "Jacob", "id": "jacob-option"},
            {"label": "Shared Bears", "id": "shared-option"},
        ]}
        self.module.CustomField.objects.get.side_effect = [owner_field, MagicMock()]
        self.owner = MagicMock(pk=1, value_select=None)
        self.due = MagicMock(pk=2, value_date=None)
        self.module.CustomFieldInstance.objects.get_or_create.side_effect = [
            (self.owner, True), (self.due, True),
        ]
        self.client = self.dependencies["paperless_ai.client"].AIClient.return_value
        self.client._normalize_errors.side_effect = lambda: nullcontext()

    def test_task_discovery_does_not_import_ai_libraries(self):
        original_import = builtins.__import__

        def check_import(name, *args, **kwargs):
            if name.startswith("llama_index") or name == "paperless_ai.client":
                self.fail(f"Task discovery imported {name}")
            return original_import(name, *args, **kwargs)

        spec = importlib.util.spec_from_file_location(
            "document_custom_fields_lazy", Path(__file__).with_name("custom_fields.py"),
        )
        with patch("builtins.__import__", side_effect=check_import):
            spec.loader.exec_module(importlib.util.module_from_spec(spec))

    def test_extraction_budgets_for_instructions_and_full_document(self):
        self.document.content = "Invoice " * 1000 + "Pay by 2026-11-15."
        self.run_extraction()
        args, kwargs = self.module.truncate_content.call_args
        self.assertEqual(args, (self.document.content,))
        self.assertEqual(kwargs["context_size"], 196608)
        self.assertEqual(kwargs["chunk_size"], 1024)
        self.assertIn("System instructions", kwargs["prompt"])
        self.assertIn("Extract the addressee", kwargs["prompt"])
        self.assertNotIn(self.document.content, kwargs["prompt"])
        prompt = self.dependencies["llama_index.core.llms"].ChatMessage.call_args.kwargs["content"]
        self.assertTrue(prompt.endswith(self.document.content))

    def test_coupon_budget_includes_coupon_instructions(self):
        self.prepare_coupon()
        self.run_extraction(
            requires_payment=False, coupon_expiry_date=None, coupon_code=None,
        )
        prompt = self.module.truncate_content.call_args.kwargs["prompt"]
        self.assertIn("expiry date and redemption code too", prompt)

    def run_extraction(self, recipient="Sophie", requires_payment=True, due="2026-11-15", **extra):
        if isinstance(due, str):
            due = self.date_value(due)
        if isinstance(extra.get("coupon_expiry_date"), str):
            extra["coupon_expiry_date"] = self.date_value(extra["coupon_expiry_date"])
        self.client.llm.chat.return_value.message.content = json.dumps({
            "recipient": recipient,
            "requires_payment": requires_payment,
            "payment_due_date": due,
            **extra,
        })
        self.module.populate_document_fields(42)

    def date_value(self, value, text=None, offset_days=0, terms=None):
        return {
            "text": text if text is not None else value,
            "value": value,
            "offset_days": offset_days,
            "terms": terms,
        }

    def prepare_coupon(self):
        self.document.content += " Coupon valid until 2026-12-31. Code Save-20!"
        self.document.document_type = MagicMock()
        self.document.document_type.name = "Coupons"
        owner_field = self.module.CustomField.objects.get.side_effect
        self.module.CustomField.objects.get.side_effect = [
            next(owner_field), next(owner_field), MagicMock(), MagicMock(),
        ]
        self.expiry = MagicMock(pk=3, value_date=None)
        self.code = MagicMock(pk=4, value_text=None)
        self.module.CustomFieldInstance.objects.get_or_create.side_effect = [
            (self.owner, False), (self.due, False),
            (self.expiry, True), (self.code, True),
        ]

    def test_coupon_extracts_date_and_exact_code_with_owner_already_filled(self):
        self.prepare_coupon()
        self.owner.value_select = "sophie-option"
        self.due.value_date = date(2026, 11, 15)
        self.run_extraction(
            requires_payment=False, coupon_expiry_date="2026-12-31",
            coupon_code="Save-20!",
        )
        self.assertEqual(self.module.CustomFieldInstance.objects.get_or_create.call_count, 4)
        self.module.CustomField.objects.get.assert_any_call(name="Coupon Expiry Date")
        self.module.CustomField.objects.get.assert_any_call(name="Coupon Code")
        self.module.CustomFieldInstance.objects.filter.assert_any_call(
            pk=3, value_date__isnull=True,
        )
        self.module.CustomFieldInstance.objects.filter.return_value.update.assert_called_once_with(
            value_date=date(2026, 12, 31),
        )
        self.module.CustomFieldInstance.objects.filter.return_value.filter.return_value.update.assert_any_call(
            value_text="Save-20!",
        )
        schema = self.client.llm.chat.call_args.kwargs["format"]
        self.assertIn("coupon_expiry_date", schema["properties"])
        self.assertIn("coupon_code", schema["properties"])

    def test_coupon_unknown_values_stay_blank(self):
        self.prepare_coupon()
        self.run_extraction(
            requires_payment=False, coupon_expiry_date=None, coupon_code=None,
        )
        self.module.CustomFieldInstance.objects.filter.return_value.update.assert_not_called()
        self.module.CustomFieldInstance.objects.filter.return_value.filter.return_value.update.assert_called_once_with(
            value_select="sophie-option",
        )

    def test_filled_coupon_fields_skip_extraction(self):
        self.prepare_coupon()
        self.owner.value_select = "sophie-option"
        self.due.value_date = date(2026, 11, 15)
        self.expiry.value_date = date(2026, 12, 31)
        self.code.value_text = "MANUAL"
        self.run_extraction()
        self.client.llm.chat.assert_not_called()
        self.module.CustomFieldInstance.objects.filter.assert_not_called()

    def test_other_types_do_not_attach_or_request_coupon_fields(self):
        self.document.document_type = MagicMock()
        self.document.document_type.name = "Invoices"
        self.run_extraction()
        self.assertEqual(self.module.CustomFieldInstance.objects.get_or_create.call_count, 2)
        schema = self.client.llm.chat.call_args.kwargs["format"]
        self.assertNotIn("coupon_code", schema["properties"])

    def test_adds_both_fields_and_extracts_each_recipient(self):
        for recipient, option in [("Sophie", "sophie-option"), ("Jacob", "jacob-option")]:
            with self.subTest(recipient=recipient):
                self.setUp()
                self.run_extraction(recipient=recipient)
                self.assertEqual(self.module.CustomFieldInstance.objects.get_or_create.call_count, 2)
                self.module.CustomFieldInstance.objects.filter.return_value.filter.return_value.update.assert_called_once_with(
                    value_select=option,
                )
                self.module.CustomFieldInstance.objects.filter.return_value.update.assert_called_once_with(
                    value_date=date(2026, 11, 15),
                )

    def test_non_payment_document_keeps_due_date_blank(self):
        self.run_extraction(requires_payment=False)
        self.module.CustomFieldInstance.objects.filter.return_value.update.assert_not_called()

    def test_unknown_deadline_keeps_due_date_blank(self):
        self.run_extraction(due=None)
        self.module.CustomFieldInstance.objects.filter.return_value.update.assert_not_called()

    def test_payment_year_is_read_from_printed_date(self):
        for printed in ["2026-11-15", "15.11.2026", "15/11/2026", "15-11-2026"]:
            with self.subTest(printed=printed):
                self.setUp()
                self.document.content = f"Invoice for Sophie. Pay by {printed}."
                self.run_extraction(due=self.date_value("2024-11-15", text=printed))
                self.module.CustomFieldInstance.objects.filter.return_value.update.assert_called_once_with(
                    value_date=date(2026, 11, 15),
                )

    def test_coupon_year_is_read_from_printed_date(self):
        self.prepare_coupon()
        self.run_extraction(
            requires_payment=False,
            coupon_expiry_date=self.date_value("2024-12-31", text="2026-12-31"),
            coupon_code="Save-20!",
        )
        self.module.CustomFieldInstance.objects.filter.return_value.update.assert_called_once_with(
            value_date=date(2026, 12, 31),
        )

    def test_unsupported_dates_stay_blank(self):
        for printed, value, content in [
            ("2024-11-15", "2024-11-15", "Pay by 2026-11-15."),
            ("15.11", "2026-11-15", "Pay by 15.11."),
            ("15.11.26", "2026-11-15", "Pay by 15.11.26."),
            ("15 November 2026", "2024-11-15", "Pay by 15 November 2026."),
            ("31.02.2026", "2026-02-28", "Pay by 31.02.2026."),
            ("2026", "2026-11-15", "Copyright 2026."),
            ("", "2026-11-15", "No deadline."),
        ]:
            with self.subTest(printed=printed):
                self.setUp()
                self.document.content = content
                self.run_extraction(due=self.date_value(value, text=printed))
                self.module.CustomFieldInstance.objects.filter.return_value.update.assert_not_called()

    def test_unsupported_coupon_date_preserves_owner_and_code(self):
        self.prepare_coupon()
        self.run_extraction(
            requires_payment=False,
            coupon_expiry_date=self.date_value("2024-12-31"),
            coupon_code="Save-20!",
        )
        self.module.CustomFieldInstance.objects.filter.return_value.update.assert_not_called()
        self.module.CustomFieldInstance.objects.filter.return_value.filter.return_value.update.assert_any_call(
            value_select="sophie-option",
        )
        self.module.CustomFieldInstance.objects.filter.return_value.filter.return_value.update.assert_any_call(
            value_text="Save-20!",
        )

    def test_historical_named_date_and_ocr_whitespace(self):
        self.document.content = "Pay by 15.\n November 2021."
        self.run_extraction(due=self.date_value("2021-11-15", text="15. November 2021"))
        self.module.CustomFieldInstance.objects.filter.return_value.update.assert_called_once_with(
            value_date=date(2021, 11, 15),
        )

    def test_relative_payment_deadline_crosses_year_in_python(self):
        self.document.content = "Invoice date 20.12.2025. Pay within 30 days."
        self.run_extraction(due=self.date_value(
            "2024-12-20", text="20.12.2025", offset_days=30, terms="Pay within 30 days",
        ))
        self.module.CustomFieldInstance.objects.filter.return_value.update.assert_called_once_with(
            value_date=date(2026, 1, 19),
        )

    def test_relative_coupon_expiry_crosses_leap_day_in_python(self):
        self.prepare_coupon()
        self.document.content = "Valid from 2024-02-28 for 2 days. Code Save-20!"
        self.run_extraction(
            requires_payment=False,
            coupon_expiry_date=self.date_value(
                "2024-02-28", offset_days=2, terms="for 2 days",
            ),
            coupon_code="Save-20!",
        )
        self.module.CustomFieldInstance.objects.filter.return_value.update.assert_called_once_with(
            value_date=date(2024, 3, 1),
        )

    def test_relative_deadline_requires_quoted_days(self):
        for terms in [None, "Pay within 30 days", "Pay within 14 days", "30 months", "Invoice 30"]:
            with self.subTest(terms=terms):
                self.setUp()
                self.document.content = "Invoice 30, date 2026-11-15. Pay within 14 days. Valid for 30 months."
                self.run_extraction(due=self.date_value(
                    "2026-11-15", offset_days=30, terms=terms,
                ))
                self.module.CustomFieldInstance.objects.filter.return_value.update.assert_not_called()

    def test_relative_deadline_in_ocr_languages(self):
        for terms in ["30 days", "30 Tage", "30 Tagen", "30 giorni", "30 päivää", "30 päivän"]:
            with self.subTest(terms=terms):
                self.setUp()
                self.document.content = f"2026-11-15. {terms}."
                self.run_extraction(due=self.date_value(
                    "2026-11-15", offset_days=30, terms=terms,
                ))
                self.module.CustomFieldInstance.objects.filter.return_value.update.assert_called_once_with(
                    value_date=date(2026, 12, 15),
                )

    def test_shared_recipient(self):
        self.run_extraction(recipient="Shared Bears")
        self.module.CustomFieldInstance.objects.filter.return_value.filter.return_value.update.assert_called_once_with(
            value_select="shared-option",
        )

    def test_empty_document_uses_shared_without_calling_llm(self):
        self.document.content = "   "
        self.run_extraction()
        self.client.llm.chat.assert_not_called()
        self.module.CustomFieldInstance.objects.filter.return_value.filter.return_value.update.assert_called_once_with(
            value_select="shared-option",
        )

    def test_filled_fields_are_preserved_without_calling_llm(self):
        self.owner.value_select = "jacob-option"
        self.due.value_date = date(2026, 12, 1)
        self.run_extraction()
        self.client.llm.chat.assert_not_called()
        self.module.CustomFieldInstance.objects.filter.assert_not_called()

    def test_invalid_date_and_unknown_recipient_are_rejected(self):
        for overrides in [
            {"payment_due_date": self.date_value("2026-02-30")},
            {"recipient": "Someone"},
        ]:
            with self.subTest(overrides=overrides), self.assertRaises(ValidationError):
                self.module.DocumentFields.model_validate({
                    "recipient": "Sophie",
                    "requires_payment": True,
                    "payment_due_date": None,
                    **overrides,
                })


if __name__ == "__main__":
    unittest.main()
