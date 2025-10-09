#!/bin/bash
# Monitor WSO2 IS and AM startup

echo "════════════════════════════════════════════════════════════════"
echo "Monitoring WSO2 Startup"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "📊 Container Status:"
docker compose ps wso2is wso2am
echo ""

echo "🔍 WSO2 IS Logs (last 30 lines):"
echo "────────────────────────────────────────────────────────────────"
docker logs innover-wso2is-1 --tail 30 2>&1 | grep -E "Starting|ready|Error|Exception|SEVERE|✅|❌|▶" || echo "No logs yet"
echo ""

echo "🔍 WSO2 AM Logs (last 20 lines):"
echo "────────────────────────────────────────────────────────────────"
docker logs innover-wso2am-1 --tail 20 2>&1 | grep -E "Starting|ready|Error|Exception|SEVERE|✅|❌|▶" || echo "No logs yet"
echo ""

echo "💡 To follow logs in real-time:"
echo "   docker logs -f innover-wso2is-1"
echo "   docker logs -f innover-wso2am-1"
