import httpx
import logging
import re
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List
import auth_service

logger = logging.getLogger(__name__)

CALENDAR_API_BASE = "https://www.googleapis.com/calendar/v3"


async def get_valid_access_token(user_tokens: Dict[str, Any]) -> Optional[str]:
    """Get a valid access token, refreshing if necessary."""
    access_token = user_tokens.get("access_token")
    refresh_token = user_tokens.get("refresh_token")
    expires_at = user_tokens.get("expires_at")

    # Check if token is expired or about to expire (within 5 minutes)
    if expires_at:
        try:
            expiry = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
            if datetime.now(expiry.tzinfo) >= expiry - timedelta(minutes=5):
                # Token expired, refresh it
                if refresh_token:
                    new_tokens = await auth_service.refresh_access_token(refresh_token)
                    if new_tokens:
                        return new_tokens.get("access_token")
                return None
        except Exception as e:
            logger.error(f"Error checking token expiry: {e}")

    return access_token


async def create_calendar_event(
    access_token: str,
    title: str,
    description: str,
    start_time: datetime,
    end_time: Optional[datetime] = None,
    attendees: Optional[List[str]] = None,
    timezone: str = "Asia/Karachi",  # Default to user's timezone
) -> Optional[Dict[str, Any]]:
    """Create a calendar event."""
    if end_time is None:
        end_time = start_time + timedelta(hours=1)

    event_body = {
        "summary": title,
        "description": description,
        "start": {
            "dateTime": start_time.strftime("%Y-%m-%dT%H:%M:%S"),
            "timeZone": timezone,
        },
        "end": {
            "dateTime": end_time.strftime("%Y-%m-%dT%H:%M:%S"),
            "timeZone": timezone,
        },
    }

    if attendees:
        event_body["attendees"] = [{"email": email} for email in attendees]

    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{CALENDAR_API_BASE}/calendars/primary/events",
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": "application/json",
                },
                json=event_body,
            )

            if response.status_code == 200 or response.status_code == 201:
                event = response.json()
                logger.info(
                    f"Created calendar event: {event.get('id')} at {start_time}"
                )
                return event
            else:
                logger.error(
                    f"Failed to create calendar event: {response.status_code} {response.text}"
                )
                return None
    except Exception as e:
        logger.error(f"Error creating calendar event: {e}")
        return None


async def add_meeting_events_to_calendar(
    user_tokens: Dict[str, Any],
    meeting_title: str,
    action_items: List[Dict[str, Any]],
    meeting_id: str,
) -> List[Dict[str, Any]]:
    """Add action items with deadlines to user's calendar."""
    logger.info(
        f"[CALENDAR] Processing {len(action_items)} action items for meeting={meeting_id}"
    )

    for i, item in enumerate(action_items):
        logger.info(f"[CALENDAR] Action item {i + 1}: {item}")

    access_token = await get_valid_access_token(user_tokens)
    if not access_token:
        logger.warning("No valid access token for calendar")
        return []

    created_events = []

    for item in action_items:
        deadline_str = item.get("deadline")
        logger.info(
            f"[CALENDAR] Checking deadline: '{deadline_str}' (type: {type(deadline_str).__name__})"
        )

        if deadline_str is None:
            logger.info(f"[CALENDAR] Skipping - deadline is None")
            continue

        deadline_lower = str(deadline_str).lower().strip()
        if deadline_lower in ["none", "null", "tbd", "asap", "", "n/a", "na"]:
            logger.info(f"[CALENDAR] Skipping - deadline is '{deadline_lower}'")
            continue

        # Try to parse the deadline
        deadline = parse_deadline(str(deadline_str))
        if not deadline:
            logger.warning(f"[CALENDAR] Could not parse deadline: {deadline_str}")
            continue

        task = item.get("task", "Action Item")
        assignee = item.get("assignee", "")

        title = f"[EchoMind] {task[:50]}..." if len(task) > 50 else f"[EchoMind] {task}"
        description = f"Action item from meeting: {meeting_title}\n\nTask: {task}\nAssignee: {assignee}\n\nMeeting ID: {meeting_id}"

        logger.info(
            f"Creating calendar event for deadline: {deadline_str} -> {deadline}"
        )

        event = await create_calendar_event(
            access_token=access_token,
            title=title,
            description=description,
            start_time=deadline,
            end_time=deadline + timedelta(hours=1),
        )

        if event:
            created_events.append(event)

    return created_events


