import time

from celery_app import celery_app


@celery_app.task(name="ledger.add")
def add(x, y):
    """Add two numbers together."""
    return x + y


@celery_app.task(name="ledger.slow")
def slow(seconds):
    """Sleep for the provided duration and return it."""
    time.sleep(seconds)
    return seconds
