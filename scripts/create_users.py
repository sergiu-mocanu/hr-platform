"""Create the fictitious NovaCorp accounts via the Supabase admin API.

Auth users cannot be created from seed.sql: passwords are hashed by the auth
service, so inserting into auth.users by hand is unreliable. This script does
that half; supabase/seed.sql sets roles, hierarchy and balances afterwards.

Idempotent — an account that already exists is skipped.

Usage:
    python scripts/create_users.py
"""

import os
import sys

import requests
from dotenv import load_dotenv

# Fictitious data only. This password is public by design; never reuse it.
DEFAULT_PASSWORD = "NovaCorp2026!"

EMPLOYEES = [
    ("hugo.bernard@novacorp.fr", "Hugo Bernard"),
    ("sophie.martin@novacorp.fr", "Sophie Martin"),
    ("marc.leroy@novacorp.fr", "Marc Leroy"),
    ("nadia.cherif@novacorp.fr", "Nadia Cherif"),
    ("claire.dubois@novacorp.fr", "Claire Dubois"),
    ("thomas.roux@novacorp.fr", "Thomas Roux"),
    ("lea.moreau@novacorp.fr", "Léa Moreau"),
    ("karim.benali@novacorp.fr", "Karim Benali"),
]


def create_user(base_url: str, service_key: str, email: str, full_name: str) -> str:
    """Return 'created', 'exists', or raises on an unexpected response."""
    response = requests.post(
        f"{base_url}/auth/v1/admin/users",
        headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
        },
        json={
            "email": email,
            "password": DEFAULT_PASSWORD,
            "email_confirm": True,
            "user_metadata": {"full_name": full_name},
        },
        timeout=30,
    )

    if response.ok:
        return "created"
    if response.status_code == 422:
        return "exists"
    raise RuntimeError(f"{email}: {response.status_code} {response.text}")


def main() -> int:
    load_dotenv()
    base_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

    if not base_url or not service_key:
        print("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env", file=sys.stderr)
        return 1

    for email, full_name in EMPLOYEES:
        try:
            status = create_user(base_url, service_key, email, full_name)
        except RuntimeError as exc:
            print(f"FAILED  {exc}", file=sys.stderr)
            return 1
        print(f"{status:8} {email}")

    print(f"\n{len(EMPLOYEES)} accounts ready. Password for all: {DEFAULT_PASSWORD}")
    print("Next: supabase db push --include-seed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
