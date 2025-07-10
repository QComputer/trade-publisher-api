# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed. Please install Node.js 14+ first."
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    print_error "npm is not installed. Please install npm first."
    exit 1
fi

print_success "Node.js and npm are installed"

# Install Runflare CLI if not present
if ! command -v runflare &> /dev/null; then
    print_status "Installing Runflare CLI..."
    npm install -g @runflare/cli
    if [ $? -eq 0 ]; then
        print_success "Runflare CLI installed successfully"
    else
        print_error "Failed to install Runflare CLI"
        exit 1
    fi
else
    print_success "Runflare CLI is already installed"
fi

# Check if logged in to Runflare
print_status "Checking Runflare authentication..."
if ! runflare auth status &> /dev/null; then
    print_warning "Not logged in to Runflare. Please login:"
    runflare auth login
    
    # Verify login was successful
    if ! runflare auth status &> /dev/null; then
        print_error "Login failed. Please try again."
        exit 1
    fi
fi
print_success "Authenticated with Runflare"

# Generate API key if not provided
if [ -z "$API_KEY" ]; then
    print_status "Generating API key..."
    API_KEY=$(openssl rand -hex 32)
    export API_KEY
    print_success "API key generated: ${API_KEY:0:8}..."
fi

# Generate secret key if not provided
if [ -z "$SECRET_KEY" ]; then
    print_status "Generating Flask secret key..."
    SECRET_KEY=$(openssl rand -hex 32)
    export SECRET_KEY
    print_success "Secret key generated"
fi

# Create MySQL service
print_status "Creating MySQL service..."
if runflare services list | grep -q "database"; then
    print_success "MySQL service 'database' already exists"
else
    runflare services create mysql database --version 8.0
    if [ $? -eq 0 ]; then
        print_success "MySQL service created successfully"
        print_status "Waiting for MySQL service to be ready..."
        sleep 60
    else
        print_error "Failed to create MySQL service"
        exit 1
    fi
fi

# Set environment variables
print_status "Setting environment variables..."
runflare env set API_KEY="$API_KEY"
runflare env set SECRET_KEY="$SECRET_KEY"
runflare env set DB_NAME="databasewlw_db"

# Get database connection details
print_status "Retrieving database connection details..."
DB_INFO=$(runflare services describe database --format json 2>/dev/null || echo "{}")

if [ "$DB_INFO" != "{}" ]; then
    DB_HOST=$(echo $DB_INFO | jq -r '.host // empty')
    DB_PORT=$(echo $DB_INFO | jq -r '.port // "3306"')
    DB_USER=$(echo $DB_INFO | jq -r '.username // empty')
    DB_PASSWORD=$(echo $DB_INFO | jq -r '.password // empty')
    
    if [ -n "$DB_HOST" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ]; then
        runflare env set DB_HOST="$DB_HOST"
        runflare env set DB_PORT="$DB_PORT"
        runflare env set DB_USER="$DB_USER"
        runflare env set DB_PASSWORD="$DB_PASSWORD"
        print_success "Database environment variables set"
    else
        print_warning "Could not retrieve all database connection details"
    fi
else
    print_warning "Could not retrieve database information"
fi

# Deploy the application
print_status "Deploying application..."
runflare deploy --config runflare.yaml

if [ $? -eq 0 ]; then
    print_success "Application deployed successfully"
else
    print_error "Deployment failed"
    exit 1
fi

# Wait for deployment to be ready
print_status "Waiting for deployment to be ready..."
sleep 30

# Get application URL
print_status "Retrieving application URL..."
APP_INFO=$(runflare apps describe trade-publisher-api --format json 2>/dev/null || echo "{}")

if [ "$APP_INFO" != "{}" ]; then
    APP_URL=$(echo $APP_INFO | jq -r '.url // empty')
    
    if [ -n "$APP_URL" ]; then
        print_success "Application deployed at: $APP_URL"
        
        # Test health endpoint
        print_status "Testing health endpoint..."
        HEALTH_RESPONSE=$(curl -s -H "Authorization: Bearer $API_KEY" "$APP_URL/api/health" || echo "")
        
        if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
            print_success "Health check passed!"
        else
            print_warning "Health check failed. Response: $HEALTH_RESPONSE"
        fi
        
        # Setup database schema
        print_status "Setting up database schema..."
        if [ -n "$DB_HOST" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ]; then
            mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" << 'EOF'
CREATE DATABASE IF NOT EXISTS databasewlw_db;
USE databasewlw_db;

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
    INDEX idx_open_time (open_time)
);

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

SELECT 'Database schema created successfully!' as status;
EOF
            
            if [ $? -eq 0 ]; then
                print_success "Database schema created successfully"
            else
                print_warning "Database schema creation failed or partially completed"
            fi
        else
            print_warning "Skipping database setup - connection details not available"
        fi
        
    else
        print_error "Could not retrieve application URL"
    fi
else
    print_error "Could not retrieve application information"
fi

# Display summary
echo ""
echo "🎉 Deployment Summary"
echo "===================="
echo "Application: trade-publisher-api"
echo "URL: ${APP_URL:-'http://copytrade.runflare.run'}"
echo "API Key: ${API_KEY:0:8}..."
echo "Database: database (MySQL 8.0)"
echo ""
echo "📋 Next Steps:"
echo "1. Update your MQL4 EA with the following settings:"
echo "   - ServerURL: ${APP_URL:-'https://copytrade.runflare.run'}/api/trades"
echo "   - ApiKey: $API_KEY"
echo ""
echo "2. Test the API endpoints:"
echo "   - Health: curl -H \"Authorization: Bearer $API_KEY\" \"${APP_URL:-'https://copytrade.runflare.run'}/api/health\""
echo "   - Accounts: curl -H \"Authorization: Bearer $API_KEY\" \"${APP_URL:-'https://copytrade.runflare.run'}/api/accounts\""
echo ""
echo "3. Monitor your application:"
echo "   - Logs: runflare logs trade-publisher-api --tail"
echo "   - Status: runflare apps status trade-publisher-api"
echo ""
echo "4. Scale if needed:"
echo "   - runflare scale trade-publisher-api --instances 2"
echo ""

# Save configuration to file
cat > deployment-config.txt << EOF
# Trade Publisher API Deployment Configuration
# Generated on: $(date)

Application URL: ${APP_URL:-'Not available'}
API Key: $API_KEY
Secret Key: $SECRET_KEY

Database Details:
- Host: ${DB_HOST:-'database-eva-service'}
- Port: ${DB_PORT:-'3306'}
- User: ${DB_USER:-'root'}
- Database: databasewlw_db

MQL4 Configuration:
- ServerURL: ${APP_URL:-'https://copytrade.runflare.run'}/api/trades
- ApiKey: $API_KEY

Useful Commands:
- View logs: runflare logs trade-publisher-api --tail
- Check status: runflare apps status trade-publisher-api
- Scale app: runflare scale trade-publisher-api --instances 2
- Update app: runflare deploy --force
- Rollback: runflare rollback trade-publisher-api
EOF

print_success "Configuration saved to deployment-config.txt"
print_success "Deployment completed successfully! 🚀"
