#!/bin/bash
#
# cleanup-feature-env.sh
# Removes a PostgreSQL VDB feature environment
#
# Usage: ./cleanup-feature-env.sh <feature-name> [options]
# Example: ./cleanup-feature-env.sh feat-789-new-api

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
REPO_BRANCH="main"
FORCE=false

# Parse arguments
FEATURE_NAME=$1
if [ -z "$FEATURE_NAME" ]; then
    echo -e "${RED}Error: Feature name is required${NC}"
    echo "Usage: $0 <feature-name> [options]"
    echo ""
    echo "Options:"
    echo "  --branch <name>   Git branch to commit to (default: main)"
    echo "  --force           Skip confirmation prompt"
    echo ""
    echo "Example:"
    echo "  $0 feat-789-new-api"
    echo "  $0 feat-789-new-api --force"
    exit 1
fi

shift

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --branch)
            REPO_BRANCH="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# File path
VALUES_FILE="environments/features/values-${FEATURE_NAME}.yaml"

# Check if file exists
if [ ! -f "$VALUES_FILE" ]; then
    echo -e "${RED}Error: Feature environment '${FEATURE_NAME}' does not exist${NC}"
    echo "File not found: $VALUES_FILE"
    exit 1
fi

# Check if git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

echo -e "${BLUE}Feature Environment Cleanup${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Feature Name: ${FEATURE_NAME}"
echo "Values File:  ${VALUES_FILE}"
echo "Branch:       ${REPO_BRANCH}"
echo ""

# Show current resource status if kubectl is available
if command -v kubectl &> /dev/null; then
    NAMESPACE="postgres-vdbs-feature-${FEATURE_NAME}"
    echo -e "${YELLOW}Current Resource Status:${NC}"
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo ""
        echo "Namespace: $NAMESPACE"
        echo ""
        echo "PostgresVDB Resources:"
        kubectl get postgresvdb -n "$NAMESPACE" 2>/dev/null || echo "  (none found)"
        echo ""
        echo "Pods:"
        kubectl get pods -n "$NAMESPACE" 2>/dev/null || echo "  (none found)"
        echo ""
        echo "Services:"
        kubectl get services -n "$NAMESPACE" 2>/dev/null || echo "  (none found)"
        echo ""
    else
        echo "  Namespace '${NAMESPACE}' not found"
        echo ""
    fi
fi

# Show ArgoCD application status if argocd CLI is available
if command -v argocd &> /dev/null; then
    APP_NAME="postgres-vdb-${FEATURE_NAME}"
    echo -e "${YELLOW}ArgoCD Application Status:${NC}"
    
    if argocd app get "$APP_NAME" &> /dev/null; then
        argocd app get "$APP_NAME" --show-operation 2>/dev/null || true
        echo ""
    else
        echo "  Application '${APP_NAME}' not found"
        echo ""
    fi
fi

# Confirmation prompt
if [ "$FORCE" != "true" ]; then
    echo -e "${YELLOW}WARNING: This will:${NC}"
    echo "  1. Remove the values file from Git"
    echo "  2. Trigger ArgoCD to delete the application"
    echo "  3. Delete all Kubernetes resources (VDB, pods, services, etc.)"
    echo "  4. Delete the namespace postgres-vdbs-feature-${FEATURE_NAME}"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    read -p "Are you sure you want to cleanup ${FEATURE_NAME}? (yes/N) " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Cleanup aborted."
        exit 0
    fi
fi

echo ""
echo -e "${GREEN}Starting cleanup process...${NC}"
echo ""

# Remove values file
echo -e "${BLUE}[1/3]${NC} Removing values file..."
git rm "$VALUES_FILE"
echo -e "${GREEN}✓ File removed${NC}"

# Commit changes
echo -e "${BLUE}[2/3]${NC} Committing changes..."
git commit -m "Remove feature environment for ${FEATURE_NAME}

Cleanup performed at $(date -u +%Y-%m-%dT%H:%M:%SZ)
"
echo -e "${GREEN}✓ Changes committed${NC}"

# Push to remote
echo -e "${BLUE}[3/3]${NC} Pushing to ${REPO_BRANCH}..."
git push origin "$REPO_BRANCH"
echo -e "${GREEN}✓ Changes pushed${NC}"

echo ""
echo -e "${GREEN}✓✓✓ Cleanup initiated successfully! ✓✓✓${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. ArgoCD will automatically detect the deletion"
echo "  2. Monitor cleanup: argocd app get postgres-vdb-${FEATURE_NAME}"
echo "  3. Verify deletion: kubectl get namespace postgres-vdbs-feature-${FEATURE_NAME}"
echo ""
echo -e "${YELLOW}Note:${NC} Complete resource cleanup may take a few minutes."
echo ""

# Optional: Watch for deletion
if command -v kubectl &> /dev/null && [ "$FORCE" != "true" ]; then
    read -p "Watch namespace deletion? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Watching for namespace deletion (Ctrl+C to exit)..."
        kubectl get namespace "postgres-vdbs-feature-${FEATURE_NAME}" -w 2>/dev/null || echo "Namespace already deleted"
    fi
fi

echo ""
echo -e "${GREEN}Cleanup complete!${NC}"
