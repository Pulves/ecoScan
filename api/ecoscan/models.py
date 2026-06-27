from datetime import datetime
from uuid import uuid4, UUID
from sqlalchemy import ForeignKey, func
from sqlalchemy.orm import (Mapped, 
                            mapped_column, relationship, 
                            mapped_as_dataclass, registry
                        )



table_registry = registry()

class Base:
    id: Mapped[UUID] = mapped_column(primary_key=True, default_factory=uuid4)
        

@mapped_as_dataclass(registry=table_registry, kw_only=True)
class User(Base):
    __tablename__ = "users"

    name: Mapped[str] = mapped_column(nullable=False, unique=True, default="")
    email: Mapped[str] = mapped_column(nullable=False, unique=True, default="")
    password: Mapped[str] = mapped_column(nullable=False, default="")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now(), init=False)
    # id: Mapped[UUID] = mapped_column(primary_key=True, default_factory=uuid4)


    plants: Mapped[list["Plant"]] = relationship(init=False, 
                                                 cascade="all, delete-orphan",
                                                 lazy="selectin"
                                                 )
    



@mapped_as_dataclass(registry=table_registry, kw_only=True)
class Plant(Base):
    __tablename__ = "plants"   

    name: Mapped[str] = mapped_column(nullable=False, default="")
    care_information: Mapped[str] = mapped_column(nullable=False, default="")
    characteristics: Mapped[str] = mapped_column(nullable=False, default="")
    botanical_family: Mapped[str] = mapped_column(nullable=False, default="")
    image_url: Mapped[str] = mapped_column(nullable=False, default="")
    # id: Mapped[UUID] = mapped_column(primary_key=True, default_factory=uuid4)

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))

