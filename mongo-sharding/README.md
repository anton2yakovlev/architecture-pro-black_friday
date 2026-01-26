# pymongo-api

## Запуск

```shell
docker compose up -d --build
```

Инициализация replica sets, настройка шардинга и заполнение БД тестовыми данными выполняется автоматически через init-контейнеры.

## Проверка

Локально: http://localhost:8080

![Общая информация о кластере](../tasks/task_2/get_root.png)
![Количество записей после запуска](../tasks/task_2/get_count.png)