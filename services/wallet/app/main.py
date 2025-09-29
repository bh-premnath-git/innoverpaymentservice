import time, os, sys
print(f"Starting {os.getenv('SERVICE_NAME','svc-unknown')}…", flush=True)
i = 0
while True:
    i += 1
    print(f"[tick {i}] alive", flush=True)
    time.sleep(5)