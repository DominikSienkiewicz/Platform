# Devcontainer Platform (N-SHOW-11): JDK 25 uruchamia Gradle'a, JDK 27 to toolchain kanonu, Node 24 i pnpm z corepack.
# Wersje nie są nowym źródłem prawdy: templates/tests/devcontainer.test.sh porównuje je z katalogiem (java),
# backend-ci.yml (java-version), frontend/.nvmrc i packageManager z frontend/package.json.
FROM mcr.microsoft.com/devcontainers/base:2-ubuntu-24.04

ARG GRADLE_JDK=25
ARG TOOLCHAIN_JDK=27
ARG NODE_MAJOR=24
ARG PNPM_VERSION=11.18.0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# JDK-i z API Adoptium (Temurin, glibc), każdy sprawdzony sumą SHA-256 z tego samego API.
RUN set -eux; \
    apt-get update; apt-get install -y --no-install-recommends jq xz-utils; rm -rf /var/lib/apt/lists/*; \
    case "$(dpkg --print-architecture)" in amd64) jdk_arch=x64; node_arch=x64 ;; arm64) jdk_arch=aarch64; node_arch=arm64 ;; esac; \
    for version in "$GRADLE_JDK" "$TOOLCHAIN_JDK"; do \
      asset=$(curl -fsSL "https://api.adoptium.net/v3/assets/latest/$version/hotspot?architecture=$jdk_arch&image_type=jdk&os=linux&vendor=eclipse"); \
      link=$(jq -r '.[0].binary.package.link' <<<"$asset"); \
      checksum=$(jq -r '.[0].binary.package.checksum' <<<"$asset"); \
      curl -fsSL "$link" -o /tmp/jdk.tar.gz; \
      echo "$checksum  /tmp/jdk.tar.gz" | sha256sum -c -; \
      mkdir -p "/opt/jdk-$version"; tar -xzf /tmp/jdk.tar.gz -C "/opt/jdk-$version" --strip-components=1; rm /tmp/jdk.tar.gz; \
    done; \
    sums=$(curl -fsSL "https://nodejs.org/dist/latest-v$NODE_MAJOR.x/SHASUMS256.txt"); \
    archive=$(awk -v suffix="-linux-$node_arch.tar.xz" 'index($2, suffix) { print $2 }' <<<"$sums"); \
    curl -fsSL "https://nodejs.org/dist/latest-v$NODE_MAJOR.x/$archive" -o "/tmp/$archive"; \
    (cd /tmp && grep " $archive\$" <<<"$sums" | sha256sum -c -); \
    tar -xJf "/tmp/$archive" -C /usr/local --strip-components=1; rm "/tmp/$archive"; \
    corepack enable; \
    corepack prepare "pnpm@$PNPM_VERSION" --activate

ENV JAVA_HOME=/opt/jdk-25
ENV PATH=/opt/jdk-25/bin:$PATH
