# -- llama.cpp build for AMD ROCm 7 -------------------------------------------------
FROM rocm/dev-ubuntu-24.04:7.0-complete

RUN apt update
RUN apt install -y install -y nano libcurl4-openssl-dev cmake git
RUN rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/ROCm/llama.cpp /opt/llama-cpp
WORKDIR /opt/llama-cpp

RUN export LLAMACPP_ROCM_ARCH=gfx1201
RUN HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
    cmake -S . -B build -DGGML_HIP=ON -DAMDGPU_TARGETS=$LLAMACPP_ROCM_ARCH \
    -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=ON \
    && cmake --build build --config Release -j$(nproc)

WORKDIR /opt/llama-cpp/build

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
