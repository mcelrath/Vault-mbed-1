
.DEFAULT_GOAL := default
# Source files
PROTOFILES = messages-common.proto messages-bitcoin.proto messages-management.proto messages.proto
SOURCES = deletedlib.cpp deletedlib.h msg_handler.cpp msg_handler.h helpers.cpp helpers.h fs_handler.cpp fs_handler.h interface.h interface.cpp hardware.h main.cpp

# Dependencies
MBED_DEPS = f469_lvgl_driver BSP_DISCO_F469NI lvgl-mbed mbed-os QSPI_DISCO_F469NI tiny_lvgl_gui uBitcoin
GIT_SUBMODULES = nanopb
NANOPB_SOURCES = pb.h pb_common.c pb_common.h pb_decode.c pb_decode.h pb_encode.c pb_encode.h

# Source files
PROTOFILES = messages-common.proto messages-bitcoin.proto messages-management.proto messages.proto

# Munge some paths
MBED_DEPS_DOTLIBFILES = $(addsuffix .lib, $(MBED_DEPS))
PROTOBUF_BASENAMES = $(basename $(PROTOFILES))
PROTOBUF_TARGET_SOURCEFILES = $(addprefix src/protobuf/, $(addsuffix .pb.c, $(basename $(PROTOFILES))) $(addsuffix .pb.h, $(basename $(PROTOFILES))))
GIT_SUBMODULE_DEPS = $(addsuffix /.git, $(GIT_SUBMODULES))
NANOPB_DEPS = $(addprefix src/nanopb/, $(NANOPB_SOURCES))
SOURCES_DEPS = $(addprefix src/, $(SOURCES))

# The file that make should build, in the end
TARGET = BUILD/DISCO_F469NI/GCC_ARM/Vault-mbed.bin

# Try to discover the device (linux only) for `make install`, using sudo
SUDOCMD = sudo
# Commands to mount as a user
#DEVICE = $(shell dmesg | grep -A 20 "STM32 STLink" | sed '/^--$$/q' | sed -z "s/^.*\[\(sd[a-z]\)\].*/\/dev\/\1/")
HAVEDEVICE = $(shell lsblk -o PATH,LABEL | grep DIS_F469NI)
DEVICE = $(shell lsblk -o PATH,LABEL | grep DIS_F469NI | awk '{print $$1}')
MOUNTCMD = gio mount -d
UMOUNTCMD = gio mount -u
MOUNTPOINT = /mnt # filled in by the output of `gio mount` if not using sudo, usually under /media/<username>/DIS_F469NI

virtualenv:
	virtualenv -p python3 virtualenv
	. virtualenv/bin/activate; pip install -Ur requirements.txt

deps: $(MBED_DEPS) $(PROTOBUF_TARGET_SOURCEFILES)

default: $(GIT_SUBMODULE_DEPS) $(MBED_DEPS) $(TARGET)

$(GIT_SUBMODULE_DEPS) $(NANOPB_DEPS): .gitmodules
	git submodule init
	git submodule update
	cd src/nanopb; ln -s $(addprefix ../../nanopb/, $(NANOPB_SOURCES)) .

$(TARGET): $(MBED_DEPS) $(PROTOBUF_TARGET_SOURCEFILES) $(NANOPB_DEPS) $(SOURCES_DEPS)
	mbed compile

# The pipe symbol here causes this recipe to be executed exactly ONCE
# If you have to update dependencies, run a 'make clean'
$(MBED_DEPS): | $(MBED_DEPS_DOTLIBFILES)
	mbed deploy
	sed '/#--Makefile autogenerated--/q' .gitignore > .gitignore.new
	ls -d $(MBED_DEPS) >> .gitignore.new
	mv .gitignore.new .gitignore

src/protobuf/%.pb.h src/protobuf/%.pb.c: src/%.proto virtualenv $(GIT_SUBMODULE_DEPS)
	. virtualenv/bin/activate; \
	cd src; protoc --plugin=protoc-gen-nanopb=../nanopb/generator/protoc-gen-nanopb --nanopb_out=protobuf $(notdir $<)

clean:
	rm -rf $(MBED_DEPS) $(PROTOBUF_TARGET_SOURCEFILES) $(GIT_SUBMODULES)/* $(GIT_SUBMODULES)/.[a-z0-9]* __pycache__ BUILD virtualenv *.pyc src/nanopb/*

test: $(NANOPB_DEPS)
	echo $(GIT_SUBMODULE_DEPS)

install: $(TARGET) $(DEVICE)
	$(eval MOUNTPOINT=$(shell $(MOUNTCMD) $(DEVICE) | sed 's/Mounted \(.*\) at \(.*\)/\2/'))
	@echo Mounting $(DEVICE) on $(MOUNTPOINT) and copying firmware...
	@cp $(TARGET) $(MOUNTPOINT)
	@sync $(MOUNTPOINT)
	@$(UMOUNTCMD) $(MOUNTPOINT)
	@echo ...done

sudoinstall: $(TARGET) $(SUDODEVICE)
ifneq ("$(wildcard $(DEVICE) )", "")
	@echo Mounting $(DEVICE) on $(MOUNTPOINT) and copying firmware...
	@$(SUDOCMD) mount $(DEVICE) $(MOUNTPOINT)
	@$(SUDOCMD) cp $(TARGET) $(MOUNTPOINT)
	@$(SUDOCMD) sync $(MOUNTPOINT)
	@$(SUDOCMD) umount $(DEVICE)
	@echo ...done
else
	@echo Unable to find STM32 ST-LINK device connected via USB. Make sure the device is
	@echo connected and the STLK jumper is shorted.  Output of \`lsusb\` follows:
	@echo ---------
	@lsusb
endif
