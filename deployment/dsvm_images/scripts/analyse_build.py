#! /usr/bin/env python3
from contextlib import suppress
import csv
from datetime import datetime
import itertools
import json
import subprocess

def human_readable(timedelta):
    seconds = int(timedelta.total_seconds())
    days, seconds = divmod(seconds, 86400)
    hours, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)
    if days > 0:
        return f"{days:d}d{hours:d}h{minutes:d}m{seconds:d}s"
    if hours > 0:
        return f"{hours:d}h{minutes:d}m{seconds:d}s"
    if minutes > 0:
        return f"{minutes:d}m{seconds:d}s"
    return f"{seconds:d}s"

# Load events from cloud init dump
# --------------------------------
events = []
sp = subprocess.run(["/bin/bash", "-c", "cloud-init analyze dump"], stdout=subprocess.PIPE)
cloud_init_log_events = json.loads(sp.stdout.decode("utf8"))

# Get build start time
initial_timestamp = min([entry["timestamp"] for entry in cloud_init_log_events])
events.append({"timestamp": datetime.fromtimestamp(initial_timestamp), "level": "SUCCESS", "message": "Started build"})

# Get initial cloud-init setup time
with suppress(IndexError):
    start_entry = list(filter(lambda x: x["event_type"] == "start" and x["name"] == "azure-ds/write_files", cloud_init_log_events))[0]
    end_entries = list(filter(lambda x: x["event_type"] == "finish" and x["name"] == "azure-ds/write_files", cloud_init_log_events))
    if end_entries:
        events.append({"timestamp": datetime.fromtimestamp(end_entries[0]["timestamp"]), "level": end_entries[0]["result"], "message": "File creation"})
    else:
        events.append({"timestamp": datetime.now(), "level": "RUNNING", "message": "File creation"})

# Get initial cloud-init setup time
with suppress(IndexError):
    start_entry = list(filter(lambda x: x["event_type"] == "start" and x["name"] == "modules-config", cloud_init_log_events))[0]
    end_entries = list(filter(lambda x: x["event_type"] == "finish" and x["name"] == "modules-config", cloud_init_log_events))
    if end_entries:
        events.append({"timestamp": datetime.fromtimestamp(end_entries[0]["timestamp"]), "level": end_entries[0]["result"], "message": "Cloud-init initial setup"})
    else:
        events.append({"timestamp": datetime.now(), "level": "RUNNING", "message": "Cloud-init initial setup"})

# Get package install/update time
with suppress(IndexError):
    start_entry = list(filter(lambda x: x["event_type"] == "start" and x["name"] == "modules-final/config-package-update-upgrade-install", cloud_init_log_events))[0]
    end_entries = list(filter(lambda x: x["event_type"] == "finish" and x["name"] == "modules-final/config-package-update-upgrade-install", cloud_init_log_events))
    if end_entries:
        events.append({"timestamp": datetime.fromtimestamp(end_entries[0]["timestamp"]), "level": end_entries[0]["result"], "message": "Installing/updating Ubuntu packages"})
    else:
        events.append({"timestamp": datetime.now(), "level": "RUNNING", "message": "Installing/updating Ubuntu packages"})

# Get total time
build_end_status = None
with suppress(IndexError):
    entry = list(filter(lambda x: x["event_type"] == "finish" and x["name"] == "modules-final", cloud_init_log_events))[0]
    events.append({"timestamp": datetime.fromtimestamp(entry["timestamp"]), "level": entry["result"], "message": "Finished build"})
    if entry["result"]:
        build_end_status = (datetime.fromtimestamp(entry["timestamp"] - 1), entry["result"])


# Load events from runcmd echo statements
# ---------------------------------------
runcmd_log_events = []
sp = subprocess.run(["grep", ">===", "/var/log/cloud-init-output.log"], stdout=subprocess.PIPE)
for event in sp.stdout.decode("utf8").split("\n"):
    with suppress(IndexError):
        start_time = event.split(" ")[1]
        message = event.split(start_time)[1].replace("===<", "").strip()
        runcmd_log_events.append({"start_time": int(start_time), "end_time": None, "message": message})
for event, next_event in zip(runcmd_log_events[:-1], runcmd_log_events[1:]):
    events.append({"timestamp": datetime.fromtimestamp(next_event["start_time"]), "level": "SUCCESS", "message": event["message"]})

# Add in progress task
if runcmd_log_events:
    current_task = runcmd_log_events[-1]["message"]
    if build_end_status:
        events.append({"timestamp": build_end_status[0], "level": build_end_status[1], "message": current_task})
    else:
        events.append({"timestamp": datetime.now(), "level": "RUNNING", "message": current_task})

# Log all events
# --------------
events.sort(key=lambda x: x["timestamp"])
last_event_time = None
for event in events:
    time_elapsed = ""
    if last_event_time:
        if event["message"] == "Finished build":
            time_elapsed = event["timestamp"] - datetime.fromtimestamp(initial_timestamp)
        else:
            time_elapsed = event["timestamp"] - last_event_time
    if time_elapsed:
        time_elapsed = ": {}".format(human_readable(time_elapsed))
    print("[{}: {: <7}] {}{}".format(event["timestamp"].strftime("%Y-%m-%d %H:%M:%S"), event["level"], event["message"], time_elapsed))
    last_event_time = event["timestamp"]


# Check system performance
# ------------------------
mem_usage, cpu_usage = [], []
with suppress(FileNotFoundError):
    with open("/installation/performance_log.csv", "r") as system_log:
        first_lines = list(itertools.islice(system_log, 10))
    with suppress(IndexError):
        lineskip = [idx for idx, line in enumerate(first_lines) if line.startswith('"used"')][0] # skip version info in the header
        with open("/installation/performance_log.csv", "r") as system_log:
            for row in csv.DictReader(itertools.islice(system_log, lineskip, None), delimiter=","):
                mem_usage.append(100 * float(row["used"]) / (float(row["used"]) + float(row["free"])))
                cpu_usage.append(100 - float(row["idl"]))
with suppress(ZeroDivisionError):
    prefix = "[{}: {: <7}]".format(datetime.now().strftime("%Y-%m-%d %H:%M:%S"), "INFO")
    print("{} {}".format(prefix, "Memory usage: Mean ({:.2f}%) Max ({:.2f}%) Min ({:.2f}%)".format(sum(mem_usage) / len(mem_usage), max(mem_usage), min(mem_usage))))
    print("{} {}".format(prefix, "CPU usage: Mean ({:.2f}%) Max ({:.2f}%) Min ({:.2f}%)".format(sum(cpu_usage) / len(cpu_usage), max(cpu_usage), min(cpu_usage))))
