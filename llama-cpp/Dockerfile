# -- llama.cpp build for AMD ROCm 7 and gfx1201 -------------------------------
FROM rocm/dev-ubuntu-24.04:7.2.2-complete

ARG HOST_UID="1000"
ARG HOST_GID="$HOST_UID"
ARG LLAMA_CPP_REPO="https://github.com/TheTom/llama-cpp-turboquant"
ARG LLAMA_CPP_REF="feature/turboquant-kv-cache"
ARG LLAMA_CPP_USER="llama-cpp"
ARG ROCM_ARCH="gfx1201"

ENV DEBIAN_FRONTEND="noninteractive"

# Install build dependencies
RUN apt update && \
    apt install -y cmake git libcurl4-openssl-dev nano ninja-build && \
    rm -rf /var/lib/apt/lists/*

# Set up a user and group that match the host's UID and GID to avoid permission issues with mounted volumes
RUN \
    if getent group "${HOST_GID}" > /dev/null 2>&1; then \
        OLD_GROUP=$(getent group "${HOST_GID}" | cut -d: -f1); \
        groupmod -n "${LLAMA_CPP_USER}" "$OLD_GROUP"; \
    else \
        groupadd --system --gid "${HOST_GID}" "${LLAMA_CPP_USER}"; \
    fi && \
    if getent passwd "${HOST_UID}" > /dev/null 2>&1; then \
        OLD_USER=$(getent passwd "${HOST_UID}" | cut -d: -f1); \
        usermod -l "${LLAMA_CPP_USER}" -d "/home/${LLAMA_CPP_USER}" -m "$OLD_USER"; \
    else \
        useradd --system --uid "${HOST_UID}" --gid "${HOST_GID}" --home "/home/${LLAMA_CPP_USER}" --create-home "${LLAMA_CPP_USER}"; \
    fi

# Build llama.cpp from source
WORKDIR /opt/llama-cpp

RUN git clone "${LLAMA_CPP_REPO}" . && \
    git checkout "${LLAMA_CPP_REF}"

RUN HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
    cmake -S . \
    -B build \
    -G "Ninja" \
    -DAMDGPU_TARGETS="${ROCM_ARCH}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/opt/rocm/llvm/bin/clang \
    -DCMAKE_CXX_COMPILER=/opt/rocm/llvm/bin/clang++ \
    -DGGML_CUDA_FA_ALL_QUANTS=ON \
    -DGGML_HIP=ON \
    -DLLAMA_CURL=ON \
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
