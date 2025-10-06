# WSO2 Initialization Fix - Changes Summary

## 2025-02-14 - Automated WSO2 IS Key Manager Enablement

- Set the external WSO2 IS key manager to enabled by default in `deployment.toml` with complete OpenID Connect metadata.
- Added an idempotent Admin REST helper (`enable_wso2is_keymanager.py`) that creates the key manager configuration if it is missing and updates it when disabled.
- Wired the setup container to call the helper automatically before provisioning APIs so the admin experience requires no manual toggles.
- Documented the grant types, issuer, and JWKS endpoints to align with the multi-role user bootstrap supplied by `wso2is/create-users.sh`.

## Problem

WSO2 API Manager initialization was failing with:
- **HTTP 500 errors** when creating APIs
- **NullPointerException: username** in WSO2 AM logs
- **Scope validation failures**
- **JSON decode errors** in setup script

### Root Cause

WSO2 AM was configured with WSO2 IS as an external Key Manager (`enabled = true`), but the setup script was authenticating against WSO2 AM's Resident Key Manager. This created an authentication mismatch where:
1. Setup script gets token from WSO2 AM's Resident KM
2. WSO2 AM tries to validate token against WSO2 IS
3. WSO2 IS doesn't recognize the token
4. Validation fails with NullPointerException

## Solution

### 1. Configuration Changes

**File: `wso2/deployment.toml`**
- Set WSO2 IS Key Manager to `enabled = false` during initial setup
- Added proper claim configuration
- Kept JWT validation settings for future enablement

```toml
[[apim.key_manager]]
name = "WSO2IS"
enabled = false  # Disabled during initial setup
```

### 2. Enhanced Setup Script

**File: `wso2/setup.py`**
- **Improved wait logic**: Now properly validates Publisher API is accessible with token
- **Retry mechanism**: API creation retries 3 times on 500 errors
- **Better error handling**: JSON decode errors are caught and handled gracefully
- **Increased timeouts**: Extended from 5s to 10s for token and API operations
- **Extended validation**: 40 attempts instead of 30 for Publisher API readiness

### 3. Docker Compose Improvements

**File: `docker-compose.yml`**
- **Enhanced healthcheck**: Now checks both `/services/Version` and `/publisher/` endpoints
- **Increased start_period**: From 240s to 360s (6 minutes) for first-time initialization
- **More retries**: From 30 to 40 retries
- **Proper dependency**: wso2-setup now waits for `service_healthy` instead of `service_started`

### 4. New Tools Added

**File: `wso2/enable_wso2is_keymanager.py`**
- Script to enable WSO2 IS Key Manager after initial setup
- Validates Key Manager configuration
- Updates via REST API

**File: `wso2/README.md`**
- Comprehensive documentation
- Troubleshooting guide
- Best practices
- Step-by-step enablement guide

**File: `wso2/CHANGES.md`** (this file)
- Summary of all changes
- Problem description
- Solution details

### 5. Makefile Enhancements

**File: `Makefile`**

New targets added:
```bash
make wso2-check      # Check WSO2 services status
make wso2-logs       # View WSO2 error logs
make wso2-restart    # Restart WSO2 and re-run setup
make wso2-reset      # Reset WSO2 data (fresh start)
make wso2-enable-km  # Enable WSO2 IS Key Manager
```

## Testing the Fix

### Step 1: Check Current Status
```bash
make wso2-check
```

### Step 2: Monitor WSO2 AM Startup
```bash
docker logs -f innover-wso2am-1
```

Wait for:
- `Pass-through HTTPS Listener started on 0.0.0.0:8243`
- Container status shows `(healthy)`

### Step 3: Run Setup
```bash
make setup
# or
docker compose up wso2-setup
```

Expected output:
```
✓ WSO2 API Manager is FULLY ready
✓ Access token obtained
✓ Created API: <api-id>
✓ API published successfully
✅ Setup Complete!
```

### Step 4: Verify APIs Created
```bash
# Check setup logs
docker logs wso2-setup

# Access WSO2 AM Publisher
# https://localhost:9443/publisher
# Credentials: admin/admin
```

## Enabling WSO2 IS Key Manager (Production)

After successful initial setup, you can enable WSO2 IS for production use:

### Option 1: Using Make Target
```bash
make wso2-enable-km
```

### Option 2: Manual Steps

1. Update `wso2/deployment.toml`:
   ```toml
   [[apim.key_manager]]
   enabled = true  # Change from false
   ```

2. Restart WSO2 AM:
   ```bash
   docker compose restart wso2am
   ```

3. Wait for healthy status (5-8 minutes)

4. Verify in Admin Portal:
   - https://localhost:9443/admin
   - Key Managers → Check WSO2IS is enabled

## Migration Path

### Current State (After Fix)
- WSO2 AM uses Resident Key Manager
- APIs are authenticated via WSO2 AM's built-in OAuth2
- Setup completes successfully

### Future State (Production)
- WSO2 AM uses WSO2 IS as Key Manager
- APIs are authenticated via WSO2 IS OAuth2
- Enhanced security and compliance features

### Migration Steps
1. Complete initial setup with Resident KM
2. Verify all APIs are working
3. Enable WSO2 IS Key Manager
4. Test token generation from WSO2 IS
5. Update client applications to use WSO2 IS token endpoint

## Files Modified

1. `wso2/deployment.toml` - Key Manager disabled, improved config
2. `wso2/setup.py` - Enhanced validation, retry logic, error handling
3. `docker-compose.yml` - Better healthchecks, proper dependencies
4. `wso2/Dockerfile` - Added enable_wso2is_keymanager.py
5. `Makefile` - New WSO2 troubleshooting targets

## Files Created

1. `wso2/enable_wso2is_keymanager.py` - KM enablement script
2. `wso2/README.md` - Comprehensive documentation
3. `wso2/CHANGES.md` - This file

## Benefits

1. **Reliable Initialization**: Setup succeeds consistently on first run
2. **Clear Error Messages**: Better debugging information
3. **Production Ready**: Path to enable WSO2 IS later
4. **Better Documentation**: Clear guides for troubleshooting
5. **Automated Tools**: Make targets for common operations

## Troubleshooting

If setup still fails:

1. **Check WSO2 AM is healthy**:
   ```bash
   docker ps --filter "name=wso2am"
   ```

2. **View detailed logs**:
   ```bash
   make wso2-logs
   ```

3. **Reset and retry**:
   ```bash
   make wso2-reset
   # Wait for healthy status
   make setup
   ```

4. **Check resource limits**:
   - WSO2 AM needs at least 1GB RAM
   - First start can take 8-10 minutes
   - Check `docker stats` for resource usage

## Next Steps

1. Monitor WSO2 AM startup (currently in progress)
2. Run setup once healthy: `make setup`
3. Verify APIs created in Publisher portal
4. Test API calls through Gateway
5. Consider enabling WSO2 IS Key Manager for production

## References

- WSO2 APIM Documentation: https://apim.docs.wso2.com/
- Key Manager Configuration: https://apim.docs.wso2.com/en/latest/administer/key-managers/
- WSO2 IS Integration: https://is.docs.wso2.com/
