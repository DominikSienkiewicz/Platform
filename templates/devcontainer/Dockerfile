# Devcontainer repozytorium konsumenta (N-SHOW-11), INCUBATING do pierwszej adopcji (Decyzja 7): JDK 25 uruchamia Gradle'a,
# JDK 27 to toolchain kanonu, Node 24 z npm dla frontendu. Kopiuj razem z devcontainer.json i post-create.sh do .devcontainer/.
# Wersje nie są nowym źródłem prawdy: templates/tests/consumer-devcontainer.test.sh porównuje je z kryteriami demona
# (templates/jvm/*/gradle/gradle-daemon-jvm.properties i java-version z backend-ci.yml), katalogiem (java) i frontend/.nvmrc.
# Obraz bazowy po digeście (OpenSSF Scorecard, Pinned-Dependencies); nowy: docker buildx imagetools inspect <obraz:tag>.
# Token GitHub Packages nie trafia do obrazu: przychodzi z remoteEnv (devcontainer.json) dopiero w działającym kontenerze.
FROM mcr.microsoft.com/devcontainers/base:2-ubuntu-24.04@sha256:d94c97dd9cacf183d0a6fd12a8e87b526e9e928307674ae9c94139139c0c6eae

ARG GRADLE_JDK=25
ARG TOOLCHAIN_JDK=27
ARG NODE_MAJOR=24

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# JDK-i z API Adoptium (Temurin, glibc), każdy sprawdzony sumą SHA-256 z tego samego API; Node z nodejs.org (sumy z SHASUMS256.txt).
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
    tar -xJf "/tmp/$archive" -C /usr/local --strip-components=1; rm "/tmp/$archive"

# JAVA_HOME to JDK Gradle'a; post-create.sh rejestruje TOOLCHAIN_JAVA_HOME w ~/.gradle/gradle.properties.
ENV JAVA_HOME=/opt/jdk-${GRADLE_JDK}
ENV TOOLCHAIN_JAVA_HOME=/opt/jdk-${TOOLCHAIN_JDK}
ENV PATH=${JAVA_HOME}/bin:${PATH}
