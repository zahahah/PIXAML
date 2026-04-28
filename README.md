# PIXAML

**Project Status: Unmaintained** *Due to a lack of free time, I have decided to stop the development of this module. Feel free to fork the repository and continue this work.*

## Overview

PIXAML is an audio modification module designed specifically for the **Google Pixel 8 and newer devices** in the Pixel family. 

In these newer devices, the sound effect architecture has been migrated from HIDL to AIDL. 
This migration removed the `audio_effects_config.xml` file, so audio effects like JamesDSP, Viper4Android, etc. cannot patch it. 

## How It Works

To bypass this limitation, PIXAML performs the following operations:
1. **Patches `libaudiohal@aidl.so`**: It modifies `/system/lib64/libaudiohal@aidl.so` to utilize an additional service (`vendor.aml.effect-service`).
2. **Restores Configuration**: It adds the missing `audio_effects_config.xml` file back into `/vendor/etc`.

The binary modification is handled by `patchelf`, a tool specifically designed for this type of operation. 

*Note: The source code for the service binary used in this project can be found here: [vendor_aml_effects by anonymix007](https://github.com/anonymix007/vendor_aml_effects).*

## ⚠️ WARNING: Bootloop Risk & Troubleshooting

***!!! THERE IS A RISK OF A BOOTLOOP !!!*** *Always be prepared for a bootloop just in case. Have a recovery method ready before flashing.*

**Known Conflicts:**
Some Magisk/KernelSU modules can conflict with PIXAML, even if they seemingly have nothing in common (e.g., *PixelXpert*). 

**Troubleshooting Steps if Your Device Doesn't Boot:**
1. Disable **all** modules (including non-audio ones).
2. Enable **only PIXAML** and reboot to check if the system boots successfully.
3. If it boots, begin enabling your other modules one by one. 
*(For unknown reasons, establishing PIXAML as the first enabled module often resolves conflicts).*
