#! /usr/bin/env python3
from contextlib import suppress
import csv
from datetime import datetime, timedelta
import itertools
import json
import multiprocessing
import subprocess

def human_readable(timedelta_):
    """Human readable string from timedelta"""
    seconds = int(timedelta_.total_seconds())
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

def main():
    """Process log files"""
    # Load events from cloud init dump
    # --------------------------------
    events = []
    bash_process = subprocess.run(["/bin/bash", "-c", "cloud-init analyze dump"], stdout=subprocess.PIPE, check=True)
    cloud_init_log_events = json.loads(bash_process.stdout.decode("utf8"))

    # Get build start time
    initial_timestamp = min([entry["timestamp"] for entry in cloud_init_log_events])
    events.append({"timestamp": datetime.fromtimestamp(initial_timestamp), "level": "SUCCESS", "message": "Started build"})

    # Get initial cloud-init setup time
    with suppress(IndexError):
        _ = list(filter(lambda x: x["event_type"] == "start" and x["name"] == "azure-ds/write_files", cloud_init_log_events))[0]
        end_entries = list(filter(lambda x: x["event_type"] == "finish" and x["name"] == "azure-ds/write_files", cloud_init_log_events))
        if end_entries:
            events.append({"timestamp": datetime.fromtimestamp(end_entries[0]["timestamp"]), "level": end_entries[0]["result"], "message": "File creation"})
        else:
            events.append({"timestamp": datetime.now(), "level": "RUNNING", "message": "File creation"})

    # Get initial cloud-init setup time
    with suppress(IndexError):
        _ = list(filter(lambda x: x["event_type"] == "start" and x["name"] == "modules-config", cloud_init_log_events))[0]
        end_entries = list(filter(lambda x: x["event_type"] == "finish" and x["name"] == "modules-config", cloud_init_log_events))
        if end_entries:
            events.append({"timestamp": datetime.fromtimestamp(end_entries[0]["timestamp"]), "level": end_entries[0]["result"], "message": "Cloud-init initial setup"})
        else:
            events.append({"timestamp": datetime.now(), "level": "RUNNING", "message": "Cloud-init initial setup"})

    # Get package install/update time
    with suppress(IndexError):
        _ = list(filter(lambda x: x["event_type"] == "start" and x["name"] == "modules-final/config-package-update-upgrade-install", cloud_init_log_events))[0]
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
    bash_process = subprocess.run(["grep", ">===", "/var/log/cloud-init-output.log"], stdout=subprocess.PIPE, check=True)
    for event in bash_process.stdout.decode("utf8").split("\n"):
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
    previous_event_time = None
    for event in events:
        time_elapsed = ""
        if previous_event_time:
            if event["message"] == "Finished build":
                time_elapsed = event["timestamp"] - datetime.fromtimestamp(initial_timestamp)
            else:
                time_elapsed = event["timestamp"] - previous_event_time
        if isinstance(time_elapsed, timedelta):
            time_elapsed = ": {}".format(human_readable(time_elapsed))
        print("[{}: {: <7}] {}{}".format(event["timestamp"].strftime("%Y-%m-%d %H:%M:%S"), event["level"], event["message"], time_elapsed))
        previous_event_time = event["timestamp"]


    # Check system performance
    # ------------------------
    mem_usage, cpu_usage, mem_bytes = [], [], []
    with suppress(FileNotFoundError):
        with open("/installation/performance_log.csv", "r") as system_log:
            first_lines = list(itertools.islice(system_log, 10))
        with suppress(IndexError):
            lineskip = [idx for idx, line in enumerate(first_lines) if line.startswith('"used"')][0] # skip version info in the header
            with open("/installation/performance_log.csv", "r") as system_log:
                for row in csv.DictReader(itertools.islice(system_log, lineskip, None), delimiter=","):
                    if build_end_status:
                        timestamp = datetime.strptime("{}-{}".format(datetime.today().year, row["time"]), "%Y-%d-%m %H:%M:%S")
                        if timestamp > build_end_status[0]:
                            break
                    mem_bytes.append((float(row["used"]) + float(row["free"]) + float(row["buff"]) + float(row["cach"])))
                    mem_usage.append(100 * float(row["used"]) / mem_bytes[-1])
                    cpu_usage.append(100 - float(row["idl"]))

    with suppress(ZeroDivisionError):
        mem_gb = (sum(mem_bytes) / len(mem_bytes)) / (1000 * 1000 * 1000)
        n_cores = multiprocessing.cpu_count()
        timestamp = build_end_status[0] if build_end_status else datetime.now()
        prefix = "[{}: {: <7}]".format(timestamp.strftime("%Y-%m-%d %H:%M:%S"), "INFO")
        # Memory
        print("{} Memory available: {:d} GB".format(prefix, int(mem_gb)))
        mem_mean, mem_min, mem_max = sum(mem_usage) / len(mem_usage), min(mem_usage), max(mem_usage)
        print("{} ..... mean usage: {: >6.2f}% => {: >4.1f} GB".format(prefix, mem_mean, mem_gb * mem_mean / 100))
        print("{} ...... min usage: {: >6.2f}% => {: >4.1f} GB".format(prefix, mem_min, mem_gb * mem_min / 100))
        print("{} ...... max usage: {: >6.2f}% => {: >4.1f} GB".format(prefix, mem_max, mem_gb * mem_max / 100))
        # CPU
        print("{} CPU available: {:d} cores".format(prefix, int(n_cores)))
        cpu_mean, cpu_min, cpu_max = sum(cpu_usage) / len(cpu_usage), min(cpu_usage), max(cpu_usage)
        print("{} ..... mean usage: {: >6.2f}% => {: >4.1f} cores".format(prefix, cpu_mean, n_cores * cpu_mean / 100))
        print("{} ...... min usage: {: >6.2f}% => {: >4.1f} cores".format(prefix, cpu_min, n_cores * cpu_min / 100))
        print("{} ...... max usage: {: >6.2f}% => {: >4.1f} cores".format(prefix, cpu_max, n_cores * cpu_max / 100))

if __name__ == "__main__":
    main()
