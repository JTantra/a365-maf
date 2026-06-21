FROM mcr.microsoft.com/devcontainers/python:1-3.11-bookworm

RUN set -eux; \
    curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg \
    | gpg --dearmor --batch --yes -o /usr/share/keyrings/yarn-archive-keyring.gpg