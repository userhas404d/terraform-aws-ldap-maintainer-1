SHELL := /bin/bash

# -include $(shell curl -sSL -o .tardigrade-ci "https://raw.githubusercontent.com/plus3it/tardigrade-ci/master/bootstrap/Makefile.bootstrap"; echo .tardigrade-ci)
-include $(shell curl -sSL -o .tardigrade-ci "https://raw.githubusercontent.com/userhas404d/tardigrade-ci/project-root-fix/bootstrap/Makefile.bootstrap"; echo .tardigrade-ci)
