# syntax=docker/dockerfile:1.7
# SENTINEL Railway image — deterministic clean-bundle build.
#
# Only the checksum-pinned runtime bundle is admitted into /app. The GitHub
# working tree is deliberately not copied, so stale files left by browser
# uploads cannot mix with the release or make pytest exercise old code.

# Shared OS layer: Railway previously downloaded Debian packages twice (quality
# and runtime). Both stages now reuse one cached installation, and the mirror
# fallback handles transient HTTP/CDN failures.
FROM python:3.12-slim-bookworm AS system-dependencies
RUN set -eu; \
    installed=0; \
    for mirror in default https alternate; do \
      if [ "$mirror" = https ]; then \
        sed -i 's#http://deb.debian.org/#https://deb.debian.org/#g' /etc/apt/sources.list.d/debian.sources; \
      elif [ "$mirror" = alternate ]; then \
        sed -i 's#https://deb.debian.org/debian-security#https://security.debian.org/debian-security#g; s#https://deb.debian.org/debian#https://ftp.debian.org/debian#g' /etc/apt/sources.list.d/debian.sources; \
      fi; \
      echo "SENTINEL Debian system dependencies: trying $mirror mirror"; \
      if apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update \
        && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 install -y --no-install-recommends \
          adduser ca-certificates fonts-dejavu-core fonts-noto-core gosu nodejs postgresql-client tzdata; then \
        installed=1; break; \
      fi; \
      rm -rf /var/lib/apt/lists/*; \
      sleep 3; \
    done; \
    if [ "$installed" -ne 1 ]; then echo 'SENTINEL: apt dependencies unavailable after all 3 Debian mirrors' >&2; exit 1; fi; \
    test -s /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf; \
    test -s /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf; \
    node --version; \
    command -v gosu; \
    command -v psql; \
    rm -rf /var/lib/apt/lists/*

FROM system-dependencies AS quality
ARG SENTINEL_BUILD_REPAIR=railway-apt-shared-base-mirrors-c36
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=180 \
    TZ=Asia/Tehran \
    SENTINEL_COVERAGE_GROUP_SIZE=100 \
    SENTINEL_TEST_TIMEOUT_SECONDS=1200 \
    SENTINEL_COVERAGE_GROUP_TIMEOUT=1200 \
    SENTINEL_COVERAGE_WORKER_TIMEOUT=1500 \
    SENTINEL_QUALITY_FINALIZER_TIMEOUT=1560
LABEL io.sentinel.build-repair="${SENTINEL_BUILD_REPAIR}"
WORKDIR /bootstrap
COPY restore_runtime.py sentinel_runtime.zip sentinel_runtime.zip.sha256 ./
RUN set -eux; \
    expected="$(awk 'NR==1 {print $1}' sentinel_runtime.zip.sha256)"; \
    actual="$(sha256sum sentinel_runtime.zip | awk '{print $1}')"; \
    test -n "$expected"; \
    test "$actual" = "$expected"; \
    mkdir -p /app; \
    python /bootstrap/restore_runtime.py \
      --bundle /bootstrap/sentinel_runtime.zip \
      --destination /app \
      --canonicalize-quality \
      --profile quality; \
    cp /bootstrap/restore_runtime.py /bootstrap/sentinel_runtime.zip /bootstrap/sentinel_runtime.zip.sha256 /app/; \
    test -s /app/pytest.ini; \
    test -s /app/pyproject.toml; \
    test -s /app/tests/conftest.py; \
    test "$(find /app/tests -maxdepth 1 -type f -name 'test_*.py' | wc -l)" -gt 0
WORKDIR /app
RUN python -m pip install --require-hashes --no-cache-dir --prefer-binary --retries 8 --timeout 180 -r requirements-dev.lock.txt \
 && python -m pip check \
 && python -c 'import pytest_asyncio; print("pytest-asyncio=" + pytest_asyncio.__version__)'
RUN python scripts/quality_gate.py \
      --release-channel candidate \
      --full-suite \
      --candidate-line-threshold 19 \
      --candidate-critical-threshold 75 \
 && node scripts/check_miniapp_js.js \
 && python -m compileall -q main.py bot.py config.py bot_runtime core modules services repositories handlers jobs ui scripts tests \
 && printf 'version=%s\nsource_sha256=%s\nbundle_sha256=%s\nrepair=%s\n' \
      "$(cat VERSION)" \
      "$(python -c 'from scripts.quality_utils import source_fingerprint; from pathlib import Path; print(source_fingerprint(Path(".")))')" \
      "$(sha256sum sentinel_runtime.zip | awk '{print $1}')" \
      "$SENTINEL_BUILD_REPAIR" \
      > /app/.quality-stage-passed

FROM system-dependencies AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=180 \
    PORT=8080 \
    TZ=Asia/Tehran
WORKDIR /app
# All apt packages are inherited from system-dependencies; no second apt
# network request is made during the runtime stage.
RUN set -eux; \
    addgroup --system sentinel; \
    adduser --system --ingroup sentinel --home /app --no-create-home sentinel
COPY --from=quality /app/requirements.lock.txt /tmp/requirements.lock.txt
RUN python -m pip install --require-hashes --no-cache-dir --prefer-binary --only-binary=:all: --retries 8 --timeout 180 -r /tmp/requirements.lock.txt \
 && python -m pip check \
 && rm -f /tmp/requirements.lock.txt
COPY --from=quality /app /app
RUN test -s /app/.quality-stage-passed \
 && python -m compileall -q main.py bot.py config.py bot_runtime core modules services repositories handlers jobs ui scripts \
 && python main.py --check \
 && rm -rf /app/tests /app/.pytest_cache /app/.ruff_cache /app/.mypy_cache /app/.coverage /app/.coverage.* \
              /app/quality-artifacts \
              /app/requirements-dev.txt /app/requirements-dev.lock.txt /app/requirements-dev.in \
              /app/Dockerfile.quality /app/Dockerfile.quality.dockerignore \
 && rm -f /app/sentinel_runtime.zip /app/sentinel_runtime.zip.sha256 /app/restore_runtime.py \
 && mkdir -p /app/data/backups /app/data/payment_receipts /app/data/support_attachments \
              /app/data/signal_templates /app/logs \
 && chmod 0755 /app/scripts/docker-entrypoint.sh \
 && chown -R sentinel:sentinel /app
EXPOSE 8080
ENTRYPOINT ["/app/scripts/docker-entrypoint.sh"]
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
  CMD ["python", "scripts/healthcheck.py", "--mode", "http", "--timeout", "5"]
CMD ["python", "main.py"]
