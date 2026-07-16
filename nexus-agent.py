#!/usr/bin/env python3

import os, sys, subprocess, socket, platform
from datetime import datetime

C  = "\033[96m"; G = "\033[92m"; Y = "\033[93m"
R  = "\033[91m"; B = "\033[1m";  D = "\033[2m"
N  = "\033[0m"

BANNER = (
    f"\n  {C}nexus  •  System Shell{N}\n"
    f"  {D}{'─'*50}{N}\n"
)

def get_sysinfo():
    info = {}
    try:
        with open("/proc/uptime") as f:
            s = float(f.read().split()[0])
            info["uptime"] = f"{int(s//3600)}h {int((s%3600)//60)}m"
        with open("/proc/loadavg") as f:
            info["load"] = " ".join(f.read().split()[:3])
        mem = subprocess.run(["free", "-h"], capture_output=True, text=True)
        info["memory"] = mem.stdout.split("\n")[1] if mem.stdout else "?"
        disk = subprocess.run(["df", "-h", "/"], capture_output=True, text=True)
        info["disk"] = disk.stdout.split("\n")[1] if disk.stdout else "?"
        info["hostname"] = socket.gethostname()
        info["kernel"]   = platform.release()
        ip = subprocess.run(["hostname", "-I"], capture_output=True, text=True)
        info["ip"] = ip.stdout.strip().split()[0] if ip.stdout.strip() else "no IP"
    except Exception as e:
        info["error"] = str(e)
    return info

def print_sysinfo():
    i = get_sysinfo()
    mem_parts = i.get('memory', '').split()
    mem_str = f"{mem_parts[2]}/{mem_parts[1]}" if len(mem_parts) >= 3 else i.get('memory', '?')
    print(
        f"  {D}host {i.get('hostname','?')}  •  "
        f"kernel {i.get('kernel','?')}  •  "
        f"ip {i.get('ip','?')}  •  "
        f"up {i.get('uptime','?')}{N}"
    )
    print(
        f"  {D}load {i.get('load','?')}  •  "
        f"mem {mem_str}  •  "
        f"disk {i.get('disk','?')}{N}\n"
    )

def run_cmd(cmd: str) -> str:
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        out = (r.stdout or "") + (r.stderr or "")
        return out.strip()[:3000] or "(no output)"
    except subprocess.TimeoutExpired:
        return "[nexus] Command timed out (30s)"
    except Exception as e:
        return f"[nexus] Error: {e}"

CMDS = {
    "status":  "uptime && free -h && df -h /",
    "ps":      "ps aux --sort=-%cpu | head -20",
    "net":     "ip addr show && echo '---' && ss -tuln",
    "top":     "top -bn1 | head -25",
    "log":     "journalctl -n 30 --no-pager",
    "disk":    "df -h && echo '---' && lsblk",
    "mem":     "free -h && cat /proc/meminfo | head -10",
}

def execute(input: str) -> str:
    lower = input.lower().strip()
    for key, cmd in CMDS.items():
        if key in lower:
            return run_cmd(cmd)
    return run_cmd(input)

def status_bar():
    i = get_sysinfo()
    ts = datetime.now().strftime("%H:%M:%S")
    mem_parts = i.get('memory', '').split()
    mem_str = f"{mem_parts[2]}/{mem_parts[1]}" if len(mem_parts) >= 3 else i.get('memory', '?')
    print(
        f"{D}{ts}  "
        f"load {i.get('load','?').split()[0]}  "
        f"mem {mem_str}  "
        f"up {i.get('uptime','?')}{N}"
    )

def main():
    startup = "/etc/nexus/startup.sh"
    if os.path.exists(startup):
        subprocess.run(["bash", startup], check=False)

    print(BANNER)
    print_sysinfo()

    while True:
        try:
            status_bar()
            user_input = input(f"  {C}❯{N} ").strip()
        except (EOFError, KeyboardInterrupt):
            print(f"\n  {D}shutdown  •  goodbye{N}")
            sys.exit(0)

        if not user_input:
            continue

        if user_input.lower() in ("exit", "quit", "shutdown", "poweroff"):
            print(f"  {D}shutdown  •  goodbye{N}")
            sys.exit(0)

        if user_input.lower() == "clear":
            os.system("clear")
            print(BANNER)
            continue

        if user_input.lower() in ("sysinfo", "status"):
            print_sysinfo()
            continue

        if user_input.lower() == "help":
            print(f"\n  {C}commands{N}")
            print(f"  {D}status{N}   system information")
            print(f"  {D}ps{N}       process list")
            print(f"  {D}net{N}      network info")
            print(f"  {D}top{N}      process monitor")
            print(f"  {D}log{N}      system logs")
            print(f"  {D}disk{N}     disk usage")
            print(f"  {D}mem{N}      memory info")
            print(f"  {D}clear{N}    clear screen")
            print(f"  {D}exit{N}     shutdown")
            print(f"  {D}help{N}     this message")
            print(f"  {D}<cmd>{N}    run any shell command\n")
            continue

        out = execute(user_input)
        print(f"\n{out}\n")

if __name__ == "__main__":
    main()
