from django.db import transaction

from documents.models import (
    CustomField,
    CustomFieldInstance,
    Document,
    Workflow,
    WorkflowAction,
    WorkflowTrigger,
)
from documents.workflows.custom_fields import populate_document_fields


with transaction.atomic():
    owner_field = CustomField.objects.get(name="Owner")
    due_field = CustomField.objects.get(name="Payment Due Date")
    workflow, _ = Workflow.objects.update_or_create(
        name="Apply AI suggestions after consumption",
        defaults={"enabled": True},
    )
    trigger, _ = workflow.triggers.get_or_create(
        type=WorkflowTrigger.WorkflowTriggerType.DOCUMENT_ADDED,
    )
    assignment, _ = workflow.actions.get_or_create(
        type=WorkflowAction.WorkflowActionType.ASSIGNMENT,
        defaults={"order": 0},
    )
    assignment.assign_custom_fields.set([owner_field, due_field])
    action, _ = workflow.actions.update_or_create(
        type=WorkflowAction.WorkflowActionType.APPLY_AI_SUGGESTIONS,
        defaults={
            "order": 1,
            "ai_suggestion_fields": [
                WorkflowAction.AISuggestionField.TITLE,
                WorkflowAction.AISuggestionField.TAGS,
                WorkflowAction.AISuggestionField.CORRESPONDENT,
                WorkflowAction.AISuggestionField.DOCUMENT_TYPE,
                WorkflowAction.AISuggestionField.STORAGE_PATH,
                WorkflowAction.AISuggestionField.CREATED,
            ],
            "ai_create_missing": False,
            # Consumed documents already have a title, date and classifier matches.
            # Suggested tags are additive, so todo/inbox flags remain for review.
            "ai_overwrite_existing": True,
        },
    )


for document in Document.objects.iterator():
    owner, owner_created = CustomFieldInstance.objects.get_or_create(
        document=document, field=owner_field,
    )
    _, due_created = CustomFieldInstance.objects.get_or_create(
        document=document, field=due_field,
    )
    if owner_created or due_created or not owner.value_select:
        populate_document_fields.delay(document.pk)
