# -- llama.cpp build for AMD ROCm 7 and gfx1201 -------------------------------
FROM rocm/dev-ubuntu-24.04:7.2-complete

ARG LLAMA_CPP_REPO="https://github.com/ggml-org/llama.cpp"
ARG LLAMA_CPP_REF="master"
ARG LLAMA_CPP_USER="llama-cpp"
ARG ROCM_ARCH="gfx1201"

RUN apt update
RUN apt install -y cmake git libcurl4-openssl-dev nano
RUN rm -rf /var/lib/apt/lists/*

RUN groupadd --system "${LLAMA_CPP_USER}"
RUN useradd --system --gid "${LLAMA_CPP_USER}" --home "/home/${LLAMA_CPP_USER}" --create-home "${LLAMA_CPP_USER}"

WORKDIR /opt/llama-cpp

RUN git clone "${LLAMA_CPP_REPO}" .
RUN git checkout "${LLAMA_CPP_REF}"

RUN HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
	cmake -S . -B build -DGGML_HIP=ON -DAMDGPU_TARGETS="${ROCM_ARCH}" \
	-DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=ON \
	&& cmake --build build --config Release -j$(nproc)

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
RUN chown -R "${LLAMA_CPP_USER}:${LLAMA_CPP_USER}" /opt/llama-cpp "/home/${LLAMA_CPP_USER}"

USER "$LLAMA_CPP_USER"
EXPOSE 8000/tcp
ENTRYPOINT ["/entrypoint.sh"]
