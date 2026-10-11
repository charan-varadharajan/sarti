import os

os.environ.setdefault(
    "SARTI_DATABASE_URL",
    "postgresql+psycopg://sarti_local:replace-for-local-use@localhost:5432/sarti_test",
)
os.environ.setdefault("SARTI_ENVIRONMENT", "test")
