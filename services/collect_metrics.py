# from influxdb_client_3 import InfluxDBClient3
# import pandas
# import os
#
# database = os.getenv('INFLUX_DATABASE')
# token = os.getenv('INFLUX_TOKEN', 'xnO2hEO8Z0IS_OZip8GaaWqA-fcbl70DVPVVhrVLXTywbeXlHirmEIo3b_KNMYqY0K209984yqcHUiIFBdfMkg==')
# host="localhost"
#
# def querySQL():
#   client = InfluxDBClient3(host, database=database, token=token)
#   table = client.query(
#     '''SELECT
#         room,
#         DATE_BIN(INTERVAL '1 day', time) AS _time,
#         AVG(temp) AS temp,
#         AVG(hum) AS hum,
#         AVG(co) AS co
#       FROM home
#       WHERE time >= now() - INTERVAL '90 days'
#       GROUP BY room, _time
#       ORDER BY _time'''
#   )
#
#   print(table.to_pandas().to_markdown())
#
#   client.close()
#
# querySQL()

import influxdb_client, os, time
from influxdb_client import InfluxDBClient, Point, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS

import docker

token = os.environ.get("INFLUXDB_TOKEN")
org = "TheDao032"
url = "http://localhost:8086"

docker_client = docker.from_env()
client = influxdb_client.InfluxDBClient(url=url, token=token, org=org)
write_api = client.write_api(write_options=SYNCHRONOUS)

bucket="metric-collector"

# write_api = client.write_api(write_options=SYNCHRONOUS)
#
# for value in range(5):
#   point = (
#     Point("measurement1")
#     .tag("tagname1", "tagvalue1")
#     .field("field1", value)
#   )
#   write_api.write(bucket=bucket, org="TheDao032", record=point)
#   time.sleep(1) # separate points by 1 second
#
#
# query_api = client.query_api()
#
# query = """from(bucket: "metric-collector")
#  |> range(start: -10m)
#  |> filter(fn: (r) => r._measurement == "measurement1")"""
# tables = query_api.query(query, org="TheDao032")
#
# for table in tables:
#   for record in table.records:
#     print(record)

def collect_metrics():
    while True:
        containers = docker_client.containers.list()

        for container in containers:
            try:
                stats = container.stats(stream=False)

                container_name = container.name
                cpu_usage = stats['cpu_stats']['cpu_usage']['total_usage']
                memory_usage = stats['memory_stats']['usage']

                # Create InfluxDB points
                cpu_point = Point("docker_container_cpu") \
                    .tag("container_name", container_name) \
                    .field("cpu_usage", cpu_usage) \
                    # .time(time.time(), WritePrecision.S)

                memory_point = Point("docker_container_memory") \
                    .tag("container_name", container_name) \
                    .field("memory_usage", memory_usage) \
                    # .time(time.time(), WritePrecision.S)

                # Write points to InfluxDB
                write_api.write(bucket=bucket, org=org, record=cpu_point)
                write_api.write(bucket=bucket, org=org, record=memory_point)

                print(f"Metrics written for container: {container_name}")

            except Exception as e:
                print(f"Error collecting metrics for container {container.name}: {e}")

        # Sleep for 10 seconds before collecting metrics again
        time.sleep(10)

if __name__ == "__main__":
    collect_metrics()
