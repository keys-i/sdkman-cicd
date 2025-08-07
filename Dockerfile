FROM debian:bookworm-slim@sha256:40b107342c492725bc7aacbe93a49945445191ae364184a6d24fedb28172f6f7

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get -o Acquire::Retries=3 --error-on=any update \
    && apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        libdigest-sha-perl \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 --shell /bin/bash sdkman \
    && install -d -o sdkman -g sdkman /opt/sdkman /workspace \
    && printf '\nsource "$SDKMAN_DIR/bin/sdkman-init.sh"\n' >> /etc/bash.bashrc

ENV SDKMAN_DIR=/opt/sdkman \
    LANG=C.UTF-8

COPY --chown=sdkman:sdkman docker/configure-sdkman.sh /tmp/configure-sdkman.sh

USER sdkman
WORKDIR /workspace

RUN curl --fail --show-error --silent --location \
        --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 120 \
        --retry 3 --retry-max-time 180 \
        'https://get.sdkman.io?rcupdate=false' \
        --output /tmp/install-sdkman.sh \
    && bash /tmp/install-sdkman.sh \
    && bash /tmp/configure-sdkman.sh \
    && rm /tmp/install-sdkman.sh /tmp/configure-sdkman.sh \
    && source "$SDKMAN_DIR/bin/sdkman-init.sh" \
    && sdk version

ENV BASH_ENV=/opt/sdkman/bin/sdkman-init.sh

CMD ["/bin/bash"]
