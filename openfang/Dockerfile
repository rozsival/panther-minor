# -- OpenFang Container (https://www.openfang.sh/) ----------------------------
FROM debian:bookworm-slim

# Install runtime dependencies as root
RUN apt-get update
RUN apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dpkg
RUN rm -rf /var/lib/apt/lists/*

# Create openfang user and set up home directory
RUN useradd -m openfang
USER openfang
WORKDIR /home/openfang

# Install OpenFang and make the binary available on PATH
RUN curl -fsSL https://openfang.sh/install | sh
ENV PATH="/home/openfang/.openfang/bin:${PATH}"

# Prepare workspace
RUN mkdir -p ./.openfang/agents
RUN mkdir -p ./.openfang/data

# Configure OpenFang
ARG MODEL="qwen3-coder:30b-a3b-q8_0"
COPY --chown="openfang" config.toml ./.openfang/
RUN echo "model = \"${MODEL}\"" >> ./.openfang/config.toml

# Run OpenFang
EXPOSE 4200/tcp
#ENTRYPOINT ["openfang"]
#CMD ["start"]
CMD ["sh", "-c", "echo 'OpenFang'"]
