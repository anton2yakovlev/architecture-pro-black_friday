# Миграция на Cassandra: модель данных, стратегии репликации и шардирования

## Задание 10.1: Критически важные данные и обоснование применения Cassandra

### Критически важные данные

**Orders (заказы)**
- Критичность: высокая
- Требования: высокая скорость записи, отказоустойчивость, горизонтальное масштабирование
- Обоснование для Cassandra: Заказы создаются с высокой частотой во время пиковых нагрузок. Требуется быстрая запись без блокировок. Leaderless-архитектура обеспечивает отказоустойчивость. Горизонтальное масштабирование без полного перераспределения данных критично при добавлении узлов.

**Carts (корзины)**
- Критичность: высокая
- Требования: высокая скорость записи и чтения, временное хранение, отказоустойчивость
- Обоснование для Cassandra: Корзины обновляются часто, требуют быстрого доступа. TTL в Cassandra обеспечивает автоматическое удаление устаревших корзин. Высокая доступность критична для пользовательского опыта.

**Products (товары)**
- Критичность: средняя
- Требования: высокая скорость чтения, геораспределенность
- Обоснование для Cassandra: Каталог товаров читается с высокой частотой. Cassandra обеспечивает эффективное чтение с распределенных узлов. Геораспределенность позволяет размещать данные ближе к пользователям.

**История заказов**
- Критичность: средняя
- Требования: высокая скорость чтения, долгосрочное хранение
- Обоснование для Cassandra: Исторические данные читаются реже, но требуют быстрого доступа. Cassandra эффективна для временных рядов и исторических данных.

### Данные, не подходящие для Cassandra

**Остатки товаров (stock.quantity)**
- Обоснование: Требуется строгая консистентность для предотвращения overselling. ACID-транзакции критичны. Cassandra обеспечивает eventual consistency, что не подходит для операций с финансовыми последствиями.

## Задание 10.2: Концептуальная модель данных

### Orders

```cql
CREATE TABLE mobile_world.orders (
    user_id UUID,
    order_id UUID,
    created_at TIMESTAMP,
    status TEXT,
    total_price DECIMAL,
    geo TEXT,
    items LIST<FROZEN<MAP<TEXT, TEXT>>>,
    PRIMARY KEY ((user_id), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

**Partition key:** `user_id`
**Clustering keys:** `created_at DESC`, `order_id`

Обоснование: Все заказы пользователя находятся в одной партиции, что обеспечивает эффективный доступ к истории заказов. Сортировка по `created_at DESC` позволяет получать последние заказы без дополнительной сортировки. `order_id` обеспечивает уникальность. Распределение по `user_id` равномерно благодаря UUID.

Минимизация горячих партиций: UUID обеспечивает равномерное распределение. При добавлении узлов Cassandra перераспределяет только новые данные, существующие партиции остаются на прежних узлах.

### Carts

```cql
CREATE TABLE mobile_world.carts (
    user_id UUID,
    session_id UUID,
    updated_at TIMESTAMP,
    status TEXT,
    items LIST<FROZEN<MAP<TEXT, TEXT>>>,
    expires_at TIMESTAMP,
    PRIMARY KEY ((user_id, session_id), updated_at)
) WITH CLUSTERING ORDER BY (updated_at DESC)
  AND default_time_to_live = 86400;
