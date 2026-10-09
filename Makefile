# IgniOS build. Run inside `nix develop`, which provides the toolchain and
# exports LIMINE_DIR, OVMF_CODE and OVMF_VARS.
#
# Build pipeline (see concept doc 02):
#
#   kernel/src/**/*.ign --ignis build--> build/ignis/user/obj/kernel.o  (one C unit, compiled by clang)
#   kernel/src/**/*.S   --clang -c-----> build/asm/**/*.o
#   kernel.o + asm .o   --ld.lld -T kernel/linker.ld--> build/kernel.elf
#   user/hello          --ignis build--> hello.o --ld.lld -T user/user.ld--> build/hello.elf
#   kernel.elf + hello.elf + Limine + boot/limine.conf --mtools--> build/ignios.img (FAT32 ESP)
#
# Common targets: `make run` (window), `make run-headless` (serial log check),
# `make keytest` (types keys and checks the echo), `make clean`.

# The Ignis compiler. Override with `make IGNIS=/path/to/ignis`.
IGNIS ?= ignis
LD := ld.lld
QEMU := qemu-system-x86_64

# Output directory for everything generated.
BUILD := build
KERNEL := $(BUILD)/kernel.elf
IMAGE := $(BUILD)/ignios.img
ESP := $(BUILD)/esp
SERIAL_LOG := $(BUILD)/serial.log
OVMF_VARS_COPY := $(BUILD)/ovmf-vars.fd
SCREEN_PPM := $(BUILD)/screen.ppm
SCREEN_PNG := $(BUILD)/screen.png
HEADLESS_SECONDS ?= 15

# Every kernel source file. Listing them makes `make` rebuild when any changes.
IGNIS_SOURCES := $(sort $(shell find kernel/src -name '*.ign'))
IGNIS_OBJECT := $(BUILD)/ignis/user/obj/kernel.o

# The user program and the files its build depends on.
HELLO := $(BUILD)/hello.elf
HELLO_OBJECT := $(BUILD)/user/hello/user/obj/hello.o
HELLO_SOURCES := $(shell find user/hello user/lib -name '*.ign' -o -name '*.toml')

# Assembles the `.S` files. `ASFLAGS` use the kernel code model so symbol
# addresses match what the Ignis-generated C expects.
CLANG ?= clang
ASM_SOURCES := $(sort $(shell find kernel/src -name '*.S'))
ASM_OBJECTS := $(patsubst kernel/src/%.S,$(BUILD)/asm/%.o,$(ASM_SOURCES))
ASFLAGS := --target=x86_64-unknown-none -mcmodel=kernel -fno-pic -fno-pie -c

# Kernel link flags. `max-page-size=0x1000` makes `CONSTANT(MAXPAGESIZE)` in the
# linker script 4 KiB, so the segment boundaries are page aligned.
# `--build-id=none` leaves out the build-id note and `-z noexecstack` marks the
# stack non-executable.
LDFLAGS := -m elf_x86_64 -nostdlib -static --no-dynamic-linker \
	-z max-page-size=0x1000 -z noexecstack --build-id=none -T kernel/linker.ld

# q35 machine, KVM when available and software emulation otherwise, the `max`
# CPU model (every feature the host or the emulator has, SMEP and SMAP among
# them; the default qemu64 model has neither), 256 MiB of RAM, and QEMU exits
# instead of resetting the machine (a triple fault ends the run instead of
# rebooting in a loop).
# OVMF is attached as two pflash drives (firmware code read-only, variables
# writable) and the boot image as a raw disk.
QEMU_FLAGS := -machine q35,accel=kvm:tcg -cpu max -m 256M -no-reboot \
	-drive if=pflash,unit=0,format=raw,readonly=on,file=$(OVMF_CODE) \
	-drive if=pflash,unit=1,format=raw,file=$(OVMF_VARS_COPY) \
	-drive format=raw,file=$(IMAGE)

# User program link flags, the same as the kernel's with `user/user.ld`.
USER_LDFLAGS := -m elf_x86_64 -nostdlib -static --no-dynamic-linker \
	-z max-page-size=0x1000 -z noexecstack --build-id=none -T user/user.ld

# Targets that name an action, not a file. `make` with no target builds
# `all`, the boot image.
.PHONY: all kernel user esp image run run-headless screenshot keytest font clean

all: image

kernel: $(KERNEL)

# One Ignis invocation compiles the whole kernel to C and then to an object.
$(IGNIS_OBJECT): $(IGNIS_SOURCES) ignis.toml
	$(IGNIS) build

user: $(HELLO)

# The user program is its own Ignis project under user/hello.
$(HELLO_OBJECT): $(HELLO_SOURCES)
	cd user/hello && $(IGNIS) build

$(HELLO): $(HELLO_OBJECT) user/user.ld
	$(LD) $(USER_LDFLAGS) -o $@ $(HELLO_OBJECT)

# Assembles one `.S` file.
$(BUILD)/asm/%.o: kernel/src/%.S
	@mkdir -p $(dir $@)
	$(CLANG) $(ASFLAGS) -o $@ $<

# Links the Ignis object and the assembly objects with the kernel linker
# script.
$(KERNEL): $(IGNIS_OBJECT) $(ASM_OBJECTS) kernel/linker.ld
	$(LD) $(LDFLAGS) -o $@ $(IGNIS_OBJECT) $(ASM_OBJECTS)

# Lays out the EFI System Partition tree: the Limine EFI binary at the removable
# media path firmware boots from, Limine's configuration, the kernel and the
# user program.
esp: $(KERNEL) $(HELLO) boot/limine.conf
	@test -n "$(LIMINE_DIR)" || { echo "LIMINE_DIR is not set; run inside nix develop" >&2; exit 1; }
	rm -rf $(ESP)
	mkdir -p $(ESP)/EFI/BOOT
	cp $(LIMINE_DIR)/BOOTX64.EFI $(ESP)/EFI/BOOT/BOOTX64.EFI
	cp boot/limine.conf $(ESP)/EFI/BOOT/limine.conf
	cp $(KERNEL) $(ESP)/kernel.elf
	cp $(HELLO) $(ESP)/hello.elf

image: $(IMAGE)

# Writes the 64 MiB FAT32 image with `mformat` and `mcopy`, without needing
# root or a loop device.
$(IMAGE): esp
	rm -f $@
	truncate -s 64M $@
	mformat -i $@ -F -v IGNIOS ::
	mcopy -i $@ -s $(ESP)/EFI ::/
	mcopy -i $@ $(ESP)/kernel.elf ::/kernel.elf
	mcopy -i $@ $(ESP)/hello.elf ::/hello.elf

# A private copy of the firmware variable store, so firmware writes never touch
# the read-only Nix store file.
$(OVMF_VARS_COPY):
	@test -n "$(OVMF_VARS)" || { echo "OVMF_VARS is not set; run inside nix develop" >&2; exit 1; }
	@mkdir -p $(BUILD)
	install -m 644 $(OVMF_VARS) $@

# Opens a QEMU window. The serial port is connected to the terminal.
run: $(IMAGE) $(OVMF_VARS_COPY)
	$(QEMU) $(QEMU_FLAGS) -serial stdio

# Boots without a display for HEADLESS_SECONDS, then checks the serial log.
# The kernel halts instead of exiting, so the timeout is the normal end.
run-headless: $(IMAGE) $(OVMF_VARS_COPY)
	rm -f $(SERIAL_LOG)
	timeout $(HEADLESS_SECONDS) $(QEMU) $(QEMU_FLAGS) -display none \
		-serial file:$(SERIAL_LOG) || test $$? -eq 124
	cat $(SERIAL_LOG)
	grep -q 'IgniOS booting' $(SERIAL_LOG)
	grep -q '^ IgniOS ' $(SERIAL_LOG)
	grep -q '^> ' $(SERIAL_LOG)

# Boots without a display until the console prompt appears on COM1, then
# saves the framebuffer to build/screen.ppm and build/screen.png.
screenshot: $(IMAGE) $(OVMF_VARS_COPY)
	scripts/screenshot.sh $(SERIAL_LOG) $(SCREEN_PPM) $(HEADLESS_SECONDS) -- \
		$(QEMU) $(QEMU_FLAGS) -display none -serial file:$(SERIAL_LOG)
	pnmtopng $(SCREEN_PPM) > $(SCREEN_PNG)
	@echo "wrote $(SCREEN_PNG)"

# Boots headless, types a key sequence through the QEMU monitor once the
# prompt appears, checks the echo in the serial log and saves the screen to
# build/screen.png.
keytest: $(IMAGE) $(OVMF_VARS_COPY)
	scripts/keytest.sh $(SERIAL_LOG) $(SCREEN_PPM) $(HEADLESS_SECONDS) -- \
		$(QEMU) $(QEMU_FLAGS) -display none -serial file:$(SERIAL_LOG)
	pnmtopng $(SCREEN_PPM) > $(SCREEN_PNG)
	@echo "wrote $(SCREEN_PNG)"

# Regenerates the committed console font from the Spleen BDF in the devShell.
font:
	@test -n "$(SPLEEN_DIR)" || { echo "SPLEEN_DIR is not set; run inside nix develop" >&2; exit 1; }
	python3 scripts/gen-font.py $(SPLEEN_DIR)/spleen-8x16.bdf kernel/src/drivers/font_8x16.ign

clean:
	rm -rf $(BUILD)
