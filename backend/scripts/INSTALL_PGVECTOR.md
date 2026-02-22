# Установка pgvector для PostgreSQL на Windows

## Шаг 1: Скачать pgvector

1. Перейдите на https://github.com/pgvector/pgvector/releases
2. Найдите версию, соответствующую вашей версии PostgreSQL (например, для PostgreSQL 16)
3. Скачайте архив для Windows (например, `pgvector-v0.5.1-windows-x64.zip`)

## Шаг 2: Распаковать и скопировать файлы

Распакуйте архив и скопируйте файлы:

1. **vector.dll** → `C:\Program Files\PostgreSQL\16\lib\`
2. **vector.control** → `C:\Program Files\PostgreSQL\16\share\extension\`
3. **vector--*.sql** (все файлы vector--*.sql) → `C:\Program Files\PostgreSQL\16\share\extension\`

## Шаг 3: Перезапустить PostgreSQL

Перезапустите службу PostgreSQL:
- Откройте "Службы" (services.msc)
- Найдите "postgresql-x64-16" (или вашу версию)
- Нажмите "Перезапустить"

## Шаг 4: Запустить скрипт установки

```bash
cd backend
python scripts/install_pgvector.py
```

## Альтернативный способ (если есть доступ к psql)

```sql
-- Подключитесь к базе данных
psql -U postgres -d english_app -p 5440

-- Создайте расширение
CREATE EXTENSION IF NOT EXISTS vector;

-- Добавьте колонку (если её нет)
ALTER TABLE cards ADD COLUMN IF NOT EXISTS embedding vector(768);
```

## Проверка установки

После установки проверьте:

```sql
-- Проверка расширения
SELECT * FROM pg_extension WHERE extname = 'vector';

-- Проверка колонки
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'cards' AND column_name = 'embedding';
```

