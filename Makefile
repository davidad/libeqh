# Makefile for libeqh ( https://github.com/davidad/libeqh )
# (c) 2016 David A. Dalrymple & Eliana Lorch
# See LICENSE for your rights to this software and README.md for instructions.

#------------------------------------------------------------------------------
# Variables

# GNU Make will see all files in these directories as if they were top-level.
SHELL := /bin/bash
VPATH = deps
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Default rule
.PHONY: all test bench
all: test bench
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Detect OS.
UNAME := $(shell uname)
ifeq ($(UNAME),Darwin)
    PLATFORM := macos
endif
ifeq ($(UNAME),Linux)
    PLATFORM := linux
endif
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Download fasm.
FASM_DL_VERSION := 1.71.57

ifeq ($(PLATFORM),macos)
    FASM_DL := fasm-macos-$(FASM_DL_VERSION).tgz
endif
ifeq ($(PLATFORM),linux)
    FASM_DL := fasm-linux-$(FASM_DL_VERSION).tgz
    FASM_URL := "https://flatassembler.net/fasm-$(FASM_DL_VERSION).tgz"
    FASM_DL_BIN := fasm/fasm
    FASM_STRIP_COMPONENTS := 1
    FASM_DL_HASH := cd80567beb6ab80bfb795eaba49afb56649e4c25
endif

deps/bin/fasm: deps/$(FASM_DL)
	mkdir -p deps/bin
	cd deps \
        && tar --strip-components=$(FASM_STRIP_COMPONENTS) \
               -xzf $(FASM_DL) $(FASM_DL_BIN)
	mv deps/fasm $@
	touch $@

deps/fasm-linux-$(FASM_DL_VERSION).tgz:
	mkdir -p deps
	curl -L $(FASM_URL) -o $@
	test `git hash-object $@` = $(FASM_DL_HASH)

deps/fasm-macos-$(FASM_DL_VERSION).tgz:
	@echo "Error: fasm is not supported on macOS, although it is possible"\
	" to make it work. Check back later."
	@false 
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Download and compile libsodium.
LIBSODIUM_VERSION := 1.0.11
LIBSODIUM_URL := "https://github.com/jedisct1/libsodium/releases/download/$(LIBSODIUM_VERSION)/libsodium-$(LIBSODIUM_VERSION).tar.gz"
LIBSODIUM_DL := libsodium-$(LIBSODIUM_VERSION).tar.gz
LIBSODIUM_DL_HASH := a20343925557869eac8d3d31d705c5d9ce252611

deps/$(LIBSODIUM_DL):
	mkdir -p deps
	curl -L $(LIBSODIUM_URL) -o $@
	test `git hash-object $@` = $(LIBSODIUM_DL_HASH)

deps/include/sodium.h deps/lib/libsodium.a: deps/$(LIBSODIUM_DL)
	cd deps \
	&& tar -xzf $(LIBSODIUM_DL)
	cd deps/libsodium-$(LIBSODIUM_VERSION) \
	&& ./configure --prefix=`pwd`/../ \
	&& make \
	&& make install
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Get all the above dependencies
.PHONY: deps
deps: deps/bin/fasm deps/include/sodium.h
.INTERMEDIATE: deps/$(LIBSODIUM_DL) deps/$(FASM_DL)
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Generate object files
LDFLAGS := -i
bin/libeqh.o: bin/libeqh_asm.o deps/lib/libsodium.a
	ld $(LDFLAGS) -o $@ $^

bin/libeqh_test.o: bin/libeqh_asm_test.o deps/lib/libsodium.a
	ld $(LDFLAGS) -o $@ $^

bin/%.o: bin/%.$(PLATFORM).o
	ln -f $< $@

bin/%.linux.o bin/%_test.linux.o: libeqh/%.asm libeqh/syscalls.inc deps/bin/fasm 
	mkdir -p bin
	cd libeqh \
	&& ../deps/bin/fasm $(shell [[ $* == *_test* ]] && echo "-d testing=1") \
                   $*.asm ../$@
	rm -f libeqh/syscalls.inc

bin/%.macos.o bin/%_test.macos.o: libeqh/%.asm libeqh/syscalls.inc \
                                  deps/bin/fasm deps/objconv 
	mkdir -p bin
	cd libeqh \
	&& ../deps/bin/fasm $(shell [[ $* == *_test* ]] && echo "-d testing=1") \
                   $*.asm ../$@
	deps/objconv -fmacho -ar:start:_start -nu $*.o $@
	rm -f $*.o
	rm -f libeqh/syscalls.inc

libeqh/syscalls.inc: libeqh/syscalls-$(PLATFORM).inc
	rm -f $@
	ln -s syscalls-$(PLATFORM).inc $@

CFLAGS += -std=c99 -O3
bin/%.o:: libeqh/%.c
	gcc $(CFLAGS) -c $< -o $@
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Generate binaries
CFLAGS += -I. -Ideps/include -Ldeps/lib
bin/libeqh-bench: test/bench.c bin/libeqh.o libeqh.h
	gcc $(CFLAGS) -o $@ bin/libeqh.o $<

bin/libeqh-test: test/test.c bin/libeqh_test.o libeqh.h test/greatest.h
	gcc $(CFLAGS) -DLIBEQH_TEST -o $@ bin/libeqh_test.o $<
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Run binaries
test: bin/libeqh-test
	./$< -v | ./test/greenest
bench: bin/libeqh-bench
	./$<
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Cleaning up.
.PHONY: distclean cleandl cleandeps clean
clean: cleandl
	rm -rf bin libeqh/syscalls.inc

cleandl:
	rm -rf deps/libsodium*/ deps/*.tgz deps/*.tar.gz

cleandeps:
	rm -rf deps

distclean: cleandeps clean
#------------------------------------------------------------------------------

