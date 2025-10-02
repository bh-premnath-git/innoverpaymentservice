import time

from celery_app import celery_app


@celery_app.task(name="tasks.echo")
def echo(msg):
    """Echo a message back."""
    print(f"[LEDGER WORKER] Echo: {msg}")
    return msg


@celery_app.task(name="ledger.add")
def add(x, y):
    """Add two numbers together."""
    return x + y


@celery_app.task(name="ledger.slow")
def slow(seconds):
    """Sleep for the provided duration and return it."""
    time.sleep(seconds)
    return seconds
