import os
from celery import Celery
from kombu import Queue

redis_password = os.getenv("REDIS_PASSWORD", "")
default_broker = (
    f"redis://:{redis_password}@redis:6379/0" if redis_password else "redis://redis:6379/0"
)
broker = os.getenv("REDIS_URL", default_broker)

celery_app = Celery(
    __name__,
    broker=broker,
    backend=broker,
    include=["tasks"],
)

queue_name = os.getenv("CELERY_DEFAULT_QUEUE", "payment-tasks")

celery_app.conf.update(
    task_acks_late=True,
    worker_prefetch_multiplier=1,
    enable_utc=True,
    timezone="UTC",
    task_default_queue=queue_name,
    task_queues=(Queue(queue_name),),
)
