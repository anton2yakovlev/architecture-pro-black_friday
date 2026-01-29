#!/bin/bash
set -e

echo ">>> Ожидание запуска shard2..."
until mongosh --host shard2 --port 27019 --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  echo ">>> Ожидание shard2..."
  sleep 2
done

echo ">>> Инициализация shard2 replica set (идемпотентно)"
mongosh --host shard2 --port 27019 <<'EOF'
try {
  rs.initiate({
    _id: "shard2",
    members: [{ _id: 0, host: "shard2:27019" }]
  })
} catch(e) {
  if (e.message.includes("already initialized") || e.message.includes("already a member")) {
    print("Shard2 replica set уже инициализирован")
  } else {
    throw e
  }
}
EOF

echo ">>> Shard2 replica set инициализирован"
