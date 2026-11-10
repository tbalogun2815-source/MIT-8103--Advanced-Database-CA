-- Portfolio 4: export the real customer ids from PostgreSQL as a JavaScript
-- array, so the MongoDB seed uses customers that exist in quickfund_db.
-- Run with: psql -t -A -f ... -o portfolio-4-nosql/customer_ids.js
-- (the funding account owner and the two Portfolio 3 demo wallets are excluded)
SELECT 'var CUSTOMER_IDS = ' || array_to_json(array_agg(customer_id::text ORDER BY customer_id)) || ';'
FROM customers
WHERE customer_id NOT IN (
  SELECT customer_id FROM accounts
  WHERE account_number IN ('0000000000', '9000000001', '9000000002'));