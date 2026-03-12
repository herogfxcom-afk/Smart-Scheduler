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
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.datetime.now(datetime.timezone.utc))

    busy_slots = relationship("BusySlot", back_populates="user")
    created_meetings = relationship("GroupMeeting", back_populates="creator")
    groups = relationship("GroupParticipant", back_populates="user")
    availability = relationship("UserAvailability", back_populates="user")
    connections = relationship("CalendarConnection", back_populates="user", cascade="all, delete-orphan")

class CalendarConnection(Base):
    __tablename__ = "calendar_connections"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    provider = Column(String(50), nullable=False)  # 'google', 'outlook', 'apple'
    email = Column(String(255), nullable=True)
    auth_data = Column(Text, nullable=False)  # Encrypted tokens
    status = Column(String(50), default="active")  # 'active', 'error', 'needs_reauth'
    last_error = Column(Text, nullable=True)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.datetime.now(datetime.timezone.utc))
    last_sync = Column(DateTime(timezone=True), nullable=True)

    user = relationship("User", back_populates="connections")
    busy_slots = relationship("BusySlot", back_populates="connection", cascade="all, delete-orphan")

    __table_args__ = (
        UniqueConstraint('user_id', 'provider', 'email', name='_user_provider_email_uc'),
    )

class Group(Base):
    __tablename__ = "groups"
    id = Column(Integer, primary_key=True)
    telegram_chat_id = Column(String(255), unique=True, index=True, nullable=False)
    title = Column(String(255), nullable=True)
    last_invite_message_id = Column(BigInteger, nullable=True) # For updating the "Magic Sync" card
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.datetime.now(datetime.timezone.utc))
    
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
    start_time = Column(DateTime(timezone=True), nullable=False)
    end_time = Column(DateTime(timezone=True), nullable=False)
    title = Column(String(255))
    location = Column(Text, nullable=True)
    description = Column(Text, nullable=True)
    idempotency_key = Column(String(255), unique=True)
    google_event_id = Column(String(255), nullable=True)
    outlook_event_id = Column(String(255), nullable=True)
    
    group = relationship("Group", back_populates="meetings")
    creator = relationship("User", back_populates="created_meetings")
    invites = relationship("MeetingInvite", back_populates="meeting", cascade="all, delete-orphan")


class BusySlot(Base):
    __tablename__ = "busy_slots"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    connection_id = Column(Integer, ForeignKey("calendar_connections.id"), nullable=True)
    start_time = Column(DateTime(timezone=True), nullable=False)
    end_time = Column(DateTime(timezone=True), nullable=False)

    user = relationship("User", back_populates="busy_slots")
    connection = relationship("CalendarConnection", back_populates="busy_slots")

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

class MeetingInvite(Base):
    __tablename__ = "meeting_invites"
    id = Column(Integer, primary_key=True)
    meeting_id = Column(Integer, ForeignKey("group_meetings.id"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    status = Column(String(50), default="pending")  # 'pending', 'accepted', 'declined'
    google_event_id = Column(String(255), nullable=True) # Each participant might have their own event
    outlook_event_id = Column(String(255), nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.datetime.now(datetime.timezone.utc))

    meeting = relationship("GroupMeeting", back_populates="invites")
    user = relationship("User")
