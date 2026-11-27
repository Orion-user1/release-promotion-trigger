#!/bin/bash
#
# Release Promotion Trigger Script
# =================================================
# This script triggers the environment promotion workflow in the GitOps repository.
# Simple, dependency-free implementation using only bash and curl.
#
# Environment Variables Required:
# - VERSION: Release version tag (e.g., v1.1.20-rc1)
# - ENVIRONMENT: Target environment (dev, qa, staging, prod)
# - GITOPS_REPO_URL: GitOps repository URL
# - GITOPS_API_TOKEN: Authentication token for GitOps API
# - TRIGGER_TYPE: (Optional) Type of trigger (api, webhook, github_actions) - default: api
# - PROMOTION_WORKFLOW_ID: (Optional) Workflow ID - default: promote_release

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions for logging
log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

# Print header
print_header() {
    echo ""
    log_info "============================================================"
    log_info "Release Promotion Trigger"
    log_info "============================================================"
    log_info "Version: ${VERSION}"
    log_info "Environment: ${ENVIRONMENT}"
    log_info "GitOps Repo: ${GITOPS_REPO_URL}"
    log_info "Trigger Type: ${TRIGGER_TYPE}"
    log_info "============================================================"
    echo ""
}

# Validate inputs
validate_inputs() {
    local errors=0

    if [ -z "$VERSION" ]; then
        log_error "VERSION environment variable is required"
        errors=$((errors + 1))
    fi

    if [ -z "$ENVIRONMENT" ]; then
        log_error "ENVIRONMENT environment variable is required"
        errors=$((errors + 1))
    elif [[ ! "$ENVIRONMENT" =~ ^(dev|qa|staging|prod)$ ]]; then
        log_error "Invalid ENVIRONMENT: $ENVIRONMENT. Must be: dev, qa, staging, or prod"
        errors=$((errors + 1))
    fi

    if [ -z "$GITOPS_REPO_URL" ]; then
        log_error "GITOPS_REPO_URL environment variable is required"
        errors=$((errors + 1))
    fi

    if [ -z "$GITOPS_API_TOKEN" ]; then
        log_error "GITOPS_API_TOKEN environment variable is required"
        errors=$((errors + 1))
    fi

    if [ $errors -gt 0 ]; then
        log_error "Validation failed with $errors error(s)"
        return 1
    fi

    log_success "Input validation passed"
    return 0
}

# Trigger via REST API
trigger_via_api() {
    log_info "Triggering promotion via REST API..."

    local api_url="${GITOPS_REPO_URL}/api/workflows/${PROMOTION_WORKFLOW_ID}/trigger"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create JSON payload
    local payload=$(cat <<EOF
{
  "version": "${VERSION}",
  "environment": "${ENVIRONMENT}",
  "source": "cicd-release-promotion-trigger",
  "timestamp": "${timestamp}",
  "triggered_by": "automated-pipeline"
}
EOF
)

    log_info "API URL: ${api_url}"
    log_info "Payload: ${payload}"

    # Make API call
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "${api_url}" \
        -H "Authorization: Bearer ${GITOPS_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -H "User-Agent: CICD-Release-Promotion-Trigger/1.0" \
        -d "${payload}" \
        --connect-timeout 10 \
        --max-time 30)

    # Extract status code and body
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    log_info "HTTP Status Code: ${http_code}"

    # Check response
    if [[ "$http_code" =~ ^(200|201|202)$ ]]; then
        log_success "Promotion workflow triggered successfully!"

        if [ -n "$body" ]; then
            log_info "Response: ${body}"

            # Try to extract workflow_id if present
            workflow_id=$(echo "$body" | grep -o '"workflow_id":"[^"]*"' | cut -d'"' -f4)
            if [ -n "$workflow_id" ]; then
                log_success "Workflow ID: ${workflow_id}"
            fi

            # Try to extract run_url if present
            run_url=$(echo "$body" | grep -o '"run_url":"[^"]*"' | cut -d'"' -f4)
            if [ -n "$run_url" ]; then
                log_success "Workflow URL: ${run_url}"
            fi
        fi

        return 0
    else
        log_error "API call failed with HTTP status ${http_code}"
        if [ -n "$body" ]; then
            log_error "Response: ${body}"
        fi
        return 1
    fi
}

