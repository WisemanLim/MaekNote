# maeknote — Linux 설치 이미지(tar.gz) 빌드. 사용: make dist-linux-docker
# 호스트 CPU 아키텍처용(arm64 호스트 → linux-arm64, x64 호스트 → linux-x64) 번들을 만든다.
FROM ubuntu:24.04 AS build
ARG FLUTTER_VERSION=3.41.9
ARG VERSION=0.0.0
ENV DEBIAN_FRONTEND=noninteractive PATH=/opt/flutter/bin:$PATH
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip build-essential clang lld llvm cmake ninja-build pkg-config \
      libgtk-3-dev libmpv-dev libsecret-1-dev libjsoncpp-dev libstdc++-12-dev \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 -b $FLUTTER_VERSION https://github.com/flutter/flutter.git /opt/flutter \
    && flutter config --no-analytics --enable-linux-desktop && flutter precache --linux
WORKDIR /src
COPY . .
RUN flutter pub get && flutter build linux --release --dart-define-from-file=.env.prod
RUN arch=$(uname -m | sed -e 's/x86_64/x64/' -e 's/aarch64/arm64/') \
    && mkdir -p /out && cp -r build/linux/$arch/release/bundle /tmp/maeknote \
    && cp packaging/linux/maeknote.desktop /tmp/maeknote/ \
    && tar -C /tmp -czf /out/MaekNote-$VERSION-linux-$arch.tar.gz maeknote

FROM scratch
COPY --from=build /out/ /
