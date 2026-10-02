# HDL simulation tools for the Dethrace core testbenches
FROM debian:bookworm
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        iverilog verilator g++ make python3 python3-pil \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
