# Mice identity

AppIcon.png is the selected 1024×1024 RGBA artwork: hand-printed cobalt running mouse on an ivory base, optically shifted right. Source and earlier design iterations are kept locally under Resources/AppIcon/Mouse-print-v4; only the selected production artwork is published. The build exports this PNG to ICNS via scripts/GenerateIcon.swift.

The menu-bar version is a simplified vector template in Sources/Shared/Views/StatusIcon.swift. It keeps the running pose, single large ear, eye and curled tail; texture is omitted for legibility at 18pt. The canvas uses standard system cursors.
