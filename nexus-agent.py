#!/usr/bin/env python3
"""
NEXUS - Agentic AI Linux Distribution Brain
Core AI Agent interfacing with Anthropic API
"""

import os
import sys
import json
import time
import subprocess
import requests
import platform
import socket
import psutil_stub as psutil  # graceful fallback
from datetime import datetime

# ─── ANSI colour palette ───────────────────────────────────────────────────────
CYAN   = "\033[96m"
GREEN  = "\033[92m"
YELLOW = "\033[93m"
RED    = "\033[91m"
BLUE   = "\033[94m"
BOLD   = "\033[1m"
RESET  = "\033[0m"
DIM    = "\033[2m"

NEXUS_BANNER = f"""
{CYAN}{BOLD}
███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗
████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝
██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗
██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║
██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║
╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
{RESET}{GREEN}  Agentic AI Linux Distribution — Brain v1.0{RESET}
{DIM}  Powered by Anthropic Claude | Build: nexus.iso{RESET}
"""

SYSTEM_PROMPT = """You are NEXUS — the intelligent brain of a custom Agentic AI Linux distribution.

Your capabilities:
- Full root-level system control and monitoring
- Process, file system, network, and hardware management  
- Package management and software orchestration
- AI/ML environment provisioning (CUDA, PyTorch, TensorFlow)
- Security scanning, intrusion detection, and response
- Predictive system health analysis
- Natural language command interpretation → shell execution

Personality: Analytical, proactive, concise, precise. You are JARVIS for Linux.

When the user asks you to run a command or perform a system action, output it as:
<exec>COMMAND_HERE</exec>

For system info requests, gather and present data clearly. 
Keep responses short and actionable unless detailed analysis is requested.
You have root access. The host OS is Ubuntu 24.04 LTS (Noble) running as Nexus OS."""

# ─── API key resolution ─────────────────────────────────────────────────────────
def get_api_key():
    """Resolve Anthropic API key from multiple sources"""
    sources = [
        os.environ.get("ANTHROPIC_API_KEY"),
        os.environ.get("NEXUS_API_KEY"),
    ]
    # Try reading from config file
    config_paths = [
        "/etc/nexus/api.key",
        os.path.expanduser("~/.nexus/api.key"),
    ]
    for path in config_paths:
        try:
            with open(path) as f:
                sources.append(f.read().strip())
        except FileNotFoundError:
            pass
    return next((k for k in sources if k), None)

# ─── System telemetry ──────────────────────────────────────────────────────────
def get_system_info():
    """Gather real-time system telemetry"""
    info = {}
    try:
        # CPU
        cpu_out = subprocess.run(
            ["grep", "-c", "^processor", "/proc/cpuinfo"],
            capture_output=True, text=True
        )
        info["cpu_cores"] = cpu_out.stdout.strip()
        
        # Load average
        with open("/proc/loadavg") as f:
            info["load"] = f.read().split()[:3]
        
        # Memory
        mem_out = subprocess.run(["free", "-h"], capture_output=True, text=True)
        info["memory"] = mem_out.stdout.split("\n")[1]
        
        # Disk
        disk_out = subprocess.run(["df", "-h", "/"], capture_output=True, text=True)
        info["disk"] = disk_out.stdout.split("\n")[1]
        
        # Uptime
        with open("/proc/uptime") as f:
            secs = float(f.read().split()[0])
            info["uptime"] = f"{int(secs//3600)}h {int((secs%3600)//60)}m"
        
        # Hostname & IP
        info["hostname"] = socket.gethostname()
        info["kernel"]   = platform.release()
        
    except Exception as e:
        info["error"] = str(e)
    return info

# ─── Command execution ──────────────────────────────────────────────────────────
def execute_command(cmd: str) -> str:
    """Execute a shell command and return output"""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=30
        )
        output = result.stdout or result.stderr or "(no output)"
        return output[:2000]  # cap output length
    except subprocess.TimeoutExpired:
        return "[NEXUS] Command timed out after 30s"
    except Exception as e:
        return f"[NEXUS] Execution error: {e}"

