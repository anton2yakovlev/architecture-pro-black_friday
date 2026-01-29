#!/bin/bash
set -e

echo ">>> Ожидание запуска shard1 реплик..."
until mongosh --host shard1_1 --port 27018 --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  echo ">>> Ожидание shard1_1..."
  sleep 2
done

until mongosh --host shard1_2 --port 27018 --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  echo ">>> Ожидание shard1_2..."
  sleep 2
done

until mongosh --host shard1_3 --port 27018 --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  echo ">>> Ожидание shard1_3..."
  sleep 2
done

echo ">>> Инициализация shard1 replica set с тремя репликами"
mongosh --host shard1_1 --port 27018 <<'EOF'
try {
  rs.initiate({
    _id: "shard1",
    members: [
      { _id: 0, host: "shard1_1:27018" },
      { _id: 1, host: "shard1_2:27018" },
      { _id: 2, host: "shard1_3:27018" }
    ]
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
