from datetime import UTC, datetime, timedelta
from unittest import IsolatedAsyncioTestCase
from unittest.mock import AsyncMock, patch

from ecoscan.email_service import _build_password_reset_message
from ecoscan.models import PasswordResetToken, User
from ecoscan.routes import auth
from ecoscan.routes.auth import confirm_password_reset, request_password_reset
from ecoscan.routes.user import update_user
from ecoscan.schemas import (
    PasswordResetRequestSchema,
    PasswordResetSchema,
    UserUpdateSchema,
)
from ecoscan.security import verify_password
from ecoscan.settings import Settings


class FakeSession:
    def __init__(self, scalar_results: list[object | None]) -> None:
        self.scalar_results = scalar_results
        self.added: list[object] = []

    async def scalar(self, statement: object):
        return self.scalar_results.pop(0)

    async def execute(self, statement: object) -> None:
        return None

    def add(self, value: object) -> None:
        self.added.append(value)

    def add_all(self, values: list[object]) -> None:
        self.added.extend(values)

    async def commit(self) -> None:
        return None

    async def rollback(self) -> None:
        return None

    async def refresh(self, value: object) -> None:
        return None

    async def get(self, model: type, identifier: object):
        return self.scalar_results.pop(0)


class UserFeatureTests(IsolatedAsyncioTestCase):
    async def test_updates_profile_and_rotates_tokens(self) -> None:
        user = User(
            name="Old name",
            email="old@example.com",
            password="hashed",
        )
        session = FakeSession([None])

        response = await update_user(
            user_update=UserUpdateSchema(
                name="New name",
                email="new@example.com",
            ),
            session=session,
            current_user=user,
        )

        self.assertEqual(user.name, "New name")
        self.assertEqual(user.email, "new@example.com")
        self.assertIn("access_token", response)
        self.assertIn("refresh_token", response)

    async def test_password_reset_token_is_one_time(self) -> None:
        user = User(
            name="test-user",
            email="user@example.com",
            password="old-hash",
        )
        session = FakeSession([user])
        previous_setting = auth.settings.PASSWORD_RESET_EXPOSE_TOKEN
        auth.settings.PASSWORD_RESET_EXPOSE_TOKEN = True
        try:
            response = await request_password_reset(
                request=PasswordResetRequestSchema(email=user.email),
                session=session,
            )
        finally:
            auth.settings.PASSWORD_RESET_EXPOSE_TOKEN = previous_setting

        reset_token = response["reset_token"]
        stored_token = next(
            value
            for value in session.added
            if isinstance(value, PasswordResetToken)
        )
        self.assertIsNotNone(reset_token)
        self.assertGreater(stored_token.expires_at, datetime.now(UTC))

        confirm_session = FakeSession([stored_token, user])
        result = await confirm_password_reset(
            reset=PasswordResetSchema(
                token=str(reset_token),
                new_password="new-password",
            ),
            session=confirm_session,
        )

        self.assertEqual(result["message"], "Senha alterada com sucesso.")
        self.assertIsNotNone(stored_token.used_at)
        self.assertTrue(verify_password("new-password", user.password))

    async def test_password_reset_is_sent_by_email_in_production(self) -> None:
        user = User(
            name="test-user",
            email="user@example.com",
            password="old-hash",
        )
        session = FakeSession([user])
        previous_expose = auth.settings.PASSWORD_RESET_EXPOSE_TOKEN
        auth.settings.PASSWORD_RESET_EXPOSE_TOKEN = False
        try:
            with patch(
                "ecoscan.routes.auth.send_password_reset_email",
                new_callable=AsyncMock,
            ) as send_email:
                response = await request_password_reset(
                    request=PasswordResetRequestSchema(email=user.email),
                    session=session,
                )
        finally:
            auth.settings.PASSWORD_RESET_EXPOSE_TOKEN = previous_expose

        self.assertIsNone(response["reset_token"])
        send_email.assert_awaited_once()
        self.assertEqual(send_email.await_args.args[0], user.email)

    def test_password_reset_email_contains_token(self) -> None:
        email_settings = Settings(
            SMTP_FROM_EMAIL="noreply@example.com",
            PASSWORD_RESET_TOKEN_EXPIRE_MINUTES=15,
        )

        message = _build_password_reset_message(
            "user@example.com",
            "reset-code",
            email_settings,
        )

        self.assertEqual(message["To"], "user@example.com")
        self.assertIn("reset-code", message.get_content())
        self.assertIn("15 minutos", message.get_content())
