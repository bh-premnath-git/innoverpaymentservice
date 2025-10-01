import os
from celery import Celery

broker = os.getenv("REDIS_URL", "redis://redis:6379/0")

celery_app = Celery(
    __name__,
    broker=broker,
    backend=broker,
    include=["tasks"],
)

celery_app.conf.update(
    task_acks_late=True,
    worker_prefetch_multiplier=1,
    enable_utc=True,
    timezone="UTC",
)
