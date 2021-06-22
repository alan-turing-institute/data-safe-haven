#! /usr/bin/env python3
from contextlib import suppress
import csv
from datetime import datetime, timedelta
import glob
import json
import multiprocessing
import subprocess


def human_readable(timedelta_):
    """Human readable string from timedelta"""
    if not isinstance(timedelta_, timedelta):
        return ""
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


def log(timestamp, level, message):
    print(f"[{timestamp.strftime(r'%Y-%m-%d %H:%M:%S')}: {level:<7}] {message}")


def main():
    """Process log files"""
    # Load events from cloud init dump
    # --------------------------------
    events = []
    bash_process = subprocess.run(["/bin/bash", "-c", "cloud-init analyze dump"], stdout=subprocess.PIPE, check=True)
    cloud_init_log_events = json.loads(bash_process.stdout.decode("utf8"))

    # Use the time at which write_files runs as an indication of when cloud-init started
    # This avoids possible clock-skew issues that occurred when trying to use earlier timestamps
    with suppress(IndexError):
        _ = list(filter(lambda x: x["event_type"] == "start" and x["name"] == "azure-ds/write_files", cloud_init_log_events))[0]
        end_entries = list(filter(lambda x: x["event_type"] == "finish" and x["name"] == "azure-ds/write_files", cloud_init_log_events))
        if end_entries:
            events.append({"timestamp": datetime.fromtimestamp(end_entries[0]["timestamp"]), "level": end_entries[0]["result"], "message": "Build started"})
        else:
            events.append({"timestamp": datetime.now(), "level": "RUNNING", "message": "Build started"})

    # Get initial cloud-init setup time
    with suppress(IndexError):
        end_entries = list(filter(lambda x: x["event_type"] == "finish" and x["name"] == "modules-config", cloud_init_log_events))
        if end_entries:
            events.append({"timestamp": datetime.fromtimestamp(end_entries[0]["timestamp"]), "level": end_entries[0]["result"], "message": "Running cloud-init modules"})
        else:
            events.append({"timestamp": datetime.now(), "level": "RUNNING", "message": "Running cloud-init modules"})

    # Get package install/update time
    with suppress(IndexError):
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
    with suppress(subprocess.CalledProcessError):
        bash_process = subprocess.run(["grep", ">===", "/var/log/cloud-init-output.log"], stdout=subprocess.PIPE, check=True)
        for event in bash_process.stdout.decode("utf8").split("\n"):
            with suppress(IndexError, ValueError):
                start_time = event.split(" ")[1]
                message = event.split(start_time)[1].replace("===<", "").strip()
                runcmd_log_events.append({"start_time": int(start_time), "end_time": None, "message": message})
        for event, next_event in zip(runcmd_log_events[:-1], runcmd_log_events[1:]):
            events.append({"timestamp": datetime.fromtimestamp(next_event["start_time"]), "level": "SUCCESS", "message": event["message"]})

    # Add currently running task
    # --------------------------
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
                time_elapsed = event["timestamp"] - events[0]["timestamp"]
            else:
                time_elapsed = event["timestamp"] - previous_event_time
        log(event["timestamp"], event["level"], f"{event['message']}: {human_readable(time_elapsed)}")
        previous_event_time = event["timestamp"]

    # Check system performance
    # ------------------------
    n_cores = multiprocessing.cpu_count()
    mem_usage, cpu_usage = [], []
    with suppress(FileNotFoundError):
        with open("/opt/monitoring/performance_log.csv", "r") as system_log:
            for row in csv.DictReader(system_log):
                if build_end_status:
                    timestamp = datetime.strptime(row["now"], r"%Y-%m-%d %H:%M:%S %Z")
                    if timestamp > build_end_status[0]:
                        break
                mem_usage.append(100 * float(row["mem.used"]) / float(row["mem.total"]))
                cpu_usage.append(100 - float(row["cpu.idle"]))
    # Calculate total memory using the last row
    try:
        mem_gb = float(row["mem.total"]) / (1000 * 1000 * 1000)
    except UnboundLocalError:
        mem_gb = 0

    timestamp = build_end_status[0] if build_end_status else datetime.now()
    with suppress(ZeroDivisionError):
        # Memory
        log(timestamp, "INFO", f"Memory available: {int(round(mem_gb)):d} GB")
        mem_mean, mem_min, mem_max = sum(mem_usage) / len(mem_usage), min(mem_usage), max(mem_usage)
        log(timestamp, "INFO", f"..... mean usage: {mem_mean:>6.2f}% => {(mem_gb * mem_mean / 100):>4.1f} GB")
        log(timestamp, "INFO", f"...... min usage: {mem_min:>6.2f}% => {mem_gb * mem_min / 100:>4.1f} GB")
        log(timestamp, "INFO", f"...... max usage: {mem_max:>6.2f}% => {mem_gb * mem_max / 100:>4.1f} GB")
        # CPU
        log(timestamp, "INFO", f"CPU available: {int(n_cores):d} cores")
        cpu_mean, cpu_min, cpu_max = sum(cpu_usage) / len(cpu_usage), min(cpu_usage), max(cpu_usage)
        log(timestamp, "INFO", f"..... mean usage: {cpu_mean:>6.2f}% => {(n_cores * cpu_mean / 100):>4.1f} cores")
        log(timestamp, "INFO", f"...... min usage: {cpu_min:>6.2f}% => {(n_cores * cpu_min / 100):>4.1f} cores")
        log(timestamp, "INFO", f"...... max usage: {cpu_max:>6.2f}% => {(n_cores * cpu_max / 100):>4.1f} cores")

    # Check python installations
    # --------------------------
    with suppress(FileNotFoundError):
        for fname in glob.glob("/opt/monitoring/python-safety-check*.json"):
            with open(fname, "r") as f_safety_check:
                packages = json.load(f_safety_check)
            if packages:
                python_version = fname.split("-")[3].replace(".json", "")
                log(timestamp, "WARNING", f"Safety check found problems with Python {python_version}")
            for package in packages:
                print(f"    {package[0]} [{package[2]}] is affected by issue {package[4]} (for versions {package[1]})")
                lines = package[3].replace(". ", ".\n")
                for sentence in lines.split("\n"):
                    print(f"       {sentence}")


if __name__ == "__main__":
    main()