"""Bridge between DB Card and fsrs library."""
from datetime import datetime, timezone
from fsrs import Scheduler, Card as FSRSCard, Rating, ReviewLog as FSRSReviewLog
import json


def _rating_from_int(r: int) -> Rating:
    if r == 1:
        return Rating.Again
    if r == 2:
        return Rating.Hard
    if r == 3:
        return Rating.Good
    if r == 4:
        return Rating.Easy
    return Rating.Good


def db_card_to_fsrs(fsrs_data: dict | None) -> FSRSCard:
    if fsrs_data:
        return FSRSCard.from_json(json.dumps(fsrs_data))
    return FSRSCard()


def fsrs_card_to_db_data(card: FSRSCard) -> dict:
    return json.loads(card.to_json())


def review_card(fsrs_data: dict | None, rating: int) -> tuple[dict, datetime]:
    """Apply FSRS review. Returns (new_fsrs_data, new_due_datetime)."""
    scheduler = Scheduler()
    fsrs_card = db_card_to_fsrs(fsrs_data)
    r = _rating_from_int(rating)
    new_card, review_log = scheduler.review_card(fsrs_card, r)
    due = new_card.due
    if due.tzinfo is None:
        due = due.replace(tzinfo=timezone.utc)
    return fsrs_card_to_db_data(new_card), due
