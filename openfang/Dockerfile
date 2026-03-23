ARG OPENFANG_IMAGE
FROM ${OPENFANG_IMAGE}

ARG OPENFANG_USER
USER ${OPENFANG_USER}

WORKDIR /home/${OPENFANG_USER}
COPY --chown=${OPENFANG_USER} ./entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
