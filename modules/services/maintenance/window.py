from datetime import time


def active(window, now):
    start = time.fromisoformat(window["start"])
    end = time.fromisoformat(window["end"])
    inside = start <= now < end if start <= end else now >= start or now < end
    return window["enabled"] and inside
