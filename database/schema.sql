-- Create database
CREATE DATABASE IF NOT EXISTS trade_publisher;
USE trade_publisher;

-- Accounts table
CREATE TABLE accounts (
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
CREATE TABLE trades (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    account_number BIGINT NOT NULL,
    ticket BIGINT NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    type TINYINT NOT NULL, -- 0=BUY, 1=SELL, etc.
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
    FOREIGN KEY (account_number) REFERENCES accounts(account_number) ON DELETE CASCADE,
    INDEX idx_account_symbol (account_number, symbol),
    INDEX idx_open_time (open_time)
);

-- Trade signals table (for close signals, etc.)
CREATE TABLE trade_signals (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    account_number BIGINT NOT NULL,
    ticket BIGINT,
    signal_type ENUM('CLOSE', 'MODIFY', 'OPEN') NOT NULL,
    signal_data JSON,
    processed BOOLEAN DEFAULT FALSE,
    processed_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (account_number) REFERENCES accounts(account_number) ON DELETE CASCADE,
    INDEX idx_account_processed (account_number, processed),
    INDEX idx_created_at (created_at)
);

-- Create indexes for better performance
CREATE INDEX idx_trades_account_time ON trades(account_number, open_time DESC);
CREATE INDEX idx_accounts_update ON accounts(last_update DESC);