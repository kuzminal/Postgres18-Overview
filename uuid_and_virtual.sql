-- Создаем таблицу для экспериментов
create table if not exists order_item
(
    order_id    uuid primary key default uuidv7(),
    name        varchar(255)   not null UNIQUE,
    price       DECIMAL(10, 2) not null,
    quantity    int            not null,
    total_price DECIMAL(10, 2) GENERATED ALWAYS AS (quantity * price) VIRTUAL,
    created_at  timestamp        default now()
);
-- Наполняем таблицу тестовыми данными
insert into order_item(name, price, quantity)
values ('Apple', 1.99, 10),
       ('Banana', 0.99, 5),
       ('Orange', 2.99, 8);

-- Если нужно почистить таблицу после экспериментов
truncate table order_item restart identity cascade;

-- Проверяем результат сгенерированного поля total_price и генерацию поля order_id
select order_id,
       name,
       price,
       quantity,
       total_price,
       created_at
from order_item;

-- Посмотрим на отслеживаемые изменения

-- Обновить количество товара и увидеть как старые, так и новые значения
UPDATE order_item
SET quantity = quantity * 2
WHERE quantity < 10
RETURNING
    name,
    old.quantity AS old_quantity,
    new.quantity AS new_quantity;


-- Upsert с отслеживанием изменений
INSERT INTO order_item (name, price, quantity)
VALUES ('Orange', 3.50, 2)
ON CONFLICT (name) DO UPDATE SET price = EXCLUDED.price -- EXCLUDED в данном случае будет содержать все поля, которые мы вставляем
RETURNING
    name,
    old.price AS previous_price,
    new.price AS current_price,
    (old.price IS NULL) AS is_new_record;

-- Отслеживать, что было удалено
DELETE
FROM products
WHERE price < 10.00
RETURNING
    old.name AS deleted_product,
    old.price AS deleted_price;

-- Мультиколоночные индексы

-- Наполним таблицу тестовыми данными
    insert into order_item(name, price, quantity)
SELECT  array_to_string(array_sample ( ARRAY['Apple', 'Banana', 'Orange'], 1 ), '') || id as name,
        round(random(1,1000) / 100::numeric, 2) as price,
        random(1, 10) as quantity
FROM generate_series(1,100000) id;

-- Создаем индекс по полям name и created_at
CREATE INDEX name_created_idx ON order_item (name, created_at);

-- Проверяем, что индекс применился
Explain analyse SELECT * from order_item
                WHERE name = 'Apple11' and created_at = '2025-10-01 16:00:00.000000';

-- А вот тут не работает, используется сканирование всех строк
Explain analyse SELECT * from order_item
                WHERE created_at = '2025-10-01 14:37:13.969459';

-- Добавим поле статуса
alter table order_item
    add column status varchar(255) default 'active';


-- Обновим записи в таблице и установим статус
update order_item
    set status = 'inactive'
    where name like 'Apple%';

-- Создаем индекс по полю статуса
CREATE INDEX name_status_idx ON order_item (name, status);

-- Создаем индекс по полю статуса
CREATE INDEX status_created_idx ON order_item (status, created_at);

Explain analyse SELECT * from order_item
                WHERE status = 'inactive' and created_at > '2025-10-01 16:00:00.000000';

Explain analyse SELECT * from order_item
                WHERE created_at > '2025-10-01 16:00:00.000000';