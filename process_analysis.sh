#!/bin/bash

# Function to print detailed process info
print_detailed_info() {
  pid=$1
  if [ -d "/proc/$pid" ]; then
    echo "------------------------------------------------------------------"
    echo ">> PID       : $pid"
    echo ">> User      : $(ps -p $pid -o user= 2>/dev/null || echo 'N/A')"
    echo ">> CPU%      : $(ps -p $pid -o %cpu= 2>/dev/null || echo 'N/A')"
    echo ">> MEM%      : $(ps -p $pid -o %mem= 2>/dev/null || echo 'N/A')"
    echo ">> Uptime    : $(ps -p $pid -o time= 2>/dev/null || echo 'N/A')"
    echo ">> Command   : $(ps -p $pid -o comm= 2>/dev/null || echo 'N/A')"
    echo ">> Start Time: $(ps -p $pid -o lstart= 2>/dev/null || echo 'N/A')"
    
    # Current working directory
    cwd=$(readlink /proc/$pid/cwd 2>/dev/null || echo 'N/A')
    echo ">> CWD       : $cwd"
    
    # Full command line
    cmdline=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null || echo 'N/A')
    echo ">> Cmdline   : $cmdline"
    
    # Threads count
    threads=$(grep Threads /proc/$pid/status 2>/dev/null | awk '{print $2}')
    [ -z "$threads" ] && threads="N/A"
    echo ">> Threads   : $threads"
    
    # Open file descriptors count
    if [ -d "/proc/$pid/fd" ]; then
      open_files=$(ls /proc/$pid/fd 2>/dev/null | wc -l)
    else
      open_files="N/A"
    fi
    echo ">> Open Files: $open_files"
    
    # Children process count
    children=$(ps -o pid --ppid $pid --no-headers 2>/dev/null | wc -l)
    echo ">> Children  : $children"
  else
    echo "Process $pid does not exist anymore."
  fi
  echo ""
}

# Default values
MODE="all"
TOP_N=5

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    cpu|memory)
      MODE="$1"
      shift
      ;;
    -n)
      TOP_N="$2"
      shift 2
      ;;
    *)
      echo "Usage: $0 [cpu|memory] [-n number_of_processes]"
      exit 1
      ;;
  esac
done

# CPU analysis
if [[ "$MODE" == "cpu" || "$MODE" == "all" ]]; then
  echo "========== Top $TOP_N processes by CPU usage =========="
  ps -eo pid,user,ppid,%cpu,%mem,time,comm --sort=-%cpu | head -n $((TOP_N + 1))

  echo ""
  echo "========== Detailed info for Top $TOP_N CPU-consuming processes =========="
  cpu_pids=$(ps -eo pid,%cpu --sort=-%cpu | awk 'NR>1 {print $1}' | head -n $TOP_N)
  for pid in $cpu_pids; do
    print_detailed_info $pid
  done
fi

# Memory analysis
if [[ "$MODE" == "memory" || "$MODE" == "all" ]]; then
  echo "========== Top $TOP_N processes by Memory usage =========="
  ps -eo pid,user,ppid,%cpu,%mem,time,comm --sort=-%mem | head -n $((TOP_N + 1))

  echo ""
  echo "========== Detailed info for Top $TOP_N Memory-consuming processes =========="
  mem_pids=$(ps -eo pid,%mem --sort=-%mem | awk 'NR>1 {print $1}' | head -n $TOP_N)
  for pid in $mem_pids; do
    print_detailed_info $pid
  done
fi
