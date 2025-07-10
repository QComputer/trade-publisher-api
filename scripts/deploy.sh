#!/bin/bash

# Trade Publisher API Deployment Script for Runflare CLI

set -e

echo "🚀 Starting deployment to Runflare..."

# Check if runflare CLI is installed
if ! command -v runflare &> /dev/null; then
    echo "❌ Runflare CLI not found. Please install it first:"
    echo "npm install -g @runflare/cli"
    exit 1
fi

# Check if logged in
if ! runflare auth status &> /dev/null; then
    echo "❌ Not logged in to Runflare. Please login first:"
    echo "runflare auth login"
    exit 1
fi

# Validate environment variables
echo "🔍 Validating environment variables..."
if [ -z "$API_KEY" ]; then
    echo "❌ API_KEY environment variable is required"
    exit 1
fi

# Create .env file for deployment
echo "📝 Creating environment configuration..."
cat > .env.production << EOF
DB_HOST=\${DB_HOST}
DB_USER=\${DB_USER}
DB_PASSWORD=\${DB_PASSWORD}
DB_NAME=trade_publisher
DB_PORT=3306
API_KEY=${API_KEY}
SECRET_KEY=${SECRET_KEY:-$(openssl rand -hex 32)}
FLASK_ENV=production
EOF

# Deploy the application
echo "🚀 Deploying application..."
runflare deploy --config runflare.yaml --env-file .env.production

# Wait for deployment to complete
echo "⏳ Waiting for deployment to complete..."
sleep 30

# Get the deployment URL
APP_URL=$(runflare apps list --format json | jq -r '.[] | select(.name=="trade-publisher-api") | .url')

if [ "$APP_URL" != "null" ] && [ -n "$APP_URL" ]; then
    echo "✅ Deployment successful!"
    echo "🌐 Application URL: $APP_URL"
    echo "🔗 Health check: $APP_URL/api/health"
    
    # Test the health endpoint
    echo "🏥 Testing health endpoint..."
    if curl -s -H "Authorization: Bearer $API_KEY" "$APP_URL/api/health" | grep -q "healthy"; then
        echo "✅ Health check passed!"
    else
        echo "⚠️  Health check failed. Please check the logs."
    fi
else
    echo "❌ Could not retrieve application URL. Please check the deployment status."
fi

# Clean up
rm -f .env.production

echo "🎉 Deployment process completed!"
