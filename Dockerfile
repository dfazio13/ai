FROM rocker/r-ver:4.3.2

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libsodium-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install R packages
RUN R -e "install.packages(c( \
    'shiny', \
    'bslib', \
    'httr2', \
    'jsonlite', \
    'DBI', \
    'RSQLite', \
    'curl', \
    'base64enc' \
    ), repos='https://cloud.r-project.org/')"

# Copy application files
COPY shiny_app.R /app/
COPY Base_Conhecimento_MEI_SEBRAE_Completa_v2.txt /app/
COPY start.sh /app/

# Make startup script executable
RUN chmod +x /app/start.sh

# Create data directory for SQLite database
RUN mkdir -p /app/data/audio

# Expose port for Shiny (Render uses PORT env variable)
EXPOSE 10000

# Set environment variable for Shiny to listen on all interfaces
ENV SHINY_HOST=0.0.0.0
# Render sets PORT environment variable - default to 10000 if not set
ENV PORT=10000
ENV RENDER=true

# Run the Shiny app using startup script
CMD ["/app/start.sh"]
