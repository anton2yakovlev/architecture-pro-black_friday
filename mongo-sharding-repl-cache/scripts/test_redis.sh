#!/bin/bash

set -e

API_URL="http://localhost:8080/helloDoc/users"
REDIS_CONTAINER="redis"

docker exec "$REDIS_CONTAINER" redis-cli FLUSHDB > /dev/null

echo "Первый запрос:"
START_TIME=$(date +%s.%N)
curl -s "$API_URL" > /dev/null
END_TIME=$(date +%s.%N)
FIRST_DURATION=$(echo "$END_TIME - $START_TIME" | bc)
echo "Время: ${FIRST_DURATION}s"

sleep 0.5

echo "Redis DBSIZE:"
docker exec "$REDIS_CONTAINER" redis-cli DBSIZE

echo "Redis KEYS:"
docker exec "$REDIS_CONTAINER" redis-cli KEYS "*"

echo ""
echo "Второй запрос:"
START_TIME=$(date +%s.%N)
curl -s "$API_URL" > /dev/null
END_TIME=$(date +%s.%N)
SECOND_DURATION=$(echo "$END_TIME - $START_TIME" | bc)
echo "Время: ${SECOND_DURATION}s"

sleep 0.5

echo "Redis DBSIZE:"
docker exec "$REDIS_CONTAINER" redis-cli DBSIZE

echo "Redis KEYS:"
docker exec "$REDIS_CONTAINER" redis-cli KEYS "*"
