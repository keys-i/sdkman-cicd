FROM debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get -o Acquire::Retries=3 --error-on=any update \
    && apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        libdigest-sha-perl \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 --shell /bin/bash sdkman \
    && install -d -o sdkman -g sdkman /opt /workspace \
    && printf '\nsource "$SDKMAN_DIR/bin/sdkman-init.sh"\n' >> /etc/bash.bashrc

ENV SDKMAN_DIR=/opt/sdkman \
    LANG=C.UTF-8

COPY --chown=sdkman:sdkman docker/install-sdkman.sh docker/configure-sdkman.sh /tmp/

USER sdkman
WORKDIR /workspace

RUN bash /tmp/install-sdkman.sh \
    && rm /tmp/install-sdkman.sh /tmp/configure-sdkman.sh

ENV BASH_ENV=/opt/sdkman/bin/sdkman-init.sh

CMD ["/bin/bash"]
