import re
from typing import ClassVar

from ecoscan.schemas import UserSchema


class EmailValidator:
    _EMAIL_RE: ClassVar[re.Pattern] = re.compile(
        r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@"
        r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
        r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$"
    )

    @classmethod
    def is_valid(self, email: str) -> bool:
        if not isinstance(email, str):
            return False
        email = email.strip()
        if not email:
            return False
        return bool(self._EMAIL_RE.fullmatch(email))



class PasswordValidator:

    _PWD_RE: ClassVar[re.Pattern] = re.compile(
        r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).+$"
    )

    @classmethod
    def is_valid(self, password: str) -> bool:
        if not isinstance(password, str):
            return False
        pwd = password.strip()
        if not pwd:
            return False
        return bool(self._PWD_RE.fullmatch(pwd))


class NameValidator:

    @classmethod
    def is_valid(self, name: str) -> bool:
        if not isinstance(name, str):
            return False
        s = name.strip()
        if not s:
            return False
        for ch in s:
            if not (ch.isalpha() or ch.isspace()):
                return False
        return True
    

class UserFieldsValidator:
    @classmethod
    def is_valid(self, user: UserSchema) -> bool:
        return (
            EmailValidator.is_valid(user.email) and
            PasswordValidator.is_valid(user.password) and
            NameValidator.is_valid(user.name)
        )