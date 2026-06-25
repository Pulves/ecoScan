import asyncio
import smtplib
import ssl
from email.message import EmailMessage
from email.utils import formataddr

from ecoscan.settings import Settings


class EmailConfigurationError(RuntimeError):
    pass


def _build_password_reset_message(
    recipient: str,
    token: str,
    settings: Settings,
) -> EmailMessage:
    if not settings.SMTP_FROM_EMAIL:
        raise EmailConfigurationError("SMTP_FROM_EMAIL nao foi configurado.")

    message = EmailMessage()
    message["Subject"] = "Recuperacao de senha EcoScan"
    message["From"] = formataddr(
        (settings.SMTP_FROM_NAME, settings.SMTP_FROM_EMAIL)
    )
    message["To"] = recipient
    message.set_content(
        "\n".join(
            [
                "Foi solicitada a recuperacao da sua senha no EcoScan.",
                "",
                f"Codigo de recuperacao: {token}",
                "",
                (
                    "Informe esse codigo no aplicativo em ate "
                    f"{settings.PASSWORD_RESET_TOKEN_EXPIRE_MINUTES} minutos."
                ),
                (
                    "Se voce nao solicitou a recuperacao, ignore esta "
                    "mensagem."
                ),
            ]
        )
    )
    return message


def _send_password_reset_email_sync(
    recipient: str,
    token: str,
    settings: Settings,
) -> None:
    if not settings.SMTP_HOST:
        raise EmailConfigurationError("SMTP_HOST nao foi configurado.")
    if settings.SMTP_USE_SSL and settings.SMTP_USE_TLS:
        raise EmailConfigurationError(
            "Configure somente um entre SMTP_USE_SSL e SMTP_USE_TLS."
        )

    message = _build_password_reset_message(recipient, token, settings)
    context = ssl.create_default_context()
    if settings.SMTP_USE_SSL:
        smtp_client = smtplib.SMTP_SSL(
            settings.SMTP_HOST,
            settings.SMTP_PORT,
            timeout=15,
            context=context,
        )
    else:
        smtp_client = smtplib.SMTP(
            settings.SMTP_HOST,
            settings.SMTP_PORT,
            timeout=15,
        )

    with smtp_client as smtp:
        if settings.SMTP_USE_TLS:
            smtp.starttls(context=context)
        if settings.SMTP_USERNAME:
            smtp.login(
                settings.SMTP_USERNAME,
                settings.SMTP_PASSWORD or "",
            )
        smtp.send_message(message)


async def send_password_reset_email(
    recipient: str,
    token: str,
    settings: Settings,
) -> None:
    await asyncio.to_thread(
        _send_password_reset_email_sync,
        recipient,
        token,
        settings,
    )
