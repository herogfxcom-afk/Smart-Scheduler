from sqlalchemy import Column, Integer, BigInteger, String, DateTime, ForeignKey, Text, UniqueConstraint
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
import datetime

Base = declarative_base()

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    telegram_id = Column(BigInteger, unique=True, index=True, nullable=False)
    username = Column(String(255), nullable=True)
    first_name = Column(String(255), nullable=True)
    photo_url = Column(Text, nullable=True)
    email = Column(String(255), nullable=True)  # Added for collective invites
    google_refresh_token = Column(Text, nullable=True)
    apple_auth_data = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)

    busy_slots = relationship("BusySlot", back_populates="user")
    created_meetings = relationship("Meeting", back_populates="creator")
    groups = relationship("GroupParticipant", back_populates="user")
    availability = relationship("UserAvailability", back_populates="user")

class Group(Base):
    __tablename__ = "groups"
    id = Column(Integer, primary_key=True)
    telegram_chat_id = Column(String(255), unique=True, index=True, nullable=False)
    title = Column(String(255), nullable=True)
    last_invite_message_id = Column(BigInteger, nullable=True) # For updating the "Magic Sync" card
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    
    participants = relationship("GroupParticipant", back_populates="group")
    meetings = relationship("GroupMeeting", back_populates="group")

class GroupParticipant(Base):
    __tablename__ = "group_participants"
    id = Column(Integer, primary_key=True)
    group_id = Column(Integer, ForeignKey("groups.id"))
    user_id = Column(Integer, ForeignKey("users.id"))
    is_synced = Column(Integer, default=0) # 0=No, 1=Yes
    
    group = relationship("Group", back_populates="participants")
    user = relationship("User", back_populates="groups")

    __table_args__ = (
        UniqueConstraint('group_id', 'user_id', name='_group_user_uc'),
    )

class GroupMeeting(Base):
    __tablename__ = "group_meetings"
    id = Column(Integer, primary_key=True)
    group_id = Column(Integer, ForeignKey("groups.id"))
    user_id = Column(Integer, ForeignKey("users.id"))  # Track the creator
    start_time = Column(DateTime, nullable=False)
    end_time = Column(DateTime, nullable=False)
    title = Column(String(255))
    location = Column(Text, nullable=True)
    idempotency_key = Column(String(255), unique=True)
    google_event_id = Column(String(255), nullable=True)
    
    group = relationship("Group", back_populates="meetings")
    creator = relationship("User")

class Meeting(Base):
    __tablename__ = "meetings"

    id = Column(Integer, primary_key=True, index=True)
    group_id = Column(BigInteger, index=True)
    title = Column(String(255))
    start_time = Column(DateTime, nullable=False)
    end_time = Column(DateTime, nullable=False)
    location = Column(Text, nullable=True)
    created_by = Column(Integer, ForeignKey("users.id"))

    creator = relationship("User", back_populates="created_meetings")

class BusySlot(Base):
    __tablename__ = "busy_slots"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    start_time = Column(DateTime, nullable=False)
    end_time = Column(DateTime, nullable=False)

    user = relationship("User", back_populates="busy_slots")

    __table_args__ = (
        UniqueConstraint('user_id', 'start_time', 'end_time', name='_user_slot_uc'),
    )

class UserAvailability(Base):
    __tablename__ = "user_availability"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    day_of_week = Column(Integer, nullable=False)  # 0=Monday, 6=Sunday
    start_time = Column(String(5), nullable=False, default="09:00")
    end_time = Column(String(5), nullable=False, default="18:00")
    is_enabled = Column(Integer, default=1)  # 1=Enabled, 0=Disabled/Day Off

    user = relationship("User", back_populates="availability")

    __table_args__ = (
        UniqueConstraint('user_id', 'day_of_week', name='_user_day_uc'),
    )
