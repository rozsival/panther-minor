# -- OpenFang Container (https://www.openfang.sh/) ----------------------------
FROM debian:bookworm-slim

# Install runtime dependencies as root
RUN apt-get update
RUN apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dpkg \
    	libssl3
RUN rm -rf /var/lib/apt/lists/*

# Create openfang user and set up home directory
RUN useradd -m openfang
USER openfang
WORKDIR /home/openfang/.openfang

# Install OpenFang and make the binary available on PATH
RUN curl -fsSL https://openfang.sh/install | sh
ENV PATH="/home/openfang/.openfang/bin:${PATH}"

# Prepare workspace
RUN mkdir -p ./agents
RUN mkdir -p ./data

# Configure OpenFang
COPY --chown=openfang config.toml .

# Run OpenFang
WORKDIR /home/openfang
EXPOSE 4200/tcp
ENTRYPOINT ["openfang"]
CMD ["start"]
