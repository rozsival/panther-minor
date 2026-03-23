ARG OPENFANG_IMAGE
FROM $OPENFANG_IMAGE

# Copy the entrypoint script
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
