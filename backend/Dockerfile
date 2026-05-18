# Multi-stage: AOT-compile the Dart server to a native binary, then ship
# it on a minimal Debian image. Final image ≈ 100 MB.

FROM dart:3.5 AS build
WORKDIR /app

# Resolve dependencies first (cacheable layer).
COPY pubspec.* ./
RUN dart pub get --no-precompile

# Build the server.
COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o /app/server
RUN dart compile exe bin/seed_admin.dart -o /app/seed_admin

# Runtime image — needs CA certs for outbound TLS (voicepassword, GigaChat).
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/server /app/server
COPY --from=build /app/seed_admin /app/seed_admin
COPY --from=build /app/migrations /app/migrations

EXPOSE 8080
CMD ["/app/server"]
