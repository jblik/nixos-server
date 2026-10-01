import os
import re
import sys
import requests

PAPERLESS_URL = os.environ["POST_CONSUME_API_URL"]
TOKEN = os.environ["POST_CONSUME_API_TOKEN"]

PAID_TAG_ID = 7
NOT_PAID_TAG_ID = 8
TODO_TAG_ID = 9
INVOICE_DOCTYPE_ID = 6
PAYMENT_DUE_FIELD_ID = 4
OWNER_FIELD_ID = 5

# Keys are exact Paperless usernames (case-sensitive), or None as fallback
# when the document has no owner or the username isn't mapped.
OWNER_USERNAME_TO_OPTION_ID = {
    "Sophie": "FPlDtkY55tHygiMG",
    "Jacob":  "iFxTrQivKeLOjNN8",
    None:     "1tCGjQNyH2N873hi",  # Shared Bears — fallback for unowned/unmapped docs
}

TIMEOUT = 10


def fetch_document(document_id, headers):
    resp = requests.get(
        f"{PAPERLESS_URL}/api/documents/{document_id}/",
        headers=headers,
        timeout=TIMEOUT,
    )
    resp.raise_for_status()
    return resp.json()


def patch_custom_fields(document_id, updates, existing_fields, headers):
    """
    Send a single PATCH with all custom field updates merged over existing fields.
    `updates` is a dict of {field_id: value}.
    `existing_fields` is the current doc['custom_fields'] list.
    """
    # Start from whatever is already on the document
    fields_by_id = {cf["field"]: cf["value"] for cf in existing_fields}
    # Apply updates on top
    fields_by_id.update(updates)

    payload = [{"field": fid, "value": val} for fid, val in fields_by_id.items()]
    resp = requests.patch(
        f"{PAPERLESS_URL}/api/documents/{document_id}/",
        headers=headers,
        json={"custom_fields": payload},
        timeout=TIMEOUT,
    )
    resp.raise_for_status()


def handle_paid_ref(document_id, doc, headers):
    """
    If this document contains a [ref:ID] token, mark the referenced document
    as paid and delete this reply/eml document.
    Returns True if handled (caller should stop further processing).
    """
    content = doc.get("content", "")
    match = re.search(r"\[ref:(\d+)\]", content)
    if not match:
        return False

    original_id = int(match.group(1))
    print(f"Found ref token, original document is {original_id}")

    bulk_resp = requests.post(
        f"{PAPERLESS_URL}/api/documents/bulk_edit/",
        headers=headers,
        json={
            "documents": [original_id],
            "method": "modify_tags",
            "parameters": {
                "add_tags": [PAID_TAG_ID],
                "remove_tags": [NOT_PAID_TAG_ID, TODO_TAG_ID],
            },
        },
        timeout=TIMEOUT,
    )
    bulk_resp.raise_for_status()
    print(f"Tagged document {original_id} as paid, removed not-paid/todo tags.")

    del_resp = requests.delete(
        f"{PAPERLESS_URL}/api/documents/{document_id}/",
        headers=headers,
        timeout=TIMEOUT,
    )
    del_resp.raise_for_status()
    print(f"Deleted reply document {document_id}.")

    return True


def compute_invoice_due_date(document_id, doc):
    """
    Returns {PAYMENT_DUE_FIELD_ID: created_date} if this is an invoice
    without a due date already set, otherwise {}.
    """
    if doc.get("document_type") != INVOICE_DOCTYPE_ID:
        print(f"Document {document_id} is not an invoice, skipping due date.")
        return {}

    for cf in doc.get("custom_fields", []):
        if cf.get("field") == PAYMENT_DUE_FIELD_ID and cf.get("value"):
            print(f"Payment Due Date already set on document {document_id}, skipping.")
            return {}

    created_date = doc.get("created")
    if not created_date:
        print(f"Document {document_id} has no created date, skipping due date.")
        return {}

    print(f"Will set Payment Due Date to {created_date} on document {document_id}.")
    return {PAYMENT_DUE_FIELD_ID: created_date}


def compute_owner_field(document_id, doc, headers):
    """
    Returns {OWNER_FIELD_ID: option_id} for the document's owner,
    or {} if already set.
    """
    for cf in doc.get("custom_fields", []):
        if cf.get("field") == OWNER_FIELD_ID and cf.get("value"):
            print(f"Owner field already set on document {document_id}, skipping.")
            return {}

    owner_id = doc.get("owner")
    username = None
    if owner_id is not None:
        user_resp = requests.get(
            f"{PAPERLESS_URL}/api/users/{owner_id}/",
            headers=headers,
            timeout=TIMEOUT,
        )
        user_resp.raise_for_status()
        username = user_resp.json().get("username")

    option_id = OWNER_USERNAME_TO_OPTION_ID.get(username, OWNER_USERNAME_TO_OPTION_ID[None])
    print(f"Will set Owner field to {username!r} → {option_id} on document {document_id}.")
    return {OWNER_FIELD_ID: option_id}


def main():
    document_id = os.environ.get("DOCUMENT_ID") or (sys.argv[1] if len(sys.argv) > 1 else None)
    if not document_id:
        print("No DOCUMENT_ID found in environment, exiting.")
        return

    headers = {"Authorization": f"Token {TOKEN}"}
    doc = fetch_document(document_id, headers)

    # Flow 1: reply/eml with a ref token → mark original as paid and stop
    if handle_paid_ref(document_id, doc, headers):
        return

    # Flows 2 & 3: compute all custom field updates, then apply in one PATCH
    updates = {}
    updates.update(compute_invoice_due_date(document_id, doc))
    updates.update(compute_owner_field(document_id, doc, headers))

    if updates:
        patch_custom_fields(document_id, updates, doc.get("custom_fields", []), headers)
        print(f"Applied {len(updates)} custom field update(s) to document {document_id}.")


if __name__ == "__main__":
    main()
