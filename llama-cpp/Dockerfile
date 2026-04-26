# -- llama.cpp build for AMD ROCm 7 and gfx1201 -------------------------------
FROM rocm/dev-ubuntu-24.04:7.2.2-complete

ARG HOST_UID="1000"
ARG HOST_GID="$HOST_UID"
ARG LLAMA_CPP_REPO="https://github.com/ggml-org/llama.cpp"
ARG LLAMA_CPP_REF="master"
ARG LLAMA_CPP_USER="llama-cpp"
ARG ROCM_ARCH="gfx1201"

# Install build dependencies
RUN apt update && \
    apt install -y cmake git libcurl4-openssl-dev nano && \
    rm -rf /var/lib/apt/lists/*

# Set up a user and group that match the host's UID and GID to avoid permission issues with mounted volumes
RUN groupadd --gid "$HOST_GID" "$LLAMA_CPP_USER" || true \
    && useradd --uid "$HOST_UID" --gid "$HOST_GID" -m "$LLAMA_CPP_USER" \
    && usermod -aG sudo "$LLAMA_CPP_USER" \
    && echo "$LLAMA_CPP_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Build llama.cpp from source
WORKDIR /opt/llama-cpp

RUN git clone "${LLAMA_CPP_REPO}" . && \
    git checkout "${LLAMA_CPP_REF}"

RUN HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
    cmake -S . \
    -B build -DGGML_HIP=ON -DAMDGPU_TARGETS="${ROCM_ARCH}" \
    -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=ON \
    && cmake --build build --config Release -j$(nproc)

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh && \
    chown -R "${LLAMA_CPP_USER}:${LLAMA_CPP_USER}" /opt/llama-cpp "/home/${LLAMA_CPP_USER}"

# Set environment variables for the user and application
ENV USER="${LLAMA_CPP_USER}"
ENV HOME="/home/${USER}"
ENV UID="${HOST_UID}"
ENV GID="${HOST_GID}"
ENV XDG_CACHE_HOME="${HOME}/.cache"
ENV HIP_COMPILER_CACHE_DIR="${XDG_CACHE_HOME}/HIP"
ENV AMD_COMGR_CACHE_DIR="${XDG_CACHE_HOME}/comgr"

# Run llama.cpp
WORKDIR "${HOME}"
USER "${USER}"
EXPOSE 8000/tcp
ENTRYPOINT ["/entrypoint.sh"]