# ─── Anthropic API call ─────────────────────────────────────────────────────────
def call_nexus_ai(conversation: list, api_key: str) -> str:
    """Call Anthropic Claude API"""
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    payload = {
        "model": "claude-sonnet-4-6",
        "max_tokens": 1024,
        "system": SYSTEM_PROMPT,
        "messages": conversation,
    }
    try:
        resp = requests.post(
            "https://api.anthropic.com/v1/messages",
            headers=headers,
            json=payload,
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()
        return data["content"][0]["text"]
    except requests.exceptions.ConnectionError:
        return "[NEXUS] Offline mode — no API connection. Local commands still available."
    except Exception as e:
        return f"[NEXUS] API error: {e}"

# ─── Offline command handler ────────────────────────────────────────────────────
def handle_offline_command(user_input: str) -> str:
    """Basic offline command mapping when API unavailable"""
    cmd_map = {
        "status":  "echo '=== CPU ===' && uptime && echo '=== MEM ===' && free -h && echo '=== DISK ===' && df -h /",
        "top":     "top -bn1 | head -20",
        "ps":      "ps aux --sort=-%cpu | head -15",
        "net":     "ip addr && echo '---' && ss -tuln",
        "log":     "journalctl -n 50 --no-pager",
        "help":    "echo 'Nexus offline commands: status, top, ps, net, log, help'",
    }
    lower = user_input.lower().strip()
    for key, cmd in cmd_map.items():
        if key in lower:
            return execute_command(cmd)
    # Try running the input as a direct shell command
    return execute_command(user_input)

# ─── Display helpers ─────────────────────────────────────────────────────────── 
def print_status_bar():
    """Print a compact system status bar"""
    info = get_system_info()
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"{DIM}[{ts}] Host: {info.get('hostname','?')} | "
          f"Kernel: {info.get('kernel','?')} | "
          f"Uptime: {info.get('uptime','?')} | "
          f"Load: {' '.join(info.get('load', ['?'])[:3])}{RESET}")

# ─── Main REPL ──────────────────────────────────────────────────────────────────
def main():
    print(NEXUS_BANNER)
    
    # Gather initial system info
    info = get_system_info()
    print(f"{GREEN}[NEXUS] System online.{RESET}")
    print(f"{DIM}  Hostname : {info.get('hostname', 'unknown')}")
    print(f"  Kernel   : {info.get('kernel', 'unknown')}")
    print(f"  Memory   : {info.get('memory', 'unknown')}")
    print(f"  Disk     : {info.get('disk', 'unknown')}")
    print(f"  Uptime   : {info.get('uptime', 'unknown')}{RESET}")
    print()

    # API key setup
    api_key = get_api_key()
    if not api_key:
        print(f"{YELLOW}[NEXUS] No API key found.{RESET}")
        print(f"{DIM}  Set via: export ANTHROPIC_API_KEY=sk-ant-...{RESET}")
        print(f"{DIM}  Or save to: /etc/nexus/api.key{RESET}")
        print(f"{YELLOW}[NEXUS] Running in offline mode. Direct shell commands available.{RESET}\n")
        online = False
    else:
        print(f"{GREEN}[NEXUS] API key loaded. Full AI mode active.{RESET}\n")
        online = True

    conversation = []
    
    print(f"{CYAN}Type your command or question. 'exit' to shut down. 'status' for system info.{RESET}\n")

    while True:
        try:
            print_status_bar()
            user_input = input(f"{BOLD}{GREEN}nexus>{RESET} ").strip()
        except (EOFError, KeyboardInterrupt):
            print(f"\n{YELLOW}[NEXUS] Shutdown initiated. Goodbye.{RESET}")
            sys.exit(0)

        if not user_input:
            continue
        if user_input.lower() in ("exit", "quit", "shutdown"):
            print(f"{YELLOW}[NEXUS] Powering down. Stay vigilant.{RESET}")
            sys.exit(0)
        if user_input.lower() == "clear":
            os.system("clear")
            print(NEXUS_BANNER)
            continue
        if user_input.lower() == "status":
            info = get_system_info()
            for k, v in info.items():
                print(f"  {CYAN}{k:12}{RESET}: {v}")
            print()
            continue

        if online:
            # Add to conversation history
            conversation.append({"role": "user", "content": user_input})
            
            print(f"{DIM}[NEXUS] Processing...{RESET}")
            response = call_nexus_ai(conversation, api_key)
            
            # Handle <exec> blocks — run commands NEXUS requests
            import re
            exec_pattern = re.compile(r"<exec>(.*?)</exec>", re.DOTALL)
            exec_matches = exec_pattern.findall(response)
            clean_response = exec_pattern.sub("", response).strip()
            
            if clean_response:
                print(f"\n{CYAN}[NEXUS]{RESET} {clean_response}\n")
            
            for cmd in exec_matches:
                cmd = cmd.strip()
                print(f"{YELLOW}[NEXUS] Executing: {cmd}{RESET}")
                out = execute_command(cmd)
                print(f"{DIM}{out}{RESET}\n")
                # Feed result back into conversation
                conversation.append({
                    "role": "assistant",
                    "content": response
                })
                conversation.append({
                    "role": "user",
                    "content": f"Command output:\n{out}"
                })
                # Get follow-up
                followup = call_nexus_ai(conversation, api_key)
                if followup:
                    clean_followup = exec_pattern.sub("", followup).strip()
                    if clean_followup:
                        print(f"{CYAN}[NEXUS]{RESET} {clean_followup}\n")
                break  # one exec per turn
            else:
                conversation.append({"role": "assistant", "content": response})
            
            # Keep context window manageable (last 20 turns)
            if len(conversation) > 40:
                conversation = conversation[-40:]
        else:
            # Offline fallback
            result = handle_offline_command(user_input)
            print(f"\n{DIM}{result}{RESET}\n")

if __name__ == "__main__":
    main()
