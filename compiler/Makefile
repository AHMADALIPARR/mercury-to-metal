# SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001
# Copyright (c) 2026 Ahmad Ali Parr. All rights reserved.
# Authored by Ahmad Ali Parr.
# Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE.

# Build the Mercury circuit compiler. Requires mmc on PATH.
#   make -C compiler         build bin/mercury-qc
#   make -C compiler test    build and run tests/compiler/run_tests.sh

MMC ?= mmc
SRC := $(wildcard src/*.m)

.PHONY: all test clean

all: bin/mercury-qc

bin/mercury-qc: $(SRC)
	cd src && $(MMC) --make mercury_qc
	mkdir -p bin
	cp src/mercury_qc bin/mercury-qc

test: all
	sh ../tests/compiler/run_tests.sh bin/mercury-qc

clean:
	rm -rf src/Mercury src/*.int src/*.int2 src/*.int3 src/*.d src/*.c \
	    src/mercury_qc bin
