import os
import socket
import time
import psutil
from loguru import logger
from prometheus_client import start_http_server, Gauge

# cpu_gauge = Gauge('system_cpu_usage', 'CPU usage in percent')
# memory_gauge = Gauge('system_memory_usage', 'Memory usage in percent')
# disk_gauge = Gauge('system_disk_usage', 'Disk usage in percent')

cpu_gauge = Gauge('cpu_usage', 'CPU usage per core in percent', ['hostname', 'cpu_core'])
memory_gauge = Gauge('memory_usage', 'Memory usage in percent', ['hostname'])
disk_gauge = Gauge('disk_usage', 'Disk usage in percent', ['hostname'])


hostname = socket.gethostname()

def collect_metrics(collect_metric_time: int):
    while True:
        # cpu_usages = psutil.cpu_percent(interval=1, percpu=True)
        # for i, usage in enumerate(cpu_usages):
        #     # Update the gauge metric with the current CPU usage, labeled by hostname and CPU core index
        #     logger.info(f"cpu_usage: {cpu_usage}")
        #     cpu_gauge.labels(hostname=hostname, cpu_core=str(i)).set(usage)

        cpu_usages = psutil.cpu_percent(interval=1)
        logger.info(f"cpu_usages infor: {cpu_usages}")
        cpu_gauge.labels(hostname=hostname).set(cpu_usages)

        # Collect Memory usage
        memory_usage = psutil.virtual_memory().percent
        logger.info(f"virtual_memory: {memory_usage}")
        memory_gauge.labels(hostname=hostname).set(memory_usage)

        # Collect Disk usage
        disk_usage = psutil.disk_usage('/').percent
        logger.info(f"disk_usage: {disk_usage}")
        disk_gauge.labels(hostname=hostname).set(disk_usage)
        # Wait for a defined interval (e.g., 3 seconds) before collecting metrics again
        time.sleep(collect_metric_time)

        # Collect CPU, Memory, and Disk usage
        # cpu_usage = psutil.cpu_percent(interval=1)
        # memory_usage = psutil.virtual_memory().percent
        # disk_usage = psutil.disk_usage('/').percent
        #
        # logger.info(f"cpu_usage: {cpu_usage}")
        # logger.info(f"memory_usage: {memory_usage}")
        # logger.info(f"disk_usage: {disk_usage}")
        #
        # # Update Prometheus metrics
        # cpu_gauge.set(cpu_usage)
        # memory_gauge.set(memory_usage)
        # disk_gauge.set(disk_usage)
        #
        # logger.info(f"cpu_gauge: {cpu_gauge._get_metric()}")
        # logger.info(f"memory_gauge: {memory_gauge._get_metric()}")
        # logger.info(f"disk_gauge: {disk_gauge._get_metric()}")
        #
        # # Wait for 3 seconds before collecting metrics again
        # logger.info("sleeping")
        # time.sleep(collect_metric_time)
