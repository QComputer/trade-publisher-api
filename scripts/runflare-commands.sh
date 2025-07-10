# Trade Publisher API - Runflare Deployment Guide

## Prerequisites

1. **Runflare Account**: Sign up at https://runflare.com/
2. **Node.js**: Install Node.js 14+ for Runflare CLI
3. **MySQL Client**: For database setup (optional)

## Step-by-Step Deployment

### 1. Install Runflare CLI

```bash
npm install -g @runflare/cli
```

### 2. Login to Runflare

```bash
runflare auth login
```

### 3. Clone and Setup Project

```bash
git clone <your-repo>
cd trade-publisher-api
chmod +x scripts/*.sh
```

### 4. Set Environment Variables

```bash
export API_KEY="your-secret-api-key-here"
export SECRET_KEY="$(openssl rand -hex 32)"
```

### 5. Deploy Application

```bash
# Option 1: Use deployment script
./scripts/deploy.sh

# Option 2: Manual deployment
runflare deploy --config runflare.yaml
```

### 6. Setup Database

```bash
# Setup database schema
./scripts/setup-database.sh
```

### 7. Verify Deployment

```bash
# Check application status
runflare apps status trade-publisher-api

# View logs
runflare logs trade-publisher-api --tail

# Test health endpoint
curl -H "Authorization: Bearer $API_KEY" https://your-app.runflare.com/api/health
```

## Configuration

### Environment Variables

Set these in Runflare dashboard or via CLI:

- `API_KEY`: Your secret API key for authentication
- `SECRET_KEY`: Flask secret key
- `DB_HOST`: MySQL host (auto-set by Runflare)
- `DB_USER`: MySQL username (auto-set by Runflare)
- `DB_PASSWORD`: MySQL password (auto-set by Runflare)
- `DB_NAME`: Database name (trade_publisher)
- `DB_PORT`: MySQL port (3306)

### MQL4 Configuration

Update your MQL4 EAs with:

```cpp
input string ServerURL = "https://your-app.runflare.com/api/trades";
input string ApiKey = "your-secret-api-key-here";
```

## Monitoring and Maintenance

### View Logs
```bash
runflare logs trade-publisher-api --tail
```

### Scale Application
```bash
runflare scale trade-publisher-api --instances 3
```

### Update Application
```bash
runflare deploy --force
```

### Rollback
```bash
runflare rollback trade-publisher-api
```

## Troubleshooting

### Common Issues

1. **Database Connection Failed**
   - Check if MySQL service is running
   - Verify environment variables
   - Check firewall settings

2. **Authentication Failed**
   - Verify API_KEY is set correctly
   - Check Authorization header format

3. **Deployment Failed**
   - Check runflare.yaml syntax
   - Verify all dependencies in requirements.txt
   - Check resource limits

### Debug Commands

```bash
# Check service status
runflare services list

# Check environment variables
runflare env list

# Check application details
runflare apps describe trade-publisher-api
```

## API Endpoints

- `GET /api/health` - Health check
- `POST /api/trades` - Publish trades
- `GET /api/trades/<account>` - Get trades for account
- `GET /api/
