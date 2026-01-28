#!/bin/bash
set -e

echo ">>> Ожидание запуска configSrv..."
until mongosh --host configSrv --port 27017 --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  echo ">>> Ожидание configSrv..."
  sleep 2
done

echo ">>> Инициализация config server replica set"
mongosh --host configSrv --port 27017 <<'EOF'
try {
  rs.initiate({
    _id: "config_server",
    configsvr: true,
    members: [{ _id: 0, host: "configSrv:27017" }]
  })
} catch(e) {
  if (e.message.includes("already initialized") || e.message.includes("already a member")) {
    print("Config server replica set уже инициализирован")
  } else {
    throw e
  }
}
EOF

echo ">>> Config server replica set инициализирован"