# Trigger via Webhook
trigger_via_webhook() {
    log_info "Triggering promotion via webhook..."

    local webhook_url="${GITOPS_REPO_URL}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create JSON payload
    local payload=$(cat <<EOF
{
  "event_type": "promotion_trigger",
  "client_payload": {
    "version": "${VERSION}",
    "environment": "${ENVIRONMENT}",
    "source": "cicd-release-promotion-trigger",
    "timestamp": "${timestamp}"
  }
}
EOF
)

    log_info "Webhook URL: ${webhook_url}"

    # Make webhook call
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "${webhook_url}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${GITOPS_API_TOKEN}" \
        -d "${payload}" \
        --connect-timeout 10 \
        --max-time 30)

    # Extract status code
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    log_info "HTTP Status Code: ${http_code}"

    # Check response
    if [[ "$http_code" =~ ^(200|201|202|204)$ ]]; then
        log_success "Webhook triggered successfully!"
        return 0
    else
        log_error "Webhook failed with HTTP status ${http_code}"
        if [ -n "$body" ]; then
            log_error "Response: ${body}"
        fi
        return 1
    fi
}

# Trigger GitHub Actions workflow
trigger_github_actions() {
    log_info "Triggering GitHub Actions workflow..."

    # Extract owner/repo from GitHub URL
    # Example: https://github.com/owner/repo -> owner/repo
    local repo_path=$(echo "${GITOPS_REPO_URL}" | sed 's|https://github.com/||' | sed 's|\.git$||')
    local api_url="https://api.github.com/repos/${repo_path}/dispatches"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create JSON payload
    local payload=$(cat <<EOF
{
  "event_type": "promote_release",
  "client_payload": {
    "version": "${VERSION}",
    "environment": "${ENVIRONMENT}",
    "workflow_id": "${PROMOTION_WORKFLOW_ID}",
    "triggered_at": "${timestamp}"
  }
}
EOF
)

    log_info "GitHub API URL: ${api_url}"
    log_info "Repository: ${repo_path}"
    log_info "Payload: ${payload}"

    # Make GitHub API call
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "${api_url}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Authorization: Bearer ${GITOPS_API_TOKEN}" \
        -H "User-Agent: CICD-Release-Promotion-Trigger/1.0" \
        -d "${payload}" \
        --connect-timeout 10 \
        --max-time 30)

    # Extract status code
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    log_info "HTTP Status Code: ${http_code}"

    # Check response (GitHub returns 204 for success)
    if [ "$http_code" = "204" ]; then
        log_success "GitHub Actions workflow triggered successfully!"
        log_info "Check workflow runs at: https://github.com/${repo_path}/actions"
        return 0
    else
        log_error "GitHub API failed with HTTP status ${http_code}"
        if [ -n "$body" ]; then
            log_error "Response: ${body}"
        fi
        return 1
    fi
}

# Main function
main() {
    # Set defaults
    TRIGGER_TYPE=${TRIGGER_TYPE:-api}
    PROMOTION_WORKFLOW_ID=${PROMOTION_WORKFLOW_ID:-promote_release}

    # Print header
    print_header

    # Validate inputs
    if ! validate_inputs; then
        log_error "Input validation failed. Exiting."
        exit 1
    fi

    echo ""

    # Route to appropriate trigger method
    case "$TRIGGER_TYPE" in
        github_actions)
            if trigger_github_actions; then
                success=true
            else
                success=false
            fi
            ;;
        webhook)
            if trigger_via_webhook; then
                success=true
            else
                success=false
            fi
            ;;
        api|*)
            if trigger_via_api; then
                success=true
            else
                success=false
            fi
            ;;
    esac

    echo ""

    # Print result
    if [ "$success" = true ]; then
        log_success "============================================================"
        log_success "Promotion for ${VERSION} to ${ENVIRONMENT} initiated!"
        log_success "============================================================"
        exit 0
    else
        log_error "============================================================"
        log_error "Failed to trigger promotion workflow"
        log_error "============================================================"
        exit 1
    fi
}

# Check if curl is available
if ! command -v curl &> /dev/null; then
    log_error "curl is not installed. Please install curl to use this script."
    exit 1
fi

# Run main function
main
