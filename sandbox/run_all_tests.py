#!/usr/bin/env python3
"""
Run All Tests
Comprehensive test suite for the entire platform
"""

import subprocess
import sys
import time

def run_test(script_name, description):
    """Run a test script and return success status"""
    print("\n" + "=" * 70)
    print(f"Running: {description}")
    print("=" * 70)
    print()
    
    try:
        result = subprocess.run(
            ['python3', script_name],
            cwd='/home/premnath/innover/sandbox',
            capture_output=False,
            text=True
        )
        return result.returncode == 0
    except Exception as e:
        print(f"❌ Error running {script_name}: {e}")
        return False


def main():
    print("=" * 70)
    print("INNOVER PLATFORM - COMPREHENSIVE TEST SUITE")
    print("=" * 70)
    print()
    print("This will test:")
    print("  1. Keycloak token generation")
    print("  2. Direct service access (localhost:8001-8006)")
    print("  3. WSO2 API Gateway access")
    print()
    input("Press Enter to start tests...")
    
    tests = [
        ('test_keycloak_token.py', 'Keycloak Token Generation'),
        ('test_services_direct.py', 'Direct Service Access'),
        ('test_wso2_gateway.py', 'WSO2 API Gateway'),
    ]
    
    results = []
    
    for script, description in tests:
        success = run_test(script, description)
        results.append((description, success))
        time.sleep(1)  # Brief pause between tests
    
    # Final Summary
    print("\n" + "=" * 70)
    print("FINAL TEST SUMMARY")
    print("=" * 70)
    print()
    
    passed = sum(1 for _, success in results if success)
    total = len(results)
    
    for description, success in results:
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{status} - {description}")
    
    print()
    print(f"Total: {passed}/{total} tests passed")
    print("=" * 70)
    
    return passed == total


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
