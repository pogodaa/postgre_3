-- ============================================================================
-- ЧАСТЬ 1. Создание базы данных и таблиц (Требование 1.1)
-- ============================================================================

-- Создаем новую базу данных
CREATE DATABASE finance_db;

-- Подключаемся к ней (если вы уже внутри psql)
\c finance_db

-- Создаем 4 связанные таблицы
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    description TEXT
);

CREATE TABLE transactions (
    transaction_id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(user_id),
    category_id INTEGER REFERENCES categories(category_id),
    amount DECIMAL(10, 2) NOT NULL,
    transaction_type VARCHAR(10) CHECK (transaction_type IN ('income', 'expense')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица для аудита (журнал изменений)
CREATE TABLE audit_log (
    log_id SERIAL PRIMARY KEY,
    table_name VARCHAR(50),
    operation VARCHAR(10),
    old_data JSONB,
    new_data JSONB,
    changed_by VARCHAR(50),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- ЧАСТЬ 2. Заполнение данными (Тестовые данные)
-- ============================================================================

INSERT INTO users (username, email) VALUES 
('ivanov', 'ivanov@test.ru'),
('petrov', 'petrov@test.ru'),
('sidorov', 'sidorov@test.ru');

INSERT INTO categories (name, description) VALUES 
('Зарплата', 'Доходы от работы'),
('Продукты', 'Расходы на еду'),
('Транспорт', 'Расходы на проезд');

INSERT INTO transactions (user_id, category_id, amount, transaction_type) VALUES 
(1, 1, 50000.00, 'income'),
(1, 2, 5000.00, 'expense'),
(2, 1, 60000.00, 'income');

-- ============================================================================
-- ЧАСТЬ 3. Пользователи и Роли (Требование 1.2)
-- ============================================================================

-- Создаем роли
CREATE ROLE accountant;      -- Бухгалтер: читает всё, добавляет операции
CREATE ROLE auditor;         -- Аудитор: читает всё, включая логи
CREATE ROLE manager;         -- Менеджер: полный доступ

-- Создаем конкретных пользователей с паролями
CREATE USER user_accountant WITH PASSWORD 'account123';
CREATE USER user_auditor WITH PASSWORD 'audit123';
CREATE USER user_manager WITH PASSWORD 'manager123';

-- Назначаем роли пользователям
GRANT accountant TO user_accountant;
GRANT auditor TO user_auditor;
GRANT manager TO user_manager;

-- ============================================================================
-- ЧАСТЬ 4. Разграничение прав доступа (Требование 1.2.4)
-- ============================================================================

-- Скрываем схемы по умолчанию
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Права роли accountant (только операции и пользователи, без удаления)
GRANT USAGE ON SCHEMA public TO accountant;
GRANT SELECT, INSERT, UPDATE ON transactions TO accountant;
GRANT SELECT ON users, categories TO accountant;
GRANT USAGE, SELECT ON SEQUENCE transactions_transaction_id_seq TO accountant;
-- Запрещаем доступ к логам
REVOKE ALL ON audit_log FROM accountant;

-- Права роли auditor (чтение всего, включая логи)
GRANT USAGE ON SCHEMA public TO auditor;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO auditor;

-- Права роли manager (полный доступ)
GRANT ALL ON ALL TABLES IN SCHEMA public TO manager;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO manager;

-- ============================================================================
-- ЧАСТЬ 5. Триггеры для аудита (Требование 1.4)
-- ============================================================================

-- Функция для логирования изменений
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, new_data, changed_by)
        VALUES (TG_TABLE_NAME, 'INSERT', to_jsonb(NEW), current_user);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, old_data, new_data, changed_by)
        VALUES (TG_TABLE_NAME, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW), current_user);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, old_data, changed_by)
        VALUES (TG_TABLE_NAME, 'DELETE', to_jsonb(OLD), current_user);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Создаем триггер на таблицу транзакций
CREATE TRIGGER transactions_audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON transactions
FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- ============================================================================
-- ЧАСТЬ 6. Проверка целостности (Требование 1.3.2)
-- ============================================================================

-- Добавляем ограничение на сумму (не может быть отрицательной)
ALTER TABLE transactions ADD CONSTRAINT check_amount_positive 
CHECK (amount >= 0);

-- ============================================================================
-- ЧАСТЬ 7. Резервное копирование (Требование 1.3.1)
-- ============================================================================
-- Внимание: Эта команда выполняется в командной строке ОС (не внутри psql)!
-- Пример команды для Windows (путь может отличаться):
-- "C:\Program Files\PostgreSQL\15\bin\pg_dump.exe" -U postgres finance_db > backup.sql
-- ============================================================================