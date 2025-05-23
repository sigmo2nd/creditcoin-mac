#!/usr/bin/env python3
from docker_stats_client import DockerStatsClient
import json

client = DockerStatsClient()
print('캐시된 데이터:', json.dumps(dict(client.container_stats), indent=2))