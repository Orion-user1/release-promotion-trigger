#!/bin/bash
#
# Test Script for Release Promotion Trigger
# ==========================================
# This script tests the promotion trigger with sample data
#

echo "🧪 Testing Release Promotion Trigger"
echo "====================================="

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo "❌ curl is not installed"
    exit 1
fi

# Set test environment variables
export VERSION="v1.0.0-test"
export ENVIRONMENT="dev"
export GITOPS_REPO_URL="https://api.example.com/gitops"
export GITOPS_API_TOKEN="test-token-12345"
export TRIGGER_TYPE="api"

echo ""
echo "🔧 Test Configuration:"
echo "   VERSION: ${VERSION}"
echo "   ENVIRONMENT: ${ENVIRONMENT}"
echo "   GITOPS_REPO_URL: ${GITOPS_REPO_URL}"
echo "   TRIGGER_TYPE: ${TRIGGER_TYPE}"
echo ""

# Run the script
echo "🚀 Running trigger script..."
echo "====================================="
bash scripts/trigger_promote_workflow.sh

exit_code=$?

echo ""
echo "====================================="
if [ $exit_code -eq 0 ]; then
    echo "✅ Test completed successfully!"
    echo ""
    echo "Note: This was a test run. The API call may have failed"
    echo "because the endpoint doesn't exist. This is expected."
    echo "Update GITOPS_REPO_URL and GITOPS_API_TOKEN with real"
    echo "values for actual usage."
else
    echo "❌ Test failed with exit code: $exit_code"
fi
echo "====================================="

exit $exit_code