```

**Partition key:** `(user_id, session_id)`
**Clustering key:** `updated_at DESC`

Обоснование: Составной partition key обеспечивает равномерное распределение корзин между узлами. Для авторизованных пользователей используется `user_id`, для гостевых - `session_id`. Сортировка по `updated_at` позволяет получать актуальные корзины. TTL автоматически удаляет устаревшие корзины.

Минимизация горячих партиций: Составной ключ из двух UUID обеспечивает равномерное распределение даже при всплесках активности определенных пользователей.

### Products

```cql
CREATE TABLE mobile_world.products (
    category TEXT,
    product_id UUID,
    name TEXT,
    price DECIMAL,
    stock MAP<TEXT, INT>,
    attributes MAP<TEXT, TEXT>,
    PRIMARY KEY ((category), product_id)
);
```

**Partition key:** `category`
**Clustering key:** `product_id`

Обоснование: Основная операция - поиск товаров по категории. Все товары категории находятся в одной партиции, что обеспечивает эффективный доступ. `product_id` обеспечивает уникальность и равномерное распределение внутри категории.

Риск горячих партиций: Популярные категории могут создавать горячие партиции. Для снижения риска можно использовать составной partition key `(category, bucket)` где `bucket` - хэш от `product_id` по модулю числа бакетов.

Альтернативная модель для равномерного распределения:

```cql
CREATE TABLE mobile_world.products (
    category TEXT,
    bucket INT,
    product_id UUID,
    name TEXT,
    price DECIMAL,
    stock MAP<TEXT, INT>,
    attributes MAP<TEXT, TEXT>,
    PRIMARY KEY ((category, bucket), product_id)
);
```

**Partition key:** `(category, bucket)`
**Clustering key:** `product_id`

Обоснование: Составной partition key с бакетированием равномерно распределяет товары категории между несколькими партициями, снижая риск горячих партиций.

### Order History

```cql
CREATE TABLE mobile_world.order_history (
    user_id UUID,
    year_month TEXT,
    order_id UUID,
    created_at TIMESTAMP,
    status TEXT,
    total_price DECIMAL,
    items LIST<FROZEN<MAP<TEXT, TEXT>>>,
    PRIMARY KEY ((user_id, year_month), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

**Partition key:** `(user_id, year_month)`
**Clustering keys:** `created_at DESC`, `order_id`

Обоснование: Разделение по месяцам предотвращает рост партиций до недопустимого размера. Запросы истории заказов обычно ограничены временным диапазоном. Сортировка по `created_at DESC` оптимизирует доступ к последним заказам.

## Задание 10.3: Стратегии обеспечения целостности данных

### Hinted Handoff

**Применение:** Orders, Carts

**Обоснование:** При временной недоступности узла Cassandra сохраняет hints для последующей репликации. Для заказов и корзин критична доступность записи даже при сбоях узлов. Hinted Handoff обеспечивает быструю запись с последующей синхронизацией без блокировки операций.

**Компромиссы:** При длительном сбое узла hints накапливаются и могут вызвать нагрузку при восстановлении. Для критичных данных требуется мониторинг состояния hints.

**Настройка:**
```cql
ALTER KEYSPACE mobile_world WITH REPLICATION = {
    'class': 'NetworkTopologyStrategy',
    'datacenter1': 3
};

// В cassandra.yaml
hinted_handoff_enabled: true
max_hint_window_in_ms: 3600000
```

### Read Repair

**Применение:** Products, Order History

**Обоснование:** Для каталога товаров и истории заказов допустима eventual consistency. Read Repair автоматически исправляет расхождения при чтении без дополнительной нагрузки на систему. Подходит для данных с высокой частотой чтения и низкой частотой обновлений.

**Компромиссы:** Read Repair увеличивает latency чтения при обнаружении расхождений. Для данных с высокой частотой чтения это приемлемый компромисс.

**Настройка:**
```cql
// Использование QUORUM для чтения активирует Read Repair
CONSISTENCY QUORUM;
SELECT * FROM mobile_world.products WHERE category = 'Электроника';
```

### Anti-Entropy Repair

**Применение:** Orders, Carts, Products

**Обоснование:** Anti-Entropy Repair обеспечивает полную синхронизацию данных между репликами. Критичен для заказов и корзин для предотвращения потери данных. Для товаров обеспечивает консистентность каталога.

**Компромиссы:** Repair создает нагрузку на кластер и должен выполняться в периоды низкой нагрузки. Для критичных данных рекомендуется регулярный repair.

**Настройка:**
```bash
# Ручной запуск repair
nodetool repair -pr mobile_world

# Автоматический repair через cron (ночное время)
0 2 * * * nodetool repair -pr mobile_world
```

### Комбинированная стратегия

**Orders:**
- Hinted Handoff: включен для обеспечения доступности записи
- Read Repair: включен для автоматического исправления при чтении
- Anti-Entropy Repair: ежедневный repair в ночное время

**Carts:**
- Hinted Handoff: включен для обеспечения доступности записи
- Read Repair: включен для автоматического исправления при чтении
- Anti-Entropy Repair: ежедневный repair в ночное время

**Products:**
- Read Repair: включен как основной механизм
- Anti-Entropy Repair: еженедельный repair для полной синхронизации

**Order History:**
- Read Repair: включен как основной механизм
- Anti-Entropy Repair: ежемесячный repair для исторических данных

### Уровни консистентности

**Запись:**
- Orders: QUORUM для обеспечения записи на большинство реплик
- Carts: QUORUM для баланса между доступностью и консистентностью
- Products: ONE для высокой скорости записи каталога

**Чтение:**
- Orders: QUORUM для актуальных данных
- Carts: QUORUM для актуального состояния корзины
- Products: ONE для высокой скорости чтения каталога
- Order History: ONE для быстрого доступа к истории
