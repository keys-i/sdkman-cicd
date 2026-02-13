FROM debian:trixie-slim@sha256:f6e2cfac5cf956ea044b4bd75e6397b4372ad88fe00908045e9a0d21712ae3ba

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

# Apply the download policy to the installer and its child curl processes
RUN sdkman_curl_home=$(mktemp -d) \
    && printf '%s\n' \
        'fail' \
        'show-error' \
        'proto = "=https"' \
        'proto-redir = "=https"' \
        'connect-timeout = 10' \
        'max-time = 120' \
        'retry = 3' \
        'retry-max-time = 180' > "$sdkman_curl_home/.curlrc" \
    && CURL_HOME="$sdkman_curl_home" curl --silent --location \
        'https://get.sdkman.io?ci=true&rcupdate=false' \
        --output /tmp/install-sdkman.sh \
    && CURL_HOME="$sdkman_curl_home" bash /tmp/install-sdkman.sh \
    && bash /tmp/configure-sdkman.sh \
    && rm /tmp/install-sdkman.sh /tmp/configure-sdkman.sh "$sdkman_curl_home/.curlrc" \
    && rmdir "$sdkman_curl_home" \
    && source "$SDKMAN_DIR/bin/sdkman-init.sh" \
    && sdk version

ENV BASH_ENV=/opt/sdkman/bin/sdkman-init.sh

CMD ["/bin/bash"]
