#!/bin/bash
# Render Startup Script
# This script runs before the app starts to verify everything is configured

echo "🚀 Starting SEBRAE Chatbot on Render..."
echo "========================================="

# Check environment variables
echo "✓ Checking environment variables..."

if [ -z "$OPENAI_API_KEY" ]; then
    echo "❌ ERROR: OPENAI_API_KEY is not set!"
    echo "Please add it in Render Environment Variables"
    exit 1
else
    echo "✓ OPENAI_API_KEY is set"
fi

if [ -z "$PORT" ]; then
    echo "⚠️  WARNING: PORT not set, using default 10000"
    export PORT=10000
else
    echo "✓ PORT is set to $PORT"
fi

# Check required files
echo "✓ Checking required files..."

if [ ! -f "/app/shiny_app.R" ]; then
    echo "❌ ERROR: shiny_app.R not found!"
    exit 1
else
    echo "✓ shiny_app.R found"
fi

if [ ! -f "/app/Base_Conhecimento_MEI_SEBRAE_Completa_v2.txt" ]; then
    echo "❌ ERROR: Knowledge base file not found!"
    exit 1
else
    echo "✓ Knowledge base found"
fi

# Check data directory
echo "✓ Checking data directory..."
if [ ! -d "/app/data" ]; then
    echo "Creating /app/data directory..."
    mkdir -p /app/data/audio
fi

if [ ! -d "/app/data/audio" ]; then
    echo "Creating /app/data/audio directory..."
    mkdir -p /app/data/audio
fi

echo "✓ Data directories ready"

# Display configuration
echo "========================================="
echo "Configuration:"
echo "  - Port: $PORT"
echo "  - Audio Enabled: ${ENABLE_AUDIO_RESPONSES:-false}"
echo "  - Voice: ${AUDIO_VOICE:-nova}"
echo "  - Environment: ${RENDER:+Production}"
echo "========================================="

echo "✅ Pre-flight checks complete!"
echo "🎯 Starting Shiny application..."
echo ""

# Start the app
exec R -e "port <- as.numeric(Sys.getenv('PORT', '10000')); message('Shiny listening on port ', port); shiny::runApp('/app/shiny_app.R', host='0.0.0.0', port=port)"
