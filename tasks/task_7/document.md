# Проектирование схем коллекций для шардирования данных

## Orders

```json
{
  "_id": ObjectId,
  "user_id": ObjectId,
  "created_at": Date,
  "items": [
    {
      "product_id": ObjectId,
      "price": Number
    }
  ],
  "status": String,
  "total_price": Number,
  "geo": String
}
```

### Шардирование

Shard key: `{user_id: "hashed"}`

Стратегия: Hash-based sharding

Обоснование: Равномерное распределение заказов по шардам. Все заказы одного пользователя попадают на один шард, что оптимизирует запросы истории заказов по user_id.

## Products

```json
{
  "_id": ObjectId,
  "name": String,
  "category": String,
  "price": Number,
  "stock": {
    "geo_zone": String,
    "quantity": Number
  },
  "attributes": {
    "color": String,
    "size": String
  }
}
```

### Шардирование

Shard key: `{category: "hashed"}`

Стратегия: Hash-based sharding

Обоснование: Основная операция поиска это фильтрация по категориям. Hash-based шардирование обеспечивает равномерное распределение товаров по шардам независимо от популярности категорий.

## Carts

```json
{
  "_id": ObjectId,
  "user_id": ObjectId,
  "session_id": String,
  "items": [
    {
      "product_id": ObjectId,
      "quantity": Number
    }
  ],
  "status": String,
  "created_at": Date,
  "updated_at": Date,
  "expires_at": Date
}
```

### Шардирование

Shard key: `{user_id: "hashed"}`

Стратегия: Hash-based sharding

Обоснование: Для авторизованных пользователей данные хранятся на одном шарде. Для гостевых корзин используется session_id как альтернативный идентификатор в запросах. Hash-based распределение равномерно распределяет нагрузку при всплесках активности.

## Команды настройки MongoDB

```javascript
// Включение шардирования для базы данных
sh.enableSharding("mobile_world");

// Шардирование коллекции orders по user_id
sh.shardCollection("mobile_world.orders", { "user_id": "hashed" });

// Шардирование коллекции products по category
sh.shardCollection("mobile_world.products", { "category": "hashed" });

// Шардирование коллекции carts по user_id
sh.shardCollection("mobile_world.carts", { "user_id": "hashed" });
```
