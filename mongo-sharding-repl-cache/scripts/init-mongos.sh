#!/bin/bash
set -e

echo ">>> Ожидание инициализации config server replica set..."
until mongosh --host configSrv --port 27017 --quiet --eval "rs.status().members.some(m => m.stateStr === 'PRIMARY')" 2>/dev/null | grep -q "true"; do
  echo ">>> Ожидание config server primary..."
  sleep 2
done

echo ">>> Ожидание запуска mongos_router..."
until mongosh --host mongos_router --port 27020 --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  echo ">>> Ожидание mongos_router..."
  sleep 2
done

echo ">>> Ожидание инициализации шардов..."
until mongosh --host shard1_1 --port 27018 --quiet --eval "rs.status().members.some(m => m.stateStr === 'PRIMARY')" 2>/dev/null | grep -q "true"; do
  echo ">>> Ожидание shard1 primary..."
  sleep 2
done

until mongosh --host shard2_1 --port 27018 --quiet --eval "rs.status().members.some(m => m.stateStr === 'PRIMARY')" 2>/dev/null | grep -q "true"; do
  echo ">>> Ожидание shard2 primary..."
  sleep 2
done

echo ">>> Добавление шардов в mongos (идемпотентно)"
mongosh --host mongos_router --port 27020 <<'EOF'
try {
  sh.addShard("shard1/shard1_1:27018,shard1_2:27018,shard1_3:27018")
  print("Shard1 добавлен")
} catch(e) {
  if (e.message.includes("already been added")) {
    print("Shard1 уже добавлен")
  } else {
    throw e
  }
}

try {
  sh.addShard("shard2/shard2_1:27018,shard2_2:27018,shard2_3:27018")
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
