# SPDX-License-Identifier: LicenseRef-Sovereign-Leviathan-SL-AGPL3-001
# Copyright (c) 2026 Ahmad Ali Parr. All rights reserved.
# Authored by Ahmad Ali Parr.
# Licensed under the SNAPKITTY OPAQUE SOURCE LICENSE v1.0. See LICENSE.

# Algebraic tests for topology/braid. Requires mmc on PATH.
#
# mmc --make only finds sources in the current directory, so the module under
# test is staged into build/ before compiling. Sources stay where they are
# owned; build/ is generated.

MMC ?= mmc
BRAID := ../../topology/braid/braid.m

.PHONY: test clean

test: build/test_braid
	./build/test_braid

build/test_braid: build/braid.m build/test_braid.m
	cd build && $(MMC) --make test_braid

build/braid.m: $(BRAID)
	mkdir -p build
	cp $(BRAID) $@

build/test_braid.m: test_braid.m
	mkdir -p build
	cp test_braid.m $@

clean:
	rm -rf build
