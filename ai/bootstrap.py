import os

from django.contrib.auth import get_user_model
from rest_framework.authtoken.models import Token

User = get_user_model()
username = os.environ["PAPERLESS_ADMIN_USER"]
password = os.environ["PAPERLESS_ADMIN_PASSWORD"]
email = os.environ.get("PAPERLESS_ADMIN_MAIL") or ""
token_key = os.environ["PAPERLESS_API_TOKEN"]

user, _created = User.objects.get_or_create(
    username=username,
    defaults={"email": email, "is_staff": True, "is_superuser": True},
)
user.email = email or user.email
user.is_staff = True
user.is_superuser = True
user.set_password(password)
user.save()

existing = Token.objects.filter(user=user).first()
if existing is None or existing.key != token_key:
    Token.objects.filter(user=user).delete()
    Token.objects.filter(key=token_key).delete()
    Token.objects.create(user=user, key=token_key)
