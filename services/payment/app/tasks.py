import time

from celery_app import celery_app


@celery_app.task(name="payment.add")
def add(x, y):
    """Add two numbers together."""
    return x + y


@celery_app.task(name="payment.slow")
def slow(seconds):
    """Sleep for the provided duration and return it."""
    time.sleep(seconds)
    return seconds
