#!/bin/bash

# Database Setup Script for Runflare MySQL

set -e

echo "🗄️  Setting up database..."

# Get database connection details from Runflare
DB_INFO=$(runflare services list --format json | jq -r '.[] | select(.type=="mysql") | select(.name=="trade-db")')

if [ "$DB_INFO" = "null" ] || [ -z "$DB_INFO" ]; then
    echo "❌ MySQL service 'trade-db' not found. Creating it..."
    runflare services create mysql trade-db --version 8.0
    echo "⏳ Waiting for MySQL service to be ready..."
    sleep 60
    DB_INFO=$(runflare services list --format json | jq -r '.[] | select(.type=="mysql") | select(.name=="trade-db")')
fi

# Extract connection details
DB_HOST=$(echo $DB_INFO | jq -r '.host')
DB_PORT=$(echo $DB_INFO | jq -r '.port')
DB_USER=$(echo $DB_INFO | jq -r '.username')
DB_PASSWORD=$(echo $DB_INFO | jq -r '.password')

echo "📊 Database connection details:"
echo "Host: $DB_HOST"
echo "Port: $DB_PORT"
echo "User: $DB_USER"

# Create database schema
echo "🏗️  Creating database schema..."
mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" << 'EOF'
-- Create database
CREATE DATABASE IF NOT EXISTS trade_publisher;
USE trade_publisher;

-- Accounts table
CREATE TABLE IF NOT EXISTS accounts (
    account_number BIGINT PRIMARY KEY,
    server VARCHAR(100) NOT NULL,
    balance DECIMAL(15,2) DEFAULT 0,
    equity DECIMAL(15,2) DEFAULT 0,
    margin DECIMAL(15,2) DEFAULT 0,
    free_margin DECIMAL(15,2) DEFAULT 0,
    last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trades table
CREATE TABLE IF NOT EXISTS trades (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    account_number BIGINT NOT NULL,
    ticket BIGINT NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    type TINYINT NOT NULL,
    lots DECIMAL(10,2) NOT NULL,
    open_price DECIMAL(10,5) NOT NULL,
    open_time TIMESTAMP NOT NULL,
    sl DECIMAL(10,5) DEFAULT 0,
    tp DECIMAL(10,5) DEFAULT 0,
    profit DECIMAL(15,2) DEFAULT 0,
    comment VARCHAR(255) DEFAULT '',
    last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_trade (account_number, ticket),
    INDEX idx_account_symbol (account_number, symbol),
    INDEX idx_open_time (open_time),
    INDEX idx_trades_account_time (account_number, open_time DESC)
);

-- Trade signals table
CREATE TABLE IF NOT EXISTS trade_signals (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    account_number BIGINT NOT NULL,
    ticket BIGINT,
    signal_type ENUM('CLOSE', 'MODIFY', 'OPEN') NOT NULL,
    signal_data JSON,
    processed BOOLEAN DEFAULT FALSE,
    processed_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_account_processed (account_number, processed),
    INDEX idx_created_at (created_at)
);

-- Add foreign key constraints (if they don't exist)
SET @constraint_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS 
    WHERE CONSTRAINT_SCHEMA = 'trade_publisher' 
    AND TABLE_NAME = 'trades' 
    AND CONSTRAINT_NAME = 'fk_trades_account');

SET @sql = IF(@constraint_exists = 0, 
    'ALTER TABLE trades ADD CONSTRAINT fk_trades_account FOREIGN KEY (account_number) REFERENCES accounts(account_number) ON DELETE CASCADE',
    'SELECT "Foreign key constraint already exists"');

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @constraint_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS 
    WHERE CONSTRAINT_SCHEMA = 'trade_publisher' 
    AND TABLE_NAME = 'trade_signals' 
    AND CONSTRAINT_NAME = 'fk_signals_account');

SET @sql = IF(@constraint_exists = 0, 
    'ALTER TABLE trade_signals ADD CONSTRAINT fk_signals_account FOREIGN KEY (account_number) REFERENCES accounts(account_number) ON DELETE CASCADE',
    'SELECT "Foreign key constraint already exists"');

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_accounts_update ON accounts(last_update DESC);

SELECT 'Database schema created successfully!' as status;
EOF

echo "✅ Database setup completed!"

# Set environment variables for the application
echo "🔧 Setting environment variables..."
runflare env set DB_HOST="$DB_HOST"
runflare env set DB_PORT="$DB_PORT"
runflare env set DB_USER="$DB_USER"
runflare env set DB_PASSWORD="$DB_PASSWORD"
runflare env set DB_NAME="trade_publisher"

echo "✅ Environment variables set!"
