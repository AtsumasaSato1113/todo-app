from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
import os

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./todos.db")

# SQLite用の設定 (PostgreSQLに切り替える場合はconnect_argsを削除)
connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

engine = create_engine(DATABASE_URL, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    """FastAPIのDependency Injectionで使用するDB接続"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
