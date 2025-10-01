# Обзор изменений в новой версии PostgreSQL 18
_Все примеры скриптов можно найти в_ **[файле](uuid_and_virtual.sql)**.
## 1. Генерация uuid v7 и виртуальные вичисляемые колонки.

```postgresql
create table if not exists order_item
(
    order_id    uuid primary key default uuidv7(),
    name        varchar(255)   not null UNIQUE,
    price       DECIMAL(10, 2) not null,
    quantity    int            not null,
    total_price DECIMAL(10, 2) GENERATED ALWAYS AS (quantity * price) VIRTUAL,
    created_at  timestamp        default now()
);
```
* появилась новая функция uuidv7(), которую можно использовать для генерации идентификаторов сущностей
* вычисляемые поля по умолчанию теперь виртуальные(VIRTUAL можно не указывать). Если их нужно сохранить в таблице, то необходимо указать STORED

### Пример
```postgresql
insert into order_item(name, price, quantity) values
    ('Apple', 1.99, 10),
    ('Banana', 0.99, 5),
    ('Orange', 2.99, 8);

select
    order_id,
    name,
    price,
    quantity,
    total_price,
    created_at
from order_item;
```
Результаты будут такими:

| order\_id | name | price | quantity | total\_price | created\_at |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 01999e9c-2986-7efb-9088-2b17a8402e82 | Apple | 1.99 | 10 | 19.90 | 2025-10-01 07:10:58.438497 |
| 01999e9c-2989-79be-a13f-a0eee5475d4b | Banana | 0.99 | 5 | 4.95 | 2025-10-01 07:10:58.438497 |
| 01999e9c-2989-7a41-bb16-2e02fdd68d0b | Orange | 2.99 | 8 | 23.92 | 2025-10-01 07:10:58.438497 |

## 2. Старые и новые значения в RETURNING
Для отслеживания изменений количества товара в нашем примере можно выполнить такой DML-скрипт:
```postgresql
-- Обновить количество товара и увидеть как старые, так и новые значения
UPDATE order_item
SET quantity = quantity * 2
WHERE quantity < 10
RETURNING
    name,
    old.quantity AS old_quantity,
    new.quantity AS new_quantity;
```
Используя ключевые слова **OLD** и **NEW** можно получить значение поля до и после изменений соответственно.
В результате мы получим следующее:

| name | old\_quantity | new\_quantity |
| :--- | :--- | :--- |
| Banana | 5 | 10 |
| Orange | 8 | 16 |

## B-tree skip scans
Появилась возможность использования вторую часть составных индексов для поиска. Но это работает с некоторыми ограничениями.

Например, у нас в таблице есть поля name и created_at, создадим составной индекс по ним:
```postgresql
-- Создаем индекс по полям name и created_at
CREATE INDEX name_created_idx ON order_item (name, created_at);
```
А теперь выполним запрос, в котором используется фильтр по имени и по дате:
```postgresql
SELECT * from order_item
WHERE name = 'Apple11' and created_at = '2025-10-01 16:00:00.000000';
```
В плане запроса используется индекс:

| QUERY PLAN |
| :--- |
| Index Scan using name\_created\_idx on order\_item  \(cost=0.42..8.45 rows=1 width=70\) \(actual time=0.398..0.398 rows=0.00 loops=1\) |
|   Index Cond: \(\(\(name\)::text = 'Apple11'::text\) AND \(created\_at = '2025-10-01 16:00:00'::timestamp without time zone\)\) |
|   Index Searches: 1 |
|   Buffers: shared read=3 |
| Planning: |
|   Buffers: shared hit=20 read=1 dirtied=1 |
| Planning Time: 2.646 ms |
| Execution Time: 0.450 ms |

А теперь попробуем отфильтровать записи только по дате, т.е. второй части составного индекса:
```postgresql
SELECT * from order_item
WHERE created_at = '2025-10-01 14:37:13.969459';
```
Результат ожидаемый, последовательное сканирование таблицы:

| QUERY PLAN |
| :--- |
| Seq Scan on order\_item  \(cost=0.00..3312.04 rows=100000 width=70\) \(actual time=0.041..23.757 rows=100000.00 loops=1\) |
|   Filter: \(created\_at = '2025-10-01 14:37:13.969459'::timestamp without time zone\) |
|   Rows Removed by Filter: 3 |
|   Buffers: shared hit=1312 |
| Planning Time: 0.193 ms |
| Execution Time: 27.518 ms |

А теперь добавим поле status в таблицу и создадим составной индекс, где первым полем будет именно он, а вторым дата:
```postgresql
-- Добавим поле статуса
alter table order_item
    add column status varchar(255) default 'active';

-- Создаем индекс по полю статуса
CREATE INDEX status_created_idx ON order_item (status, created_at);
```
И теперь выполним запрос, где оба поля участвуют:
```postgresql
SELECT * from order_item
WHERE status = 'inactive' and created_at = '2025-10-01 16:00:00.000000';
```
Ожидаемо использовался новый индекс:

| QUERY PLAN |
| :--- |
| Index Scan using status\_created\_idx on order\_item  \(cost=0.29..8.32 rows=1 width=70\) \(actual time=0.041..0.042 rows=0.00 loops=1\) |
|   Index Cond: \(\(\(status\)::text = 'inactive'::text\) AND \(created\_at = '2025-10-01 16:00:00'::timestamp without time zone\)\) |
|   Index Searches: 1 |
|   Buffers: shared hit=2 |
| Planning Time: 0.139 ms |
| Execution Time: 0.065 ms |

А теперь запрос только по дате:
```postgresql
SELECT * from order_item
WHERE created_at = '2025-10-01 16:00:00.000000';
```
И вуаля, снова сработал индекс:

| QUERY PLAN |
| :--- |
| Index Scan using status\_created\_idx on order\_item  \(cost=0.29..20.45 rows=3 width=70\) \(actual time=0.094..0.095 rows=0.00 loops=1\) |
|   Index Cond: \(created\_at = '2025-10-01 16:00:00'::timestamp without time zone\) |
|   Index Searches: 3 |
|   Buffers: shared hit=6 |
| Planning Time: 0.131 ms |
| Execution Time: 0.118 ms |

В первый раз мы создавали составной индекс по полям (name, created_at), где name - имеет высокую кардинальность и 
планировщик не смог пропустить это поле в индексе и использовать вторую часть индекса по полю created_at.   
А вот в случае индекса по полям (status, created_at), где status содержит всего два варианта значений и имеет низкую кардинальность,
планировщик пропустил индекс по статусу и применил вторую часть составного индекса по полю created_at.