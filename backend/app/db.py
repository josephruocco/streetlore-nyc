from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

from .settings import settings

engine: Engine = create_engine(settings.database_url, pool_pre_ping=True)


def fetch_one(sql: str, params: dict):
    with engine.connect() as conn:
        row = conn.execute(text(sql), params).mappings().first()
        return dict(row) if row else None


def fetch_all(sql: str, params: dict):
    with engine.connect() as conn:
        rows = conn.execute(text(sql), params).mappings().all()
        return [dict(r) for r in rows]


def execute(sql: str, params: dict | None = None):
    with engine.begin() as conn:
        conn.execute(text(sql), params or {})
