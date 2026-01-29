# Выявление и устранение горячих шардов MongoDB

## Метрики мониторинга

### Нагрузка на шарды

Метрики операций и производительности:
```javascript
// Счетчики операций по типам
db.serverStatus().opcounters

// Задержки операций (95, 99 перцентили)
db.serverStatus().opLatencies

// Медленные запросы
db.setProfilingLevel(1, 50)
db.system.profile.find().sort({ts: -1}).limit(10)
```

Метрики использования ресурсов:
```javascript
// Загрузка CPU
db.serverStatus().metrics.cpu

// Использование памяти и кэша WiredTiger
db.serverStatus().mem
db.serverStatus().wiredTiger.cache["percentage of cache used"]

// Очередь конкурентных операций
db.serverStatus().globalLock.currentQueue
```

### Распределение данных

Метрики чанков и балансировки:
```javascript
// Статус шардирования и распределение чанков
sh.status()
sh.printShardingStatus()

// Распределение данных по шардам
db.products.getShardDistribution()

// Статистика коллекций по шардам
db.products.stats()
```

Метрики миграции:
```javascript
// Статус балансировщика
sh.getBalancerState()

// История миграций
db.getSiblingDB("config").changelog.find({what: "moveChunk.commit"}).sort({time: -1})
```

### Распределение ключей шардирования

Анализ распределения запросов:
```javascript
// Анализ распределения документов по ключу шардирования
db.products.aggregate([
  { $group: { _id: "$category", count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])

// Определение горячих ключей
db.products.aggregate([
  { $group: { _id: "$category", ops: { $sum: 1 } } },
  { $match: { ops: { $gt: 10000 } } }
])
```

### Репликация

Метрики лага репликации:
```javascript
// Информация о репликации
rs.printSlaveReplicationInfo()
rs.printReplicationInfo()

// Статус репликации
rs.status()
```

## Пороги алертов

- Дисбаланс чанков между шардами: более 30% от среднего значения
- Использование кэша WiredTiger: более 80%
- Задержка операций (p99): более 500ms
- Лаг репликации: более 5 секунд
- Дисбаланс операций между шардами: более 40% от среднего

## Механизмы автоматического перераспределения

### Встроенный балансировщик MongoDB

Настройка автоматической балансировки:
```javascript
// Включение балансировщика
sh.setBalancerState(true)

// Настройка окна балансировки (ночное время для снижения нагрузки)
sh.setBalancerWindow("01:00", "05:00")

// Проверка состояния
sh.getBalancerState()
```

Автоматическое разделение чанков:
```javascript
// Включение авто-разделения
sh.enableAutoSplit()

// Ручное разделение большого чанка
sh.splitAt("mobile_world.products", { "category": "Электроника", "_id": ObjectId("...") })
```

### Ручное перераспределение чанков

Перемещение чанков между шардами:
```javascript
// Перемещение чанка на другой шард
sh.moveChunk(
  "mobile_world.products",
  { "category": "Электроника" },
  "shard2"
)

// Принудительное разделение горячего чанка
sh.splitFind("mobile_world.products")
```

### Стратегия перешардирования

Использование составного ключа для равномерного распределения:
```javascript
// Перешардирование с составным ключом
sh.shardCollection("mobile_world.products", {
  "category": 1,
  "_id": "hashed"
})
```

Альтернатива - hash-based шардирование по составному ключу:
```javascript
// Hash-based шардирование для равномерного распределения
sh.shardCollection("mobile_world.products", {
  "category": "hashed",
  "product_id": "hashed"
})
```

### Range Tagging для управления распределением

Привязка диапазонов ключей к конкретным шардам:
```javascript
// Создание тега для шарда
sh.addTagRange(
  "mobile_world.products",
  { "category": "Электроника", "_id": MinKey },
  { "category": "Электроника", "_id": MaxKey },
  "high_performance_shard"
)

// Добавление шарда с тегом
sh.addShardTag("shard3", "high_performance_shard")
```

### Автоматический скрипт балансировки

Пример скрипта для автоматической проверки и балансировки:
```javascript
// auto_balancer.js
function checkAndRebalance() {
  const status = sh.status(true);
  const shardStats = {};
  
  // Сбор статистики по шардам
  status.databases.forEach(db => {
    db.collections.forEach(coll => {
      coll.shards.forEach(shard => {
        if (!shardStats[shard.shard]) {
          shardStats[shard.shard] = { chunks: 0, size: 0 };
        }
        shardStats[shard.shard].chunks += shard.chunks;
        shardStats[shard.shard].size += shard.size;
      });
    });
  });
  
  // Вычисление среднего значения
  const shardNames = Object.keys(shardStats);
  const avgChunks = shardNames.reduce((sum, name) => 
    sum + shardStats[name].chunks, 0) / shardNames.length;
  
  // Проверка дисбаланса
  shardNames.forEach(shardName => {
    const imbalance = Math.abs(shardStats[shardName].chunks - avgChunks) / avgChunks;
    if (imbalance > 0.3) {
      print(`Дисбаланс обнаружен на ${shardName}: ${(imbalance * 100).toFixed(2)}%`);
      sh.startBalancer();
    }
  });
}

// Запуск проверки
checkAndRebalance();
```

### Добавление новых шардов

Масштабирование при росте нагрузки:
```javascript
// Добавление нового шарда
sh.addShard("shard3/mongodb-shard3-1:27017,mongodb-shard3-2:27017")

// После добавления балансировщик автоматически перераспределит данные
sh.setBalancerState(true)
```

## Интеграция с системами мониторинга

Экспорт метрик в Prometheus через MongoDB Exporter:
```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'mongodb'
    static_configs:
      - targets: ['mongodb-exporter:9216']
```

Метрики для отслеживания в Grafana:
- mongodb_shard_chunks_total
- mongodb_shard_chunk_size_bytes
- mongodb_op_latencies_seconds
- mongodb_wiredtiger_cache_used_percent
- mongodb_replication_lag_seconds

## Профилактика горячих шардов

1. Использование hash-based шардирования вместо range-based для равномерного распределения
2. Мониторинг распределения запросов по ключам шардирования
3. Регулярный анализ популярности категорий и товаров
4. Настройка автоматических алертов при превышении порогов
5. Плановое добавление шардов при росте нагрузки
6. Использование составных ключей шардирования для более равномерного распределения
