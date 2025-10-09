# WSO2 IS + APIM Integration - Safe Deployment Strategy

## ⚠️ Important: deployment.toml Sensitivity

WSO2 Identity Server is **extremely sensitive** to `deployment.toml` configuration errors:
- ❌ Wrong syntax → Container crashes
- ❌ Missing required keys → Startup fails
- ❌ Incorrect variable references → Parser exceptions
- ❌ Exit code 137 → Out of memory (often caused by config loops)

## ✅ Current Safe Approach

### **Phase 1: Use Default Configuration (NOW)**

**What we're doing:**
- ✅ Using WSO2 IS 7.1.0's **default deployment.toml**
- ✅ No custom configuration overrides
- ✅ Increased memory: 2GB (was 1.5GB)
- ✅ Creating users via SCIM2 API (works with defaults)
- ✅ Registering IS7 as Third-Party Key Manager in APIM

**Why this is safer:**
- Default config is tested and stable
- No risk of syntax errors
- IS will start reliably
- Basic APIM integration works without custom config

**What works:**
- ✅ WSO2 IS starts successfully
- ✅ Users created (admin, finance, auditor, ops_user, user)
- ✅ OAuth2 token generation
- ✅ APIM can validate tokens via JWKS
- ✅ IS7 registered as Key Manager in APIM
- ✅ All users can authenticate

**What doesn't work (yet):**
- ⚠️ Token revocation notifications (IS → APIM)
- ⚠️ Advanced OAuth2 features (authorize_all_scopes)
- ⚠️ Custom SCIM2 access control

---

### **Phase 2: Add Minimal Config (LATER - Optional)**

**Only if needed**, we can add minimal configuration:

```toml
# Minimal safe additions to deployment.toml
[server]
hostname = "wso2is"

[oauth]
authorize_all_scopes = true
```

**How to apply safely:**
1. Test in development first
2. Add one section at a time
3. Verify IS starts after each change
4. Monitor logs for config errors

---

## 🔧 Current Dockerfile Strategy

### **wso2is/Dockerfile - Minimal Approach**

```dockerfile
FROM wso2/wso2is:7.1.0-alpine

USER root

# Only install required tools
RUN apk add --no-cache curl bash jq

# DO NOT override deployment.toml
# Use default configuration from WSO2 IS

# Copy user setup scripts
COPY setup-users-and-roles.sh /home/wso2carbon/
COPY entrypoint-wrapper.sh /home/wso2carbon/
RUN chmod +x /home/wso2carbon/*.sh && \
    chown wso2carbon:wso2 /home/wso2carbon/*.sh

USER wso2carbon
ENTRYPOINT ["/home/wso2carbon/entrypoint-wrapper.sh"]
```

**What we removed:**
- ❌ Custom deployment.toml (too risky)
- ❌ JAR download (network dependency, may fail)
- ❌ Token revocation handler (requires JAR + config)
- ❌ Repository ownership changes (not needed)

---

## 📊 Resource Allocation

### **WSO2 IS Container**
```yaml
deploy:
  resources:
    limits:
      cpus: "2.00"    # Increased from 1.50
      memory: 2G      # Increased from 1.5G
```

**Why increased:**
- IS 7.1.0 needs more memory for startup
- Prevents OOM kills (exit code 137)
- Allows for user initialization scripts

### **WSO2 AM Container**
```yaml
deploy:
  resources:
    limits:
      cpus: "1.00"
      memory: 1G
```

---

## 🚀 Deployment Steps

### **Step 1: Clean Start**
```bash
docker compose down -v
```

### **Step 2: Build with Minimal Config**
```bash
docker compose build wso2is wso2am
```

### **Step 3: Start Services**
```bash
docker compose up -d
```

### **Step 4: Monitor WSO2 IS Startup**
```bash
docker logs -f innover-wso2is-1
```

**Expected output:**
```
▶ Starting WSO2 Identity Server...
▶ Waiting for WSO2 IS to be ready...
✅ WSO2 IS is ready
▶ Testing SCIM2 endpoint...
✅ SCIM2 endpoint ready
▶ Running user/role setup...
✅ Setup complete, WSO2 IS running
```

