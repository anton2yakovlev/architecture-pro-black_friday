#!/bin/bash
set -e

echo ">>> Ожидание инициализации config server replica set..."
until mongosh --host configSrv --port 27017 --eval "rs.status().members[0].stateStr" 2>/dev/null | grep -q "PRIMARY"; do
  echo ">>> Ожидание config server primary..."
  sleep 2
done

echo ">>> Ожидание запуска mongos_router..."
until mongosh --host mongos_router --port 27020 --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  echo ">>> Ожидание mongos_router..."
  sleep 2
done

echo ">>> Ожидание инициализации шардов..."
until mongosh --host shard1 --port 27018 --eval "rs.status().members[0].stateStr" 2>/dev/null | grep -q "PRIMARY"; do
  echo ">>> Ожидание shard1 primary..."
  sleep 2
done

until mongosh --host shard2 --port 27019 --eval "rs.status().members[0].stateStr" 2>/dev/null | grep -q "PRIMARY"; do
  echo ">>> Ожидание shard2 primary..."
  sleep 2
done

echo ">>> Добавление шардов в mongos (идемпотентно)"
mongosh --host mongos_router --port 27020 <<'EOF'
try {
  sh.addShard("shard1/shard1:27018")
  print("Shard1 добавлен")
} catch(e) {
  if (e.message.includes("already been added")) {
    print("Shard1 уже добавлен")
  } else {
    throw e
  }
}

try {
  sh.addShard("shard2/shard2:27019")
  print("Shard2 добавлен")
} catch(e) {
  if (e.message.includes("already been added")) {
    print("Shard2 уже добавлен")
  } else {
    throw e
  }
}
EOF

echo ">>> Включение шардинга для базы данных (идемпотентно)"
mongosh --host mongos_router --port 27020 <<'EOF'
use somedb
try {
  sh.enableSharding("somedb")
  print("Шардинг включен для somedb")
} catch(e) {
  if (e.message.includes("already enabled")) {
    print("Шардинг уже включен для somedb")
  } else {
    throw e
  }
}
EOF

echo ">>> Mongos инициализирован"
