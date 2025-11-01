#!/bin/bash

source ./login.sh

# VAST AI Upload and Setup Script
# Usage: ./upload.sh

# --- Configuration ---
PROJECT_NAME="TISAI-207-kubernetes"
LOCAL_ZIP="${PROJECT_NAME}.zip"
REMOTE_HOST="root@${INSTANCE_IP}"
SSH_OPTS="-p ${INSTANCE_PORT}"
SCP_OPTS="-P ${INSTANCE_PORT}"

echo "🚀 Starting VAST AI setup for ${PROJECT_NAME}..."
echo "Instance: ${REMOTE_HOST}:${INSTANCE_PORT}"

# --- Create Project Archive ---
echo "📦 Creating project archive from current directory..."
zip -r "${LOCAL_ZIP}" Makefile server_init.sh kubernetes/

echo "✅ Created ${LOCAL_ZIP} ($(du -h ${LOCAL_ZIP} | cut -f1))"

# --- Upload Zip File ---
echo "⬆️  Uploading ${LOCAL_ZIP}..."
scp $SCP_OPTS "${LOCAL_ZIP}" "${REMOTE_HOST}:/root/"

if [ $? -ne 0 ]; then
    echo "❌ Upload failed!"
    exit 1
fi

echo "✅ Upload complete!"

# --- SSH and Setup on Remote ---
echo "🔧 Setting up on remote instance..."
ssh $SSH_OPTS $REMOTE_HOST << EOF
    PROJECT_DIR="/root/${PROJECT_NAME}"
    PROJECT_ZIP="/root/${LOCAL_ZIP}"

    echo "📦 Creating project directory and extracting..."
    mkdir -p \${PROJECT_DIR}
    unzip -o \${PROJECT_ZIP} -d \${PROJECT_DIR}

    cd \${PROJECT_DIR}

    echo "🔧 Setting file permissions..."
    chmod +x *.sh
    echo "✅ Execute permission set for bash scripts."
    
    echo "🎯 Ready for processing!"
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Setup complete!"
    echo "💡 Next steps:"
    echo "   1. SSH into instance: ssh $SSH_OPTS $REMOTE_HOST"
    echo "   2. Go to project folder: cd /root/${PROJECT_NAME}"
else
    echo "❌ Setup failed!"
    exit 1
fi

