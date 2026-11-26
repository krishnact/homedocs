ARG POSTGRES_VERSION=18
FROM postgres:${POSTGRES_VERSION}

ARG CLIGOO_REF=444ae9c54690a0e77d0ba148cc9921477b75cdff

RUN apt-get update && apt-get install -y --no-install-recommends \
      rclone \
      ca-certificates \
      python3 \
      python3-venv \
      git \
    && python3 -m venv /opt/cligoo \
    && /opt/cligoo/bin/pip install --no-cache-dir \
         "cligoo @ git+https://github.com/marcomc/cligoo.git@${CLIGOO_REF}" \
    && ln -s /opt/cligoo/bin/cligoo /usr/local/bin/cligoo \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHON_KEYRING_BACKEND=keyring.backends.fail.Keyring

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh
ENTRYPOINT ["/usr/local/bin/backup.sh"]
