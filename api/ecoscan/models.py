from datetime import datetime
from uuid import uuid4, UUID

from sqlalchemy import ForeignKey, func

from sqlalchemy.orm import (Mapped, 
                            mapped_column, relationship, 
                            mapped_as_dataclass, registry
                        )


table_registry = registry()



@mapped_as_dataclass(table_registry)
class User:
    __tablename__ = "users"

    name: Mapped[str] = mapped_column(nullable=False, unique=True)
    email: Mapped[str] = mapped_column(nullable=False, unique=True)
    password: Mapped[str] = mapped_column(nullable=False)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now(), init=False)
    id: Mapped[UUID] = mapped_column(primary_key=True, default_factory=uuid4)


    plants: Mapped[list["Plant"]] = relationship(init=False, 
                                                 cascade="all, delete-orphan",
                                                 lazy="selectin"
                                                 )
    



@mapped_as_dataclass(table_registry)
class Plant:
    __tablename__ = "plants"   

    name: Mapped[str] = mapped_column(nullable=False)
    care_information: Mapped[str] = mapped_column(nullable=False)
    characteristics: Mapped[str] = mapped_column(nullable=False)
    botanical_family: Mapped[str] = mapped_column(nullable=False)
    image_url: Mapped[str] = mapped_column(nullable=False)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    id: Mapped[UUID] = mapped_column(primary_key=True, default_factory=uuid4)
