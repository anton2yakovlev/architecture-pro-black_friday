#!/bin/bash
set -e

echo ">>> Ожидание готовности mongos_router..."
until mongosh --host mongos_router --port 27020 --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  echo ">>> Ожидание mongos_router..."
  sleep 2
done

echo ">>> Вставка тестовых данных в базу"
mongosh --host mongos_router --port 27020 <<'EOF'
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
print(">>> Вставлено 1000 документов в коллекцию helloDoc")
EOF

echo ">>> Тестовые данные успешно вставлены"
