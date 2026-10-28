#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/wow-launcher
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/CASC.m launcher/WoW/Client.m tests/test_wow_manifest.m \
    -o build/wow-launcher/test_wow_manifest
build/wow-launcher/test_wow_manifest
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/CASC.m launcher/WoW/Client.m tests/test_wow_client.m \
    -o build/wow-launcher/test_wow_client
build/wow-launcher/test_wow_client
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/Installation.m tests/test_wow_installation.m \
    -o build/wow-launcher/test_wow_installation
build/wow-launcher/test_wow_installation
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/CASC.m launcher/WoW/Client.m launcher/WoW/Updater.m tests/test_wow_update.m \
    -o build/wow-launcher/test_wow_update
build/wow-launcher/test_wow_update
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/CASC.m tests/test_wow_verification.m \
    -o build/wow-launcher/test_wow_verification
build/wow-launcher/test_wow_verification
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/AddonManager.m tests/test_wow_addon_manager.m \
    -o build/wow-launcher/test_wow_addon_manager
build/wow-launcher/test_wow_addon_manager
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz \
    launcher/WoW/BackupManager.m tests/test_wow_backup_manager.m \
    -o build/wow-launcher/test_wow_backup_manager
build/wow-launcher/test_wow_backup_manager
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O2 -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/CASC.m launcher/WoW/Client.m tools/wow_cdn.m \
    -o build/wow-launcher/wow_cdn
