#!/bin/bash
#
# create-feature-env.sh
# Creates a new PostgreSQL VDB environment for a feature branch
#
# Usage: ./create-feature-env.sh <feature-name> [options]
# Example: ./create-feature-env.sh feat-789-new-api --memory 4Gi --cpu 2

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
MEMORY_REQUEST="2Gi"
CPU_REQUEST="1"
MEMORY_LIMIT="4Gi"
CPU_LIMIT="2"
REPO_BRANCH="main"

# Parse arguments
FEATURE_NAME=$1
if [ -z "$FEATURE_NAME" ]; then
    echo -e "${RED}Error: Feature name is required${NC}"
    echo "Usage: $0 <feature-name> [options]"
    echo ""
    echo "Options:"
    echo "  --memory-request <size>   Memory request (default: 2Gi)"
    echo "  --cpu-request <size>      CPU request (default: 1)"
    echo "  --memory-limit <size>     Memory limit (default: 4Gi)"
    echo "  --cpu-limit <size>        CPU limit (default: 2)"
    echo "  --branch <name>           Git branch to commit to (default: main)"
    echo ""
    echo "Example:"
    echo "  $0 feat-789-new-api --memory-request 4Gi --cpu-request 2"
    exit 1
fi

shift

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --memory-request)
            MEMORY_REQUEST="$2"
            shift 2
            ;;
        --cpu-request)
            CPU_REQUEST="$2"
            shift 2
            ;;
        --memory-limit)
            MEMORY_LIMIT="$2"
            shift 2
            ;;
        --cpu-limit)
            CPU_LIMIT="$2"
            shift 2
            ;;
        --branch)
            REPO_BRANCH="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Validate feature name format
