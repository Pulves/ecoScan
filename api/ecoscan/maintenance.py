from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ecoscan.database import engine
from ecoscan.models import Identification, PasswordResetToken
from ecoscan.settings import Settings


async def cleanup_images(*, days: int, apply: bool) -> int:
    cutoff = datetime.now(UTC).replace(tzinfo=None) - timedelta(days=days)
    async with AsyncSession(engine, expire_on_commit=False) as session:
        count = await session.scalar(
            select(func.count(Identification.id)).where(
                Identification.in_library.is_(False),
                Identification.created_at < cutoff,
            )
        )
        total = int(count or 0)
        if apply and total:
            await session.execute(
                delete(Identification).where(
                    Identification.in_library.is_(False),
                    Identification.created_at < cutoff,
                )
            )
            await session.commit()
        return total


async def cleanup_expired_reset_tokens(*, apply: bool) -> int:
    now = datetime.now(UTC)
    async with AsyncSession(engine, expire_on_commit=False) as session:
        count = await session.scalar(
            select(func.count(PasswordResetToken.id)).where(
                PasswordResetToken.expires_at < now
            )
        )
        total = int(count or 0)
        if apply and total:
            await session.execute(
                delete(PasswordResetToken).where(
                    PasswordResetToken.expires_at < now
                )
            )
            await session.commit()
        return total


async def main() -> None:
    settings = Settings()
    parser = argparse.ArgumentParser(description="EcoScan database maintenance")
    parser.add_argument(
        "task",
        choices=["cleanup-images", "cleanup-reset-tokens"],
    )
    parser.add_argument(
        "--days",
        type=int,
        default=settings.IMAGE_RETENTION_DAYS,
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply deletions. Without this flag, only reports the count.",
    )
    args = parser.parse_args()

    if args.task == "cleanup-images":
        count = await cleanup_images(days=args.days, apply=args.apply)
    else:
        count = await cleanup_expired_reset_tokens(apply=args.apply)

    action = "removed" if args.apply else "would_remove"
    print(f"{action}={count}")
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
