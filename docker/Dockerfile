ARG BASE_REPO
FROM ${BASE_REPO}
ARG ADD_DEVTOOLS_OPTION
ARG USERNAME
WORKDIR /workdir
COPY . /workdir/
RUN apt-get update && \
    apt-get -y install sudo
RUN bash /workdir/setup-build-env $ADD_DEVTOOLS_OPTION
ENV VENV_DIR /workdir/.venv
ENV PATH ${VENV_DIR}/bin:$PATH
ENV PYTHONPATH /workdir/.venv/bin
ENV USER $USERNAME