def parse_deadline(deadline_str: str) -> Optional[datetime]:
    """Parse various deadline formats into datetime.

    Handles:
    - ISO format: 2024-04-15T14:30, 2024-04-15
    - Common formats: 04/15/2024, April 15, 2024
    - Relative: today, tomorrow, next week, end of week
    - Time extraction: "April 15 at 2pm", "tomorrow at 3:30 PM"
    """
    deadline_str = deadline_str.strip()
    now = datetime.now()

    # Try to extract time from the string first
    extracted_time = _extract_time(deadline_str)

    # ISO format with time
    iso_match = re.match(r"^(\d{4}-\d{2}-\d{2})(?:T(\d{2}):(\d{2}))?", deadline_str)
    if iso_match:
        try:
            date_part = iso_match.group(1)
            hour = int(iso_match.group(2)) if iso_match.group(2) else None
            minute = int(iso_match.group(3)) if iso_match.group(3) else 0

            parsed = datetime.strptime(date_part, "%Y-%m-%d")
            if hour is not None:
                parsed = parsed.replace(hour=hour, minute=minute)
            elif extracted_time:
                parsed = parsed.replace(
                    hour=extracted_time[0], minute=extracted_time[1]
                )
            else:
                parsed = parsed.replace(hour=9, minute=0)  # Default to 9 AM
            return parsed
        except ValueError:
            pass

    # Common date formats
    date_formats = [
        (r"^(\d{1,2})/(\d{1,2})/(\d{4})", "%m/%d/%Y"),
        (r"^(\d{1,2})-(\d{1,2})-(\d{4})", "%m-%d-%Y"),
        (r"^(\d{4})/(\d{1,2})/(\d{1,2})", "%Y/%m/%d"),
    ]

    for pattern, fmt in date_formats:
        match = re.match(pattern, deadline_str)
        if match:
            try:
                parsed = datetime.strptime(match.group(0), fmt)
                if extracted_time:
                    parsed = parsed.replace(
                        hour=extracted_time[0], minute=extracted_time[1]
                    )
                else:
                    parsed = parsed.replace(hour=9, minute=0)  # Default to 9 AM
                return parsed
            except ValueError:
                continue

    # Relative dates
    lower = deadline_str.lower()

    if "today" in lower:
        target = now
        if extracted_time:
            return target.replace(
                hour=extracted_time[0],
                minute=extracted_time[1],
                second=0,
                microsecond=0,
            )
        return target.replace(
            hour=17, minute=0, second=0, microsecond=0
        )  # Default 5 PM

    elif "tomorrow" in lower:
        target = now + timedelta(days=1)
        if extracted_time:
            return target.replace(
                hour=extracted_time[0],
                minute=extracted_time[1],
                second=0,
                microsecond=0,
            )
        return target.replace(hour=9, minute=0, second=0, microsecond=0)  # Default 9 AM

    elif "next week" in lower:
        target = now + timedelta(weeks=1)
        if extracted_time:
            return target.replace(
                hour=extracted_time[0],
                minute=extracted_time[1],
                second=0,
                microsecond=0,
            )
        return target.replace(hour=9, minute=0, second=0, microsecond=0)

    elif "end of week" in lower or "eow" in lower or "friday" in lower:
        days_until_friday = (4 - now.weekday()) % 7
        if days_until_friday == 0 and now.hour >= 17:
            days_until_friday = 7
        target = now + timedelta(days=days_until_friday)
        if extracted_time:
            return target.replace(
                hour=extracted_time[0],
                minute=extracted_time[1],
                second=0,
                microsecond=0,
            )
        return target.replace(hour=17, minute=0, second=0, microsecond=0)

    elif "end of month" in lower or "eom" in lower:
        if now.month == 12:
            next_month = now.replace(year=now.year + 1, month=1, day=1)
        else:
            next_month = now.replace(month=now.month + 1, day=1)
        target = next_month - timedelta(days=1)
        if extracted_time:
            return target.replace(
                hour=extracted_time[0],
                minute=extracted_time[1],
                second=0,
                microsecond=0,
            )
        return target.replace(hour=17, minute=0, second=0, microsecond=0)

    elif "monday" in lower:
        days_until = (0 - now.weekday()) % 7
        if days_until == 0:
            days_until = 7
        target = now + timedelta(days=days_until)
        if extracted_time:
            return target.replace(
                hour=extracted_time[0],
                minute=extracted_time[1],
                second=0,
                microsecond=0,
            )
        return target.replace(hour=9, minute=0, second=0, microsecond=0)

    elif "tuesday" in lower:
        days_until = (1 - now.weekday()) % 7
        if days_until == 0:
            days_until = 7
        target = now + timedelta(days=days_until)
        if extracted_time:
            return target.replace(
                hour=extracted_time[0],
                minute=extracted_time[1],
                second=0,
                microsecond=0,
            )
        return target.replace(hour=9, minute=0, second=0, microsecond=0)

    elif "wednesday" in lower:
        days_until = (2 - now.weekday()) % 7
        if days_until == 0:
            days_until = 7
        target = now + timedelta(days=days_until)
        if extracted_time:
            return target.replace(
                hour=extracted_time[0],
                minute=extracted_time[1],
                second=0,
                microsecond=0,
            )
        return target.replace(hour=9, minute=0, second=0, microsecond=0)

    elif "thursday" in lower:
        days_until = (3 - now.weekday()) % 7
        if days_until == 0:
            days_until = 7
        target = now + timedelta(days=days_until)
        if extracted_time:
            return target.replace(
                hour=extracted_time[0],
                minute=extracted_time[1],
                second=0,
                microsecond=0,
            )
        return target.replace(hour=9, minute=0, second=0, microsecond=0)

    elif "saturday" in lower:
        days_until = (5 - now.weekday()) % 7
        if days_until == 0:
            days_until = 7
        target = now + timedelta(days=days_until)
        if extracted_time:
            return target.replace(
                hour=extracted_time[0],
                minute=extracted_time[1],
                second=0,
                microsecond=0,
            )
        return target.replace(hour=9, minute=0, second=0, microsecond=0)

    elif "sunday" in lower:
        days_until = (6 - now.weekday()) % 7
        if days_until == 0:
            days_until = 7
        target = now + timedelta(days=days_until)
        if extracted_time:
            return target.replace(
                hour=extracted_time[0],
                minute=extracted_time[1],
                second=0,
                microsecond=0,
            )
        return target.replace(hour=9, minute=0, second=0, microsecond=0)

    # Try dateutil parser as fallback
    try:
        from dateutil import parser as dateutil_parser

        parsed = dateutil_parser.parse(deadline_str, fuzzy=True, dayfirst=False)

        # If no specific time was in the original string, use extracted or default
        if (
            parsed.hour == 0
            and parsed.minute == 0
            and ":" not in deadline_str
            and not any(x in lower for x in ["am", "pm", "noon", "midnight"])
        ):
            if extracted_time:
                parsed = parsed.replace(
                    hour=extracted_time[0], minute=extracted_time[1]
                )
            else:
                parsed = parsed.replace(hour=9, minute=0)  # Default to 9 AM

        return parsed
    except Exception:
        pass

    return None


def _extract_time(text: str) -> Optional[tuple]:
    """Extract time from text like '2pm', '2:30 PM', '14:30', 'at 3 o'clock'."""
    text = text.lower()

    # Match patterns like "2:30 pm", "2:30pm", "14:30"
    time_match = re.search(r"(\d{1,2}):(\d{2})\s*(am|pm)?", text, re.IGNORECASE)
    if time_match:
        hour = int(time_match.group(1))
        minute = int(time_match.group(2))
        period = time_match.group(3)

        if period:
            period = period.lower()
            if period == "pm" and hour != 12:
                hour += 12
            elif period == "am" and hour == 12:
                hour = 0

        return (hour, minute)

    # Match patterns like "2pm", "2 pm", "2 PM"
    hour_match = re.search(r"(\d{1,2})\s*(am|pm)", text, re.IGNORECASE)
    if hour_match:
        hour = int(hour_match.group(1))
        period = hour_match.group(2).lower()

        if period == "pm" and hour != 12:
            hour += 12
        elif period == "am" and hour == 12:
            hour = 0

        return (hour, 0)

    # Match "noon" or "midnight"
    if "noon" in text:
        return (12, 0)
    if "midnight" in text:
        return (0, 0)

    return None
