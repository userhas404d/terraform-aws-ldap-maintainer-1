FROM maximumoverdrive/ci-testing:test

WORKDIR /ci-harness
ENTRYPOINT ["make"]
