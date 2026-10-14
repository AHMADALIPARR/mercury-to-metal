# Repository entry points. Each target is a real build or test; nothing here
# claims hardware execution.
#
#   make compiler        build the Mercury circuit compiler (bin/mercury-qc)
#   make test-compiler   compiler regression and semantic tests
#   make test-algebra    braid algebra tests (Mercury)
#   make test            all of the above

.PHONY: compiler test-compiler test-algebra test clean

compiler:
	$(MAKE) -C compiler all

test-compiler: compiler
	sh tests/compiler/run_tests.sh compiler/bin/mercury-qc

test-algebra:
	$(MAKE) -C tests/algebraic test

test: test-compiler test-algebra

clean:
	$(MAKE) -C compiler clean
	$(MAKE) -C tests/algebraic clean
