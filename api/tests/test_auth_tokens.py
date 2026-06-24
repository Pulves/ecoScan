from unittest import IsolatedAsyncioTestCase, TestCase

from fastapi import HTTPException
from jwt import decode

from ecoscan.models import User
from ecoscan.routes.auth import refresh_token
from ecoscan.security import (
    _get_user_from_token,
    create_access_token,
    create_refresh_token,
    settings,
)


class FakeSession:
    def __init__(self, user: User) -> None:
        self.user = user

    async def scalar(self, statement: object) -> User:
        return self.user


class TokenCreationTests(TestCase):
    def test_creates_distinct_access_and_refresh_tokens(self) -> None:
        access_token = create_access_token({"sub": "user@example.com"})
        refresh = create_refresh_token({"sub": "user@example.com"})

        access_payload = decode(
            access_token,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )
        refresh_payload = decode(
            refresh,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )

        self.assertEqual(access_payload["type"], "access")
        self.assertEqual(refresh_payload["type"], "refresh")
        self.assertGreater(refresh_payload["exp"], access_payload["exp"])

    def test_refresh_endpoint_rotates_both_tokens(self) -> None:
        user = User(
            name="test-user",
            email="user@example.com",
            password="hashed",
        )

        response = refresh_token(user)
        next_response = refresh_token(user)

        self.assertIn("access_token", response)
        self.assertIn("refresh_token", response)
        self.assertEqual(response["token_type"], "bearer")
        self.assertNotEqual(
            response["access_token"],
            next_response["access_token"],
        )
        self.assertNotEqual(
            response["refresh_token"],
            next_response["refresh_token"],
        )


class TokenValidationTests(IsolatedAsyncioTestCase):
    async def test_access_token_cannot_be_used_as_refresh_token(self) -> None:
        user = User(
            name="test-user",
            email="user@example.com",
            password="hashed",
        )
        token = create_access_token({"sub": user.email})

        with self.assertRaises(HTTPException):
            await _get_user_from_token(
                FakeSession(user),
                token,
                expected_type="refresh",
            )
