#!/bin/bash

echo "🔍 WSO2 API Manager Setup Status"
echo "=================================="
echo ""

# Check container status
STATUS=$(docker ps --filter "name=wso2am" --format "{{.Status}}" 2>/dev/null)
if [ -z "$STATUS" ]; then
  echo "❌ WSO2 AM container not running"
  exit 1
fi

echo "📦 Container Status: $STATUS"
echo ""

# Check logs for setup progress
echo "📋 Setup Progress:"
echo "------------------"

# API Setup
if docker logs innover-wso2am-1 2>&1 | grep -q "Creating 6 APIs"; then
  echo "✅ API creation started"
  
  if docker logs innover-wso2am-1 2>&1 | grep -q "Setup Complete"; then
    echo "✅ API setup completed successfully"
    
    # Show consumer key
    CONSUMER_KEY=$(docker logs innover-wso2am-1 2>&1 | grep "Consumer Key:" | tail -1 | cut -d: -f2 | xargs)
    if [ -n "$CONSUMER_KEY" ]; then
      echo "   🔑 Consumer Key: $CONSUMER_KEY"
    fi
  elif docker logs innover-wso2am-1 2>&1 | grep -q "API setup failed"; then
    echo "⚠️  API setup failed - check logs"
  else
    echo "⏳ API setup in progress..."
  fi
else
  echo "⏳ Waiting for API setup to start..."
fi

# Key Manager Integration
echo ""
if docker logs innover-wso2am-1 2>&1 | grep -q "Configuring WSO2 IS as Key Manager"; then
  echo "✅ Key Manager configuration started"
  
  if docker logs innover-wso2am-1 2>&1 | grep -q "WSO2 IS configured as Key Manager"; then
    echo "✅ WSO2 IS integrated as Key Manager successfully"
  elif docker logs innover-wso2am-1 2>&1 | grep -q "Key Manager configuration failed"; then
    echo "⚠️  Key Manager configuration failed - will retry on restart"
  else
    echo "⏳ Key Manager configuration in progress..."
  fi
else
  echo "⏳ Waiting for Key Manager configuration..."
fi

echo ""
echo "------------------"

# Check if fully ready
if docker logs innover-wso2am-1 2>&1 | grep -q "Setup complete, WSO2 API-M running"; then
  echo "✅ WSO2 API Manager is fully ready!"
  echo ""
  echo "🌐 Access URLs:"
  echo "   Publisher: https://localhost:9443/publisher"
  echo "   DevPortal: https://localhost:9443/devportal"
  echo "   Gateway:   https://localhost:8243"
  echo ""
  
  # Check application keys file
  if [ -f "/home/premnath/innover/wso2/output/application-keys.json" ]; then
    echo "📄 Application keys saved to: wso2/output/application-keys.json"
    echo ""
    cat /home/premnath/innover/wso2/output/application-keys.json | jq .
  fi
else
  echo "⏳ Setup still in progress... (wait ~2-3 minutes after container start)"
fi
