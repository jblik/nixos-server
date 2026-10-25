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
        self.module.AIClient.reset_mock()
        self.module.Document.reset_mock()
        self.module.clear_document_caches.reset_mock()
        self.module.AIConfig.return_value.ai_enabled = True
        self.document = self.module.Document.objects.get.return_value
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
        self.client = self.module.AIClient.return_value
        self.client._normalize_errors.side_effect = lambda: nullcontext()

    def run_extraction(self, recipient="Sophie", requires_payment=True, due="2026-11-15"):
        self.client.llm.chat.return_value.message.content = json.dumps({
            "recipient": recipient,
            "requires_payment": requires_payment,
            "payment_due_date": due,
        })
        self.module.populate_document_fields(42)

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
        for overrides in [{"payment_due_date": "2026-02-30"}, {"recipient": "Someone"}]:
            with self.subTest(overrides=overrides), self.assertRaises(ValidationError):
                self.module.DocumentFields.model_validate({
                    "recipient": "Sophie",
                    "requires_payment": True,
                    "payment_due_date": None,
                    **overrides,
                })


if __name__ == "__main__":
    unittest.main()
