FROM debian:bookworm-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        libdigest-sha-perl \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 --shell /bin/bash sdkman \
    && install -d -o sdkman -g sdkman /opt/sdkman /workspace

ENV SDKMAN_DIR=/opt/sdkman

COPY --chown=sdkman:sdkman docker/configure-sdkman.sh /tmp/configure-sdkman.sh

USER sdkman
WORKDIR /workspace

RUN curl --fail --show-error --silent --location \
        --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 120 \
        'https://get.sdkman.io?rcupdate=false' \
        --output /tmp/install-sdkman.sh \
    && bash /tmp/install-sdkman.sh \
    && bash /tmp/configure-sdkman.sh \
    && rm /tmp/install-sdkman.sh /tmp/configure-sdkman.sh \
    && printf '\nsource "$SDKMAN_DIR/bin/sdkman-init.sh"\n' >> /home/sdkman/.bashrc \
    && source "$SDKMAN_DIR/bin/sdkman-init.sh" \
    && sdk version

ENV BASH_ENV=/opt/sdkman/bin/sdkman-init.sh

CMD ["/bin/bash"]
