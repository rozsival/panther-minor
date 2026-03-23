ARG OPENFANG_IMAGE
FROM ${OPENFANG_IMAGE}

ARG OPENFANG_USER
USER ${OPENFANG_USER}

WORKDIR /home/${OPENFANG_USER}
COPY --chown=${OPENFANG_USER} ./entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh

EXPOSE 4200/tcp
ENTRYPOINT ["./entrypoint.sh"]
CMD ["openfang", "start"]
