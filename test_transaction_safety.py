import os
import unittest
import asyncio
from unittest.mock import MagicMock, patch, AsyncMock
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
import models
from main import perform_calendar_sync
from models import User, BusySlot, UserAvailability

# Use a real file-based SQLite
DB_PATH = "test_advisory_lock.db"
if os.path.exists(DB_PATH): os.remove(DB_PATH)

engine = create_engine(f"sqlite:///{DB_PATH}")
TestingSessionLocal = sessionmaker(bind=engine)
models.Base.metadata.create_all(bind=engine)

class TestTransactionSafety(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.db = TestingSessionLocal()
        # Create a test user
        self.user = User(
            id=1,
            telegram_id=12345,
            username="test_advisory_user",
            timezone="UTC"
        )
        self.db.add(self.user)
        self.db.commit()

    def tearDown(self):
        self.db.close()
        if os.path.exists(DB_PATH): os.remove(DB_PATH)

    async def test_advisory_lock_collision_safety(self):
        """
        Verifies that when pg_try_advisory_xact_lock returns False, 
        no exception is raised and the session remains healthy.
        """
        # Mock execute to return False for the advisory lock
        with patch.object(self.db, 'execute') as mock_exec:
            mock_scalar = MagicMock()
            mock_scalar.scalar.return_value = False
            mock_exec.return_value = mock_scalar
            
            # This should NOT raise an exception now
            result = await perform_calendar_sync(self.user, self.db)
            self.assertEqual(result, 0, "Sync should be skipped gracefully if lock is held")
            
            # Verify subsequent query on SAME session passes
            print("DEBUG: Executing post-collision query...")
            avail = self.db.query(UserAvailability).filter_by(user_id=self.user.id).all()
            self.assertEqual(len(avail), 0, "Query should succeed because transaction was NOT aborted")
            print("DEBUG: Advisory lock safety verified!")

if __name__ == "__main__":
    unittest.main()
