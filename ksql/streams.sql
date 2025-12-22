CREATE STREAM ORDERS_STREAM (
  order_id INT,
  customer_id INT,
  amount DOUBLE,
  currency VARCHAR,
  country VARCHAR,
  status VARCHAR,
  created_at VARCHAR,
  source VARCHAR
) WITH (
  KAFKA_TOPIC = 'orders',
  VALUE_FORMAT = 'JSON'
);

CREATE TABLE SALES_PER_COUNTRY AS
  SELECT country,
         COUNT(*) AS order_count,
         SUM(amount) AS total_amount
  FROM ORDERS_STREAM
  WINDOW TUMBLING (SIZE 1 MINUTE)
  GROUP BY country
  EMIT CHANGES;

