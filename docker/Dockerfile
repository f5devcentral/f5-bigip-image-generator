ARG BASE_REPO
FROM ${BASE_REPO}
ARG ADD_DEVTOOLS_OPTION
ARG USERNAME
ARG KVM_GROUP_ID
WORKDIR /f5
COPY . /f5/
# Set disable_coredump false is a sudo alpine bug
RUN apk update && \
    apk add sudo bash && \
    echo "Set disable_coredump false" >> /etc/sudo.conf
RUN bash /f5/setup-build-env $ADD_DEVTOOLS_OPTION
ENV PATH /f5:$PATH
ENV VENV_DIR /f5/.venv
ENV PATH ${VENV_DIR}/bin:$PATH
ENV PYTHONPATH /f5/.venv/bin
ENV LANG=en_US.UTF-8
ENV USER $USERNAME
USER $LINUX_USER_ID:$KVM_GROUP_ID
WORKDIR /mnt
