---
title:  "Fixing suspend on an iMac 18,1 with Linux"
categories: imac linux
published: true
---

My iMac 18,1 (2017, 21.5") runs CachyOS. Suspend was broken:

- The first wake took over a minute.
- The second suspend rebooted the machine.

The kernel log showed this after the first wake:

```
thunderbolt ... WARNING: drivers/thunderbolt/ctl.c ... tb_cfg_read
xhci_hcd 0000:07:00.0: not ready 65535ms after resume; giving up
```

This post shows how I fixed it. Suspend works every time now, and the USB-C/Thunderbolt ports keep working after wake.

My setup:

- iMac18,1, Apple firmware 529.140.2.0.0
- CachyOS (Arch based), kernel 7.2.9, Limine boot loader, mkinitcpio

The result: 16 suspend/wake cycles in a row without a problem, some of them 15 minutes long. Wake takes about 5 seconds.

What I did not test: a real device in a USB-C port, and Thunderbolt docks. The controller is alive after wake, so I expect them to work.

The steps are for this exact model and firmware. Other Macs have different firmware tables, so the patch in step 2 will not fit them.

## What is wrong

There are two problems.

1. **The reboot.** On a Mac, Linux tells the firmware "I am macOS". The firmware then runs its macOS code for sleep. With Linux, that code hangs on the second suspend, and the machine resets.
2. **The Thunderbolt chip.** If Linux says "I am not macOS", the reboot is gone. But now the firmware handles the Thunderbolt chip the way it does for Windows (Boot Camp). Linux does not play along by default, and the chip is dead after the first sleep. The USB-C ports belong to this chip.

The fix has four parts:

1. Kernel parameter `acpi_osi=!Darwin`. Linux no longer says "I am macOS". This stops the reboot.
2. Kernel parameter `thunderbolt.start_icm=1`. Linux drives the chip the way Windows does.
3. A patched copy of one firmware table. It cuts the chip's power before sleep and restores it on wake.
4. A small sleep hook.

About part 3: the firmware has small programs called ACPI tables. They tell the operating system how to switch hardware on and off. Linux can load a changed copy of a table at boot and use it in place of the original. The firmware in the Mac is not touched, so this is easy to undo.

## Step 1: Kernel parameters

Edit `/etc/default/limine` and add the two parameters to the end of your kernel command line:

```
KERNEL_CMDLINE[default]+="quiet nowatchdog splash rw rootflags=subvol=/@ root=UUID=XXXX acpi_osi=!Darwin thunderbolt.start_icm=1"
```

Your line will look different. Keep what is there and only add the two parameters at the end. If you use another boot loader (GRUB, systemd-boot), add them to its kernel command line.

## Step 2: Patch the firmware table

Install the ACPI tools and copy the firmware tables to a work folder:

```sh
sudo pacman -S acpica
mkdir ~/acpi && cd ~/acpi
sudo cp /sys/firmware/acpi/tables/DSDT DSDT.aml
for t in /sys/firmware/acpi/tables/SSDT*; do sudo cp $t $(basename $t).aml; done
sudo chown $USER: *.aml
```

Find the Thunderbolt table. It is the one named `TbtOnPCH`. On my machine it is `SSDT6`:

```sh
grep -l TbtOnPCH SSDT*.aml
```

Turn it into readable source code. The other tables are needed as a reference:

```sh
mkdir other && mv DSDT.aml SSDT*.aml other/ && mv other/SSDT6.aml .
iasl -e other/*.aml -d SSDT6.aml
```

This creates `SSDT6.dsl`. Now save the following as `thunderbolt.patch`:

```diff
--- SSDT6.dsl
+++ SSDT6.dsl
@@ -18,7 +18,7 @@
  *     Compiler ID      "INTL"
  *     Compiler Version 0x20140424 (538182692)
  */
-DefinitionBlock ("", "SSDT", 2, "APPLE ", "TbtOnPCH", 0x00001000)
+DefinitionBlock ("", "SSDT", 2, "APPLE ", "TbtOnPCH", 0x00001003)
 {
     External (_SB_.GGDV, MethodObj)    // 1 Arguments
     External (_SB_.GGII, MethodObj)    // 1 Arguments
@@ -64,8 +64,6 @@
                     }
                     Else
                     {
-                        \_SB.SGOV (0x02060000, Zero)
-                        \_SB.SGDO (0x02060000)
                     }

                     If (\_SB.PCI0.RP05.UPMB)
@@ -195,6 +193,8 @@
             RPTL,   1,
                 ,   21,
             RPLT,   1,
+                ,   1,
+            RPLA,   1,
             Offset (0x54)
         }

@@ -376,13 +376,21 @@

         Method (ICMB, 0, NotSerialized)
         {
+            /* Linux fix K1: UPSB._PS3 releases TB force power for S3; re-assert it here (_WAK and _INI call ICMB)
+               and wait up to 3 s for the RP05 data link to be active before ICMS restarts the ICM. */
+            \_SB.SGDI (0x02060000)
+            Local0 = 0x012C
+            While (((Local0 != Zero) && (RPLA == Zero)))
+            {
+                Sleep (0x0A)
+                Local0--
+            }
+
             If ((BICM == One))
             {
                 If ((\_SB.PCI0.LPCB.RTC.ISWI != One))
                 {
                     ICMS ()
-                    SGOV (0x02060001, Zero)
-                    SGDO (0x02060001)
                 }
                 Else
                 {
@@ -423,8 +431,6 @@
                                     Sleep (0x03E8)
                                 }

-                                \_SB.SGOV (0x02060000, Zero)
-                                \_SB.SGDO (0x02060000)
                             }
                         }
                     }
@@ -1351,7 +1357,11 @@
                     {
                     }

-                    \_SB.PCI0.RP05.TBTC (0x05)
+                    \_SB.PCI0.RP05.TBTC (0x07)
+                    /* Linux fix K1: unpower the chip for S3 after GO2SX_NO_WAKE (a powered ICM wakes the SMC 2-3 s
+                       after S3 entry). The firmware's S3 resume and ICMB re-assert force power at wake. */
+                    \_SB.SGOV (0x02060000, Zero)
+                    \_SB.SGDO (0x02060000)
                 }
             }

```

What the patch does:

- The firmware no longer switches the chip's power off after boot (three places).
- Before sleep it sends "sleep, no wake" to the chip and then cuts its power.
- On wake it powers the chip on again and waits for the link.
- The version number goes up, so Linux prefers this table over the original.

Apply it, compile it, install it:

```sh
patch -l SSDT6.dsl < thunderbolt.patch
iasl SSDT6.dsl
sudo mkdir -p /etc/initcpio/acpi_override
sudo cp SSDT6.aml /etc/initcpio/acpi_override/
```

If `patch` reports an error, your firmware is different from mine. Stop here. Do not apply the changes by hand unless you can read the table source.

## Step 3: Load the table at boot

The table must be inside the initramfs, the small file system the kernel loads first. This mkinitcpio hook puts it there. Create `/etc/initcpio/install/apple_tb_acpi_override`:

```bash
#!/usr/bin/env bash
build() {
    local aml
    for aml in /etc/initcpio/acpi_override/*.aml; do
        [[ -f "$aml" ]] && add_file_early "$aml" '/kernel/firmware/acpi/'
    done
    return 0
}
help() {
    echo "Adds /etc/initcpio/acpi_override/*.aml to the early initramfs (ACPI table upgrade)."
}
```

Add `apple_tb_acpi_override` to the end of the `HOOKS` line in `/etc/mkinitcpio.conf`. Mine looks like this now:

```
HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems apple_tb_acpi_override)
```

## Step 4: Sleep hook

When the chip loses power, the port it is connected to (`00:1c.4`) sees that as an event and wakes the machine at once. This hook switches that wake source off during sleep. Create `/usr/lib/systemd/system-sleep/10-apple-thunderbolt.sh`:

```sh
#!/bin/sh
WK=/sys/bus/pci/devices/0000:00:1c.4/power/wakeup
case "$1" in
  pre)  echo disabled > "$WK" ;;
  post) echo enabled  > "$WK" ;;
esac
exit 0
```

```sh
sudo chmod +x /usr/lib/systemd/system-sleep/10-apple-thunderbolt.sh
```

## Step 5: Rebuild and reboot

`limine-update` rebuilds the initramfs and the boot menu entry. With another boot loader, run `sudo mkinitcpio -P` and update its config.

```sh
sudo limine-update
sudo reboot
```

## Check

After the reboot:

```sh
cat /proc/cmdline                 # must show both parameters
sudo dmesg | grep TbtOnPCH        # must show "Table Upgrade" and 00001003
lspci | grep -i thunderbolt       # 7 devices
```

Now suspend and wake two times with `systemctl suspend`. After each wake, `lspci | grep -i thunderbolt` must still show 7 devices.

## Good to know

- Suspend with the desktop menu or `systemctl suspend`. Tools that write to `/sys/power/state` directly (like `rtcwake -m mem`) skip the sleep hook.
- A device in a USB-C/Thunderbolt port cannot wake the machine, because the chip has no power during sleep. The keyboard can wake it.
- There is a new ACPI error about `RP05.ICMB` in the kernel log at boot. It is harmless.
- After an Apple firmware update, the patch may no longer fit. Then repeat step 2.

## Undo

Remove the two kernel parameters, remove the hook from `HOOKS`, delete the three new files, then run `sudo limine-update` and reboot.
