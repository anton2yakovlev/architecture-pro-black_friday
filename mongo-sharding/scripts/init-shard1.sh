#!/bin/bash
set -e

echo ">>> Ожидание запуска shard1..."
until mongosh --host shard1 --port 27018 --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  echo ">>> Ожидание shard1..."
  sleep 2
done

echo ">>> Инициализация shard1 replica set (идемпотентно)"
mongosh --host shard1 --port 27018 <<'EOF'
try {
  rs.initiate({
    _id: "shard1",
    members: [{ _id: 0, host: "shard1:27018" }]
  })
} catch(e) {
  if (e.message.includes("already initialized") || e.message.includes("already a member")) {
    print("Shard1 replica set уже инициализирован")
  } else {
    throw e
  }
}
EOF

echo ">>> Shard1 replica set инициализирован"
