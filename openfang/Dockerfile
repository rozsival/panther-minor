ARG OPENFANG_IMAGE
FROM $OPENFANG_IMAGE

# Create empty .env file (can be overridden by user's mounted .env)
ARG OPENFANG_HOME
RUN touch "$OPENFANG_HOME/.env"
RUN chmod 644 "$OPENFANG_HOME/.env"

# Copy the entrypoint script
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
