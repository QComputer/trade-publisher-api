from flask import Flask, request, jsonify
import mysql.connector
from mysql.connector import pooling
import os
from datetime import datetime
import json
import logging
from functools import wraps
import time

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Database configuration with connection pooling
DB_CONFIG = {
    'host': os.environ.get('DB_HOST', 'localhost'),
    'user': os.environ.get('DB_USER', 'root'),
    'password': os.environ.get('DB_PASSWORD', ''),
    'database': os.environ.get('DB_NAME', 'trade_publisher'),
    'port': int(os.environ.get('DB_PORT', 3306)),
    'pool_name': 'trade_pool',
    'pool_size': 10,
    'pool_reset_session': True,
    'autocommit': True
}

# API Key for authentication
API_KEY = os.environ.get('API_KEY', 'your-secret-api-key')

# Initialize connection pool
try:
    connection_pool = pooling.MySQLConnectionPool(**DB_CONFIG)
    logger.info("Database connection pool initialized successfully")
except mysql.connector.Error as err:
    logger.error(f"Error creating connection pool: {err}")
    connection_pool = None

def get_db_connection():
    """Get database connection from pool"""
    try:
        if connection_pool:
            return connection_pool.get_connection()
        else:
            # Fallback to direct connection
            config = DB_CONFIG.copy()
            config.pop('pool_name', None)
            config.pop('pool_size', None)
            config.pop('pool_reset_session', None)
            return mysql.connector.connect(**config)
    except mysql.connector.Error as err:
        logger.error(f"Database connection error: {err}")
        return None

def authenticate_request():
    """Authenticate API request"""
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        return False
    
    token = auth_header.split(' ')[1]
    return token == API_KEY

def require_auth(f):
    """Decorator for authentication"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not authenticate_request():
            return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated_function

def handle_db_error(f):
    """Decorator for database error handling"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        try:
            return f(*args, **kwargs)
        except mysql.connector.Error as err:
            logger.error(f"Database error in {f.__name__}: {err}")
            return jsonify({'error': 'Database error', 'details': str(err)}), 500
        except Exception as e:
            logger.error(f"Unexpected error in {f.__name__}: {e}")
            return jsonify({'error': 'Internal server error'}), 500
    return decorated_function

@app.route('/', methods=['GET'])
def root():
    """Root endpoint"""
    return jsonify({
        'service': 'Trade Publisher API',
        'version': '1.0.0',
        'status': 'running',
        'endpoints': {
            'health': '/api/health',
            'publish_trades': '/api/trades (POST)',
            'get_trades': '/api/trades/<account_number> (GET)',
            'get_accounts': '/api/accounts (GET)',
            'close_trade': '/api/trades/<account_number>/close/<ticket> (POST)',
            'get_signals': '/api/signals/<account_number> (GET)'
        }
    }), 200

@app.route('/api/health', methods=['GET'])
@require_auth
@handle_db_error
def health_check():
    """Health check endpoint"""
    conn = get_db_connection()
    if conn:
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        cursor.close()
        conn.close()
        
        return jsonify({
            'status': 'healthy',
            'database': 'connected',
            'timestamp': datetime.now().isoformat(),
            'version': '1.0.0'
        }), 200
    else:
        return jsonify({
            'status': 'unhealthy',
            'database': 'disconnected',
            'timestamp': datetime.now().isoformat()
        }), 500

@app.route('/api/trades', methods=['POST'])
@require_auth
@handle_db_error
def publish_trades():
    """Publish trades from MQL4 EA"""
    data = request.get_json()
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    
    # Validate required fields
    required_fields = ['account', 'server', 'timestamp']
    for field in required_fields:
        if field not in data:
            return jsonify({'error': f'Missing required field: {field}'}), 400
    
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    cursor = conn.cursor()
    
    try:
        # Insert/update account info
        account_query = """
        INSERT INTO accounts (account_number, server, balance, equity, margin, free_margin, last_update)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
        balance = VALUES(balance),
        equity = VALUES(equity),
        margin = VALUES(margin),
        free_margin = VALUES(free_margin),
        last_update = VALUES(last_update)
        """
        
        cursor.execute(account_query, (
            data['account'],
            data['server'],
            data.get('balance', 0),
            data.get('equity', 0),
            data.get('margin', 0),
            data.get('free_margin', 0),
            datetime.fromtimestamp(data['timestamp'])
        ))
        
        # Insert/update trades
        trades_inserted = 0
        for trade in data.get('trades', []):
            if 'ticket' not in trade or 'symbol' not in trade:
                continue
                
            trade_query = """
            INSERT INTO trades (account_number, ticket, symbol, type, lots, open_price, 
                              open_time, sl, tp, profit, comment, last_update)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE
            profit = VALUES(profit),
            sl = VALUES(sl),
            tp = VALUES(tp),
            last_update = VALUES(last_update)
            """
            
            cursor.execute(trade_query, (
                data['account'],
                trade['ticket'],
                trade['symbol'],
                trade.get('type', 0),
                trade.get('lots', 0),
                trade.get('open_price', 0),
                datetime.fromtimestamp(trade.get('open_time', data['timestamp'])),
                trade.get('sl', 0),
                trade.get('tp', 0),
                trade.get('profit', 0),
                trade.get('comment', ''),
                datetime.fromtimestamp(data['timestamp'])
            ))
            trades_inserted += 1
        
        conn.commit()
        
        logger.info(f"Published {trades_inserted} trades for account {data['account']}")
        return jsonify({
            'status': 'success',
            'trades_count': trades_inserted,
            'account': data['account'],
            'timestamp': datetime.now().isoformat()
        }), 200
        
    finally:
        cursor.close()
        conn.close()

