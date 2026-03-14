import os
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv

load_dotenv()

# First try Railway's common DB variables, then generic DATABASE_URL
DATABASE_URL = os.getenv("DATABASE_URL") or os.getenv("DATABASE_PRIVATE_URL") or os.getenv("DATABASE_PUBLIC_URL")

# Compatibility fix: modern SQLAlchemy requires 'postgresql://', but many services still provide 'postgres://'
if DATABASE_URL and DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

# Final fallback for development or unlinked services
if not DATABASE_URL:
    DATABASE_URL = "sqlite:///./test.db"
    print("WARNING: DATABASE_URL not found. Using local SQLite database (test.db).")

engine = create_engine(
    DATABASE_URL,
    # Small optimization for SQLite
    connect_args={"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {},
    # Stability for Neon/Serverless Postgres (handles SSL connection closed errors)
    pool_pre_ping=True,
    pool_recycle=300,
    max_overflow=20,
    pool_size=10
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