if [[ ! "$FEATURE_NAME" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
    echo -e "${RED}Error: Feature name must be lowercase alphanumeric with hyphens${NC}"
    exit 1
fi

# Generate secure random password
PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

# File path
VALUES_FILE="environments/features/values-${FEATURE_NAME}.yaml"

# Check if file already exists
if [ -f "$VALUES_FILE" ]; then
    echo -e "${YELLOW}Warning: Feature environment '${FEATURE_NAME}' already exists${NC}"
    read -p "Do you want to overwrite it? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

echo -e "${GREEN}Creating feature environment for ${FEATURE_NAME}...${NC}"

# Sanitize feature name for database identifiers (replace hyphens with underscores)
DB_NAME=$(echo "${FEATURE_NAME}" | tr '-' '_')

# Create values file for feature branch
cat > "$VALUES_FILE" << EOF
environment: feature
featureBranch: "${FEATURE_NAME}"

vdb:
  name: "${FEATURE_NAME}-vdb"
  database:
    name: "${DB_NAME}_app"
    user: "${DB_NAME}_user"
    password: "${PASSWORD}"
  
  resources:
    requests:
      memory: "${MEMORY_REQUEST}"
      cpu: "${CPU_REQUEST}"
    limits:
      memory: "${MEMORY_LIMIT}"
      cpu: "${CPU_LIMIT}"
  
  hooks:
    - name: "init-${DB_NAME}-schema"
      stage: "post-create"
      database: "${DB_NAME}_app"
      script: |
        -- Create feature-specific schemas
        CREATE SCHEMA IF NOT EXISTS ${DB_NAME}_experimental;
        CREATE SCHEMA IF NOT EXISTS ${DB_NAME}_testing;
        
        -- Create experimental data table
        CREATE TABLE IF NOT EXISTS ${DB_NAME}_experimental.experimental_data (
          id SERIAL PRIMARY KEY,
          feature_name VARCHAR(100) NOT NULL,
          feature_data JSONB,
          created_at TIMESTAMP DEFAULT NOW(),
          updated_at TIMESTAMP DEFAULT NOW(),
          created_by VARCHAR(100),
          status VARCHAR(50) DEFAULT 'active'
        );
        
        -- Create feature flag table
        CREATE TABLE IF NOT EXISTS ${DB_NAME}_experimental.feature_flags (
          flag_id SERIAL PRIMARY KEY,
          flag_name VARCHAR(100) UNIQUE NOT NULL,
          enabled BOOLEAN DEFAULT false,
          description TEXT,
          created_at TIMESTAMP DEFAULT NOW()
        );
        
        -- Create test data table
        CREATE TABLE IF NOT EXISTS ${DB_NAME}_testing.test_data (
          test_id SERIAL PRIMARY KEY,
          test_case VARCHAR(255) NOT NULL,
          input_data JSONB,
          expected_output JSONB,
          actual_output JSONB,
          passed BOOLEAN,
          executed_at TIMESTAMP DEFAULT NOW()
        );
        
        -- Create indexes
        CREATE INDEX IF NOT EXISTS idx_experimental_data_feature ON ${DB_NAME}_experimental.experimental_data(feature_name);
        CREATE INDEX IF NOT EXISTS idx_experimental_data_status ON ${DB_NAME}_experimental.experimental_data(status);
        CREATE INDEX IF NOT EXISTS idx_test_data_case ON ${DB_NAME}_testing.test_data(test_case);
        
        -- Grant permissions
        GRANT ALL ON SCHEMA ${DB_NAME}_experimental TO ${DB_NAME}_user;
        GRANT ALL ON SCHEMA ${DB_NAME}_testing TO ${DB_NAME}_user;
        GRANT ALL ON ALL TABLES IN SCHEMA ${DB_NAME}_experimental TO ${DB_NAME}_user;
        GRANT ALL ON ALL TABLES IN SCHEMA ${DB_NAME}_testing TO ${DB_NAME}_user;
        GRANT ALL ON ALL SEQUENCES IN SCHEMA ${DB_NAME}_experimental TO ${DB_NAME}_user;
        GRANT ALL ON ALL SEQUENCES IN SCHEMA ${DB_NAME}_testing TO ${DB_NAME}_user;
        
        -- Insert initial feature flags
        INSERT INTO ${DB_NAME}_experimental.feature_flags (flag_name, enabled, description)
        VALUES 
          ('${DB_NAME}_enabled', true, 'Master feature flag for ${FEATURE_NAME}'),
          ('${DB_NAME}_debug_mode', false, 'Enable debug logging for ${FEATURE_NAME}')
        ON CONFLICT (flag_name) DO NOTHING;
        
        -- Insert initialization marker
        INSERT INTO ${DB_NAME}_experimental.experimental_data (feature_name, feature_data, created_by)
        VALUES ('${FEATURE_NAME}-init', '{"status": "initialized", "version": "0.1.0", "created": "'||NOW()||'"}'::jsonb, 'system');

# Monitoring for feature branch
monitoring:
  enabled: true
  serviceMonitor:
    enabled: false

# Service configuration
service:
  type: ClusterIP
  annotations:
    feature.branch: "${FEATURE_NAME}"
    feature.created: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    feature.expires: "30d"
EOF

echo -e "${GREEN}✓ Created feature environment configuration${NC}"
echo "  File: $VALUES_FILE"
echo ""
echo -e "${YELLOW}Database Credentials (save these securely):${NC}"
echo "  Database: ${DB_NAME}_app"
echo "  Username: ${DB_NAME}_user"
echo "  Password: ${PASSWORD}"
echo ""

# Git operations
echo -e "${GREEN}Committing to Git...${NC}"

# Check if git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

# Add and commit
git add "$VALUES_FILE"
git commit -m "Add feature environment for ${FEATURE_NAME}

- Memory: ${MEMORY_REQUEST} / ${MEMORY_LIMIT}
- CPU: ${CPU_REQUEST} / ${CPU_LIMIT}
- Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)
"

echo -e "${GREEN}✓ Committed changes${NC}"

# Push to remote
echo -e "${GREEN}Pushing to ${REPO_BRANCH}...${NC}"
git push origin "$REPO_BRANCH"

echo ""
echo -e "${GREEN}✓✓✓ Feature environment ${FEATURE_NAME} created successfully! ✓✓✓${NC}"
echo ""
echo "Next steps:"
echo "  1. ArgoCD will automatically detect and provision the environment"
echo "  2. Monitor progress: argocd app get postgres-vdb-${FEATURE_NAME}"
echo "  3. Check VDB status: kubectl get postgresvdb -n postgres-vdbs-feature-${FEATURE_NAME}"
echo "  4. Connect to database:"
echo "     kubectl port-forward svc/${FEATURE_NAME}-vdb 5432:5432 -n postgres-vdbs-feature-${FEATURE_NAME}"
echo "     psql -h localhost -p 5432 -U ${DB_NAME}_user -d ${DB_NAME}_app"
echo ""
