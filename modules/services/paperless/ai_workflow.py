from django.db import transaction

from documents.models import Workflow, WorkflowAction, WorkflowTrigger


with transaction.atomic():
    workflow, _ = Workflow.objects.update_or_create(
        name="Apply AI suggestions after consumption",
        defaults={"enabled": True},
    )
    trigger, _ = workflow.triggers.get_or_create(
        type=WorkflowTrigger.WorkflowTriggerType.DOCUMENT_ADDED,
    )
    action, _ = workflow.actions.update_or_create(
        type=WorkflowAction.WorkflowActionType.APPLY_AI_SUGGESTIONS,
        defaults={
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
