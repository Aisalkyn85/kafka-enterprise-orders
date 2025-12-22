CREATE TABLE IF NOT EXISTS legacy_orders (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL,
    customer_id INT NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    currency VARCHAR(10) NOT NULL,
    country VARCHAR(10) NOT NULL,
    created_at TIMESTAMP NOT NULL
);

INSERT INTO legacy_orders (order_id, customer_id, amount, currency, country, created_at) VALUES
(1001, 2001, 123.45, 'USD', 'US', NOW() - INTERVAL '1 day'),
(1002, 2002, 555.00, 'USD', 'FR', NOW() - INTERVAL '2 days'),
(1003, 2003, 75.99, 'USD', 'DE', NOW() - INTERVAL '3 days');