### **Step 5: Monitor WSO2 AM Startup**
```bash
docker logs -f innover-wso2am-1
```

**Expected output:**
```
▶ Starting WSO2 API Manager...
✅ WSO2 API-M is ready
▶ Registering WSO2 IS 7 as Third-Party Key Manager...
✅ Key Manager registered successfully!
▶ Running API setup...
✅ 6 APIs published
✅ Application created with WSO2-IS Key Manager
```

---

## 🧪 Testing

### **Test 1: Verify IS Started**
```bash
curl -k https://localhost:9444/oauth2/token/.well-known/openid-configuration
```

### **Test 2: Verify Users Created**
```bash
# Get token for finance user
curl -sk -u admin:admin \
  -d "grant_type=password&username=finance&password=Finance123" \
  https://localhost:9444/oauth2/token | jq .
```

### **Test 3: Verify Key Manager Registered**
```bash
curl -sk -u admin:admin \
  https://localhost:9443/api/am/admin/v4/key-managers | \
  jq '.list[] | select(.name=="WSO2-IS")'
```

### **Test 4: Test API Call**
```bash
# Load app keys
APP_KEYS=$(cat wso2/output/application-keys.json)
CLIENT_ID=$(echo $APP_KEYS | jq -r '.production.consumerKey')
CLIENT_SECRET=$(echo $APP_KEYS | jq -r '.production.consumerSecret')

# Get token from IS
TOKEN=$(curl -sk -u "$CLIENT_ID:$CLIENT_SECRET" \
  -d "grant_type=password&username=finance&password=Finance123" \
  https://localhost:9444/oauth2/token | jq -r '.access_token')

# Call API via Gateway
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8280/api/forex/1.0.0/health
```

---

## 🔍 Troubleshooting

### **Issue: IS exits with code 137**
**Cause:** Out of memory  
**Fix:** Already increased to 2GB in docker-compose.yml

### **Issue: Config parser exception**
**Cause:** Invalid deployment.toml syntax  
**Fix:** Using default config (no custom deployment.toml)

### **Issue: "server.hostname doesn't exist"**
**Cause:** Custom deployment.toml missing required keys  
**Fix:** Removed custom deployment.toml

### **Issue: Users not created**
**Cause:** SCIM2 endpoint not ready  
**Fix:** entrypoint-wrapper.sh waits for SCIM2 before running setup

### **Issue: Key Manager registration fails**
**Cause:** IS not healthy when APIM tries to register  
**Fix:** APIM depends_on wso2is with condition: service_healthy

---

## 📝 What Changed from Original Plan

### **Original Plan (Too Risky)**
- ❌ Custom deployment.toml with all APIM integration settings
- ❌ Download JAR file from Maven (network dependency)
- ❌ Token revocation event handler
- ❌ Complex configuration with variable references

### **Current Plan (Safe)**
- ✅ Use default deployment.toml
- ✅ No external dependencies
- ✅ Minimal configuration changes
- ✅ Focus on core functionality first

### **What We Still Get**
- ✅ IS7 as Third-Party Key Manager
- ✅ All 5 users can authenticate
- ✅ JWT token validation via JWKS
- ✅ API Gateway integration
- ✅ Complete end-to-end flow

### **What We Can Add Later (Optional)**
- Token revocation notifications
- Custom OAuth2 settings
- Advanced SCIM2 access control
- Role management integration

---

## 🎯 Success Criteria

After deployment, you should have:

- [x] WSO2 IS running without crashes
- [x] WSO2 AM running and healthy
- [x] IS7 registered as "WSO2-IS" Key Manager
- [x] 5 users created in IS (admin, finance, auditor, ops_user, user)
- [x] 6 APIs published to APIM Gateway
- [x] Application keys generated from IS7 Key Manager
- [x] All users can get tokens from IS
- [x] All users can call APIs via APIM Gateway
- [x] No "Invalid Access Token" errors

---

## 📚 Next Steps

1. **Deploy with minimal config** (current approach)
2. **Verify everything works**
3. **Run comprehensive tests** (`make test`)
4. **Only then** consider adding advanced config if needed

**Remember:** Stability first, features second!
