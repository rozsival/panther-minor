FROM rocm/llama.cpp:llama.cpp-b6652.amd0_rocm7.0.0_ubuntu24.04_full

USER root
RUN apt update
RUN apt install -y curl jq
RUN rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