@app.route('/api/trades/<int:account_number>', methods=['GET'])
@require_auth
@handle_db_error
def get_trades(account_number):
    """Get trades for specific account"""
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    cursor = conn.cursor(dictionary=True)
    
    try:
        # Get account info
        account_query = "SELECT * FROM accounts WHERE account_number = %s"
        cursor.execute(account_query, (account_number,))
        account = cursor.fetchone()
        
        if not account:
            return jsonify({'error': 'Account not found'}), 404
        
        # Get trades with pagination
        limit = min(int(request.args.get('limit', 100)), 1000)
        offset = int(request.args.get('offset', 0))
        
        trades_query = """
        SELECT * FROM trades 
        WHERE account_number = %s 
        ORDER BY open_time DESC
        LIMIT %s OFFSET %s
        """
        cursor.execute(trades_query, (account_number, limit, offset))
        trades = cursor.fetchall()
        
        # Convert datetime objects to timestamps
        for trade in trades:
            if 'open_time' in trade and trade['open_time']:
                trade['open_time'] = int(trade['open_time'].timestamp())
            if 'last_update' in trade and trade['last_update']:
                trade['last_update'] = int(trade['last_update'].timestamp())
        
        if 'last_update' in account and account['last_update']:
            account['last_update'] = int(account['last_update'].timestamp())
        
        response = {
            'account': account,
            'trades': trades,
            'trades_count': len(trades),
            'pagination': {
                'limit': limit,
                'offset': offset,
                'has_more': len(trades) == limit
            }
        }
        
        return jsonify(response), 200
        
    finally:
        cursor.close()
        conn.close()

@app.route('/api/accounts', methods=['GET'])
@require_auth
@handle_db_error
def get_accounts():
    """Get all accounts"""
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    cursor = conn.cursor(dictionary=True)
    
    try:
        query = """
        SELECT a.*, COUNT(t.ticket) as trades_count
        FROM accounts a
        LEFT JOIN trades t ON a.account_number = t.account_number
        GROUP BY a.account_number
        ORDER BY a.last_update DESC
        """
        
        cursor.execute(query)
        accounts = cursor.fetchall()
        
        # Convert datetime objects to timestamps
        for account in accounts:
            if 'last_update' in account and account['last_update']:
                account['last_update'] = int(account['last_update'].timestamp())
            if 'created_at' in account and account['created_at']:
                account['created_at'] = int(account['created_at'].timestamp())
        
        return jsonify({'accounts': accounts, 'count': len(accounts)}), 200
        
    finally:
        cursor.close()
        conn.close()

@app.route('/api/trades/<int:account_number>/close/<int:ticket>', methods=['POST'])
@require_auth
@handle_db_error
def close_trade_signal(account_number, ticket):
    """Signal to close a specific trade"""
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    cursor = conn.cursor()
    
    try:
        # Check if trade exists
        check_query = "SELECT ticket FROM trades WHERE account_number = %s AND ticket = %s"
        cursor.execute(check_query, (account_number, ticket))
        if not cursor.fetchone():
            return jsonify({'error': 'Trade not found'}), 404
        
        # Insert close signal
        signal_query = """
        INSERT INTO trade_signals (account_number, ticket, signal_type, created_at)
        VALUES (%s, %s, 'CLOSE', %s)
        """
        
        cursor.execute(signal_query, (account_number, ticket, datetime.now()))
        conn.commit()
        
        logger.info(f"Close signal sent for account {account_number}, ticket {ticket}")
        return jsonify({
            'status': 'success',
            'message': 'Close signal sent',
            'account': account_number,
            'ticket': ticket
        }), 200
        
    finally:
        cursor.close()
        conn.close()

@app.route('/api/signals/<int:account_number>', methods=['GET'])
@require_auth
@handle_db_error
def get_signals(account_number):
    """Get pending signals for account"""
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    cursor = conn.cursor(dictionary=True)
    
    try:
        query = """
        SELECT * FROM trade_signals 
        WHERE account_number = %s AND processed = FALSE
        ORDER BY created_at ASC
        """
        
        cursor.execute(query, (account_number,))
        signals = cursor.fetchall()
        
        # Convert datetime objects to timestamps
        for signal in signals:
            if 'created_at' in signal and signal['created_at']:
                signal['created_at'] = int(signal['created_at'].timestamp())
        
        return jsonify({'signals': signals, 'count': len(signals)}), 200
        
    finally:
        cursor.close()
        conn.close()

@app.route('/api/signals/<int:signal_id>/processed', methods=['POST'])
@require_auth
@handle_db_error
def mark_signal_processed(signal_id):
    """Mark signal as processed"""
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database connection failed'}), 500
    
    cursor = conn.cursor()
    
    try:
        query = """
        UPDATE trade_signals 
        SET processed = TRUE, processed_at = %s
        WHERE id = %s
        """
        
        cursor.execute(query, (datetime.now(), signal_id))
        
        if cursor.rowcount == 0:
            return jsonify({'error': 'Signal not found'}), 404
        
        conn.commit()
        
        return jsonify({'status': 'success', 'signal_id': signal_id}), 200
        
    finally:
        cursor.close()
        conn.close()

@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Endpoint not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('FLASK_ENV') == 'development'
    app.run(debug=debug, host='0.0.0.0', port=port)