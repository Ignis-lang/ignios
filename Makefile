# IgniOS build. Run inside `nix develop`, which provides the toolchain and
# exports LIMINE_DIR, OVMF_CODE and OVMF_VARS.

IGNIS ?= ../ignisc.rs/build/bootstrap/stage1/ignis
LD := ld.lld
QEMU := qemu-system-x86_64

BUILD := build
KERNEL := $(BUILD)/kernel.elf
IMAGE := $(BUILD)/ignios.img
ESP := $(BUILD)/esp
SERIAL_LOG := $(BUILD)/serial.log
OVMF_VARS_COPY := $(BUILD)/ovmf-vars.fd
SCREEN_PPM := $(BUILD)/screen.ppm
SCREEN_PNG := $(BUILD)/screen.png
HEADLESS_SECONDS ?= 15

IGNIS_SOURCES := $(shell find kernel/src -name '*.ign')
IGNIS_OBJECT := $(BUILD)/ignis/user/obj/kernel.o

CLANG ?= clang
ASM_SOURCES := $(shell find kernel/src -name '*.S')
ASM_OBJECTS := $(patsubst kernel/src/%.S,$(BUILD)/asm/%.o,$(ASM_SOURCES))
ASFLAGS := --target=x86_64-unknown-none -mcmodel=kernel -fno-pic -fno-pie -c

LDFLAGS := -m elf_x86_64 -nostdlib -static --no-dynamic-linker \
	-z max-page-size=0x1000 -z noexecstack --build-id=none -T kernel/linker.ld

QEMU_FLAGS := -machine q35,accel=kvm:tcg -m 256M -no-reboot \
	-drive if=pflash,unit=0,format=raw,readonly=on,file=$(OVMF_CODE) \
	-drive if=pflash,unit=1,format=raw,file=$(OVMF_VARS_COPY) \
	-drive format=raw,file=$(IMAGE)

.PHONY: all kernel esp image run run-headless screenshot keytest font clean

all: image

kernel: $(KERNEL)

$(IGNIS_OBJECT): $(IGNIS_SOURCES) ignis.toml
	$(IGNIS) build

$(BUILD)/asm/%.o: kernel/src/%.S
	@mkdir -p $(dir $@)
	$(CLANG) $(ASFLAGS) -o $@ $<

$(KERNEL): $(IGNIS_OBJECT) $(ASM_OBJECTS) kernel/linker.ld
	$(LD) $(LDFLAGS) -o $@ $(IGNIS_OBJECT) $(ASM_OBJECTS)

esp: $(KERNEL) boot/limine.conf
	@test -n "$(LIMINE_DIR)" || { echo "LIMINE_DIR is not set; run inside nix develop" >&2; exit 1; }
	rm -rf $(ESP)
	mkdir -p $(ESP)/EFI/BOOT
	cp $(LIMINE_DIR)/BOOTX64.EFI $(ESP)/EFI/BOOT/BOOTX64.EFI
	cp boot/limine.conf $(ESP)/EFI/BOOT/limine.conf
	cp $(KERNEL) $(ESP)/kernel.elf

image: $(IMAGE)

$(IMAGE): esp
	rm -f $@
	truncate -s 64M $@
	mformat -i $@ -F -v IGNIOS ::
	mcopy -i $@ -s $(ESP)/EFI ::/
	mcopy -i $@ $(ESP)/kernel.elf ::/kernel.elf

$(OVMF_VARS_COPY):
	@test -n "$(OVMF_VARS)" || { echo "OVMF_VARS is not set; run inside nix develop" >&2; exit 1; }
	@mkdir -p $(BUILD)
	install -m 644 $(OVMF_VARS) $@

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
	python3 scripts/gen-font.py $(SPLEEN_DIR)/spleen-8x16.bdf kernel/src/font_8x16.ign

clean:
	rm -rf $(BUILD)
