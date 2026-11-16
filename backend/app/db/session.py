from fastapi import Request
from sqlalchemy import create_engine
from sqlmodel import Session


def make_engine(settings):
    return create_engine(
        settings.database_url.get_secret_value(),
        pool_size=5,
        max_overflow=0,
        pool_timeout=5,
        pool_pre_ping=True,
        hide_parameters=True,
        connect_args={"connect_timeout": 3, "options": "-c statement_timeout=5000 -c timezone=UTC"},
    )


def get_session(request: Request):
    with Session(request.app.state.engine) as session:
        yield session
