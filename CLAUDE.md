# SPACBR — PROJECT ARCHITECTURE, DEVELOPMENT AND DESIGN SPECIFICATION

You are working on SPACBR.

SPACBR is a personal, opinionated desktop system built specifically on
Arch Linux.

You must treat this project as a real software/system engineering
project, not as a dotfiles collection or a Linux "rice".

You must think simultaneously as:

- Linux system architect
- Arch Linux engineer
- X11 engineer
- Suckless developer
- Unix software engineer
- Shell developer
- DevOps/release engineer
- Security engineer
- UX designer
- UI designer
- Product architect

The goal is to create a complete, cohesive, lightweight, highly
functional personal computing environment that feels like one system.

The system should be minimal, calm, fast, functional, maintainable,
reproducible and distinctly personal.

It should never feel like a collection of unrelated configuration
files.

=======================================================================
1. PROJECT IDENTITY
=======================================================================

Project name:

    SPACBR

SPACBR is an opinionated personal desktop environment built on top of
Arch Linux.

The underlying operating system remains Arch Linux.

SPACBR is NOT a Linux distribution.

SPACBR is NOT a desktop environment.

SPACBR is NOT a Wayland compositor.

SPACBR is NOT a clone of Omarchy.

SPACBR is NOT a generic rice.

SPACBR is an integration layer that combines:

    Arch Linux
    X11
    dwm
    dmenu
    st
    dwmblocks
    slock
    lightweight Linux utilities
    carefully designed scripts
    unified configuration
    coherent visual design
    reproducible installation
    system management tools


=======================================================================
2. PLATFORM CONTRACT
=======================================================================

SPACBR officially targets:

    Arch Linux
    x86_64
    Xorg
    X11
    dwm

The graphical architecture is explicitly X11.

Do not redesign the project around:

    Wayland
    Hyprland
    Sway
    GNOME
    KDE
    XFCE
    Cinnamon

Individual applications may support Wayland internally, but that does
not change the SPACBR platform architecture.

The window manager must remain:

    dwm


=======================================================================
3. CORE PHILOSOPHY
=======================================================================

SPACBR follows:

    SIMPLE AT THE SURFACE
    POWERFUL UNDERNEATH

The system should look extremely simple while providing substantial
functionality underneath.

Permanent UI should contain only information that is genuinely useful.

Advanced functionality should be contextual.

Prefer:

    keyboard shortcut
        ↓
    dmenu
        ↓
    action

over:

    permanent widget
    permanent panel
    permanent GUI

The desktop should feel quiet and uncluttered.


=======================================================================
4. DESIGN PHILOSOPHY
=======================================================================

SPACBR should feel:

    minimal
    calm
    mature
    technical
    personal
    timeless
    coherent
    functional

Avoid:

    neon colors
    excessive gradients
    excessive transparency
    excessive blur
    unnecessary animation
    giant widgets
    decorative panels
    excessive icons
    excessive system information
    visual clutter
    "AI-generated" looking interfaces
    flashy effects

Aesthetic quality must come from:

    typography
    spacing
    hierarchy
    consistency
    restrained color
    subtle details

Not from visual effects.


=======================================================================
5. WHAT SPACBR MUST NOT BECOME
=======================================================================

Never allow SPACBR to become:

    - a package dumping ground
    - a collection of random AUR packages
    - a widget showcase
    - a theme showcase
    - a desktop environment clone
    - an Omarchy clone
    - a Hyprland configuration
    - a Wayland system
    - a giant shell framework
    - a collection of unnecessary daemons
    - an over-engineered framework
    - a generic Linux configuration

Every feature must have a reason to exist.


=======================================================================
6. ARCHITECTURE
=======================================================================

SPACBR consists of several layers:

    SPACBR
       │
       ├── Configuration
       │
       ├── Scripts
       │
       ├── Suckless components
       │
       ├── Desktop integration
       │
       ├── Package definitions
       │
       ├── Installer
       │
       ├── CLI
       │
       └── Documentation
              │
              ▼
           Arch Linux
              │
              ▼
             X11
              │
              ▼
             dwm
              │
              ▼
           Hardware


SPACBR should integrate existing Linux infrastructure rather than
reimplementing it.


=======================================================================
7. RESPONSIBILITY MODEL
=======================================================================

Each responsibility must have one primary owner.

Window management:

    dwm

Application launcher:

    dmenu

Terminal:

    st

Status bar:

    dwmblocks

Notifications:

    dunst

Compositor:

    picom

Networking:

    NetworkManager

Networking control:

    nmcli

Audio:

    PipeWire
    WirePlumber

Audio control:

    wpctl / appropriate PipeWire utilities

Bluetooth:

    BlueZ

Bluetooth control:

    bluetoothctl

Media control:

    playerctl

Brightness:

    brightnessctl

Display:

    xrandr

Locking:

    slock

Power/session:

    systemd
    loginctl

Filesystem:

    PCManFM

Documents:

    Zathura

Media:

    mpv

Editor:

    Neovim / Vim

Shell:

    zsh

Do not introduce alternative tools unless there is a clear architectural
reason.


=======================================================================
8. EXISTING REPOSITORY
=======================================================================

The existing SPACBR repository currently contains:

    .config/
    .local/
    .vimrc
    .zshrc

The .config directory currently contains:

    alacritty/
    dunst/
    firefox/
    gtk-2.0/
    gtk-3.0/
    gtk-4.0/
    htop/
    libfm/
    mpv/
    nvim/
    pcmanfm/
    picom/
    shell/
    vim/
    xinitrc
    xresources
    zathura/

The .local directory currently contains:

    bin/
    share/
    src/

The .local/bin directory currently contains scripts such as:

    net
    passmenu
    screenshot

The .local/share directory currently contains:

    backgrounds/
    gnupg/

The .local/src directory contains:

    blocks/
    dmenu/
    dwm/
    slock/
    st/

These existing files and configurations are the starting point.

DO NOT blindly replace them.

Inspect them first.

Preserve useful personal modifications.

Refactor only when there is a clear architectural reason.


=======================================================================
9. XDG STANDARD
=======================================================================

SPACBR must follow XDG conventions wherever practical.

Use:

    ~/.config/
        configuration

    ~/.local/bin/
        user executables

    ~/.local/share/
        user data

    ~/.local/state/
        persistent runtime/state data

    ~/.local/src/
        source code

    ~/.cache/
        disposable cache

Conventional home files may remain where appropriate:

    ~/.zshrc
    ~/.vimrc

Do not invent unnecessary directory structures.


=======================================================================
10. REPOSITORY STRUCTURE
=======================================================================

Evolve the repository toward a clear structure similar to:

    spacbr/
    │
    ├── CLAUDE.md
    ├── README.md
    ├── VERSION
    ├── LICENSE
    ├── .gitignore
    │
    ├── .config/
    │   ├── dunst/
    │   ├── gtk-2.0/
    │   ├── gtk-3.0/
    │   ├── gtk-4.0/
    │   ├── mpv/
    │   ├── nvim/
    │   ├── pcmanfm/
    │   ├── picom/
    │   ├── shell/
    │   ├── vim/
    │   ├── zathura/
    │   └── ...
    │
    ├── .local/
    │   ├── bin/
    │   ├── share/
    │   ├── state/
    │   └── src/
    │       ├── dwm/
    │       ├── dmenu/
    │       ├── st/
    │       ├── dwmblocks/
    │       └── slock/
    │
    ├── packages/
    │   ├── base
    │   ├── x11
    │   ├── desktop
    │   ├── hardware
    │   └── aur
    │
    ├── install/
    │   ├── bootstrap.sh
    │   ├── install.sh
    │   ├── update.sh
    │   ├── repair.sh
    │   ├── uninstall.sh
    │   ├── doctor.sh
    │   └── functions/
    │
    ├── system/
    │   ├── services/
    │   └── x11/
    │
    └── docs/

Do not force an immediate migration if it risks breaking working
configuration.

Migrate carefully.


=======================================================================
11. SOURCE OF TRUTH
=======================================================================

The SPACBR repository is the authoritative source for:

    configuration
    scripts
    package manifests
    Suckless source
    patches
    installer
    system integration
    documentation

The user's installed home directory is a deployment target.

Changes made manually to the installed system should eventually be
represented in the repository.


=======================================================================
12. GENERATED FILES
=======================================================================

Never commit:

    .DS_Store
    *.orig
    editor backups
    build artifacts
    generated caches
    temporary files
    private keys
    passwords
    tokens
    API keys
    secrets
    machine-specific temporary state


=======================================================================
13. SUCKLESS COMPONENTS
=======================================================================

Maintain independently buildable:

    dwm
    dmenu
    st
    dwmblocks
    slock

Each component must remain understandable and independently maintainable.

Keep patches organized.

For every patch understand:

    what it changes
    why it exists
    what problem it solves
    what maintenance cost it introduces

Do not add patches simply because they are popular.


=======================================================================
14. DWm
=======================================================================

dwm is the central window manager.

Optimize it for:

    fast navigation
    predictable tags
    sensible layouts
    useful keybindings
    Xresources integration
    scratchpad if genuinely useful
    systray if genuinely useful

Every patch must justify itself.

Do not turn dwm into a giant custom desktop environment.


=======================================================================
15. DMENU
=======================================================================

dmenu is the primary contextual interaction mechanism.

Use it for:

    application launching
    power management
    network control
    audio control
    Bluetooth
    wallpaper
    display management
    clipboard
    system actions
    SPACBR utilities

dmenu should provide access to functionality without adding permanent
visual clutter.


=======================================================================
16. DWMBLOCKS
=======================================================================

dwmblocks is the status/control surface.

The default status bar should remain minimal.

Normal permanent information should include only useful state such as:

    network
    volume
    battery
    time

Additional blocks must be justified.

Clickable blocks should expose contextual functionality.

Do not turn dwmblocks into a system-monitor dashboard.


=======================================================================
17. TERMINAL
=======================================================================

Use the existing customized st as the primary SPACBR terminal.

Preserve useful existing patches and configuration.

The terminal should integrate with:

    Xresources
    SPACBR colors
    SPACBR fonts
    shell configuration


=======================================================================
18. LOCKING
=======================================================================

Use slock.

Integrate it with:

    keyboard shortcuts
    idle locking
    suspend workflow

Do not introduce a second lock screen.


=======================================================================
19. X11 SESSION
=======================================================================

SPACBR must provide a clean X11 startup process.

Use:

    ~/.config/xinitrc

or another conventional X11 mechanism where appropriate.

Startup should launch only necessary graphical-session components.

Conceptually:

    X11
      ↓
    Xresources
      ↓
    wallpaper
      ↓
    dunst
      ↓
    picom
      ↓
    dwmblocks
      ↓
    dwm

Do not start system services manually from xinitrc when systemd already
manages them.


=======================================================================
20. SYSTEM SERVICES
=======================================================================

Use systemd for actual system services.

Use X11 startup only for graphical-session components.

Do not duplicate system service management inside shell scripts.


=======================================================================
21. NETWORKING
=======================================================================

Use NetworkManager.

Use nmcli underneath.

SPACBR should provide a dmenu-based network interface supporting:

    current connection
    Wi-Fi scanning
    connection
    disconnection
    saved networks
    interface state

The network interface should be fast and contextual.


=======================================================================
22. AUDIO
=======================================================================

Use:

    PipeWire
    WirePlumber

Provide:

    volume up
    volume down
    mute
    output selection
    input selection

Use native PipeWire utilities.

Do not install a heavyweight audio GUI merely for normal operation.


=======================================================================
23. BLUETOOTH
=======================================================================

Use BlueZ.

Provide dmenu interaction for:

    scan
    list devices
    connect
    disconnect
    trust
    remove

Bluetooth UI should appear only when needed.


=======================================================================
24. MEDIA
=======================================================================

Use playerctl where appropriate.

Support:

    play/pause
    previous
    next

Optionally expose current media in dwmblocks if useful.

Do not permanently display large media information.


=======================================================================
25. BRIGHTNESS
=======================================================================

Use brightnessctl where appropriate.

Provide keyboard shortcuts.

Do not create a permanent brightness GUI.


=======================================================================
26. DISPLAY MANAGEMENT
=======================================================================

Use xrandr.

Support useful operations such as:

    monitor detection
    resolution
    primary display
    enable/disable
    display profiles if genuinely useful


=======================================================================
27. SCREENSHOTS
=======================================================================

Provide:

    full screen
    active window
    region selection

The workflow should be:

    shortcut
       ↓
    capture
       ↓
    save
       ↓
    notification

The process should be fast and unobtrusive.


=======================================================================
28. CLIPBOARD
=======================================================================

Normal clipboard usage should remain invisible.

Provide clipboard history through dmenu only if useful.

Avoid heavyweight permanent clipboard services.


=======================================================================
29. POWER MANAGEMENT
=======================================================================

Provide:

    lock
    logout
    suspend
    reboot
    shutdown

Use systemd/loginctl where appropriate.

Use slock for locking.

Power operations must avoid accidental destructive actions.


=======================================================================
30. IDLE MANAGEMENT
=======================================================================

Provide automatic locking.

Optionally suspend after prolonged inactivity.

Use one lightweight idle mechanism.

Do not run multiple idle daemons.


=======================================================================
31. WALLPAPERS
=======================================================================

Wallpapers belong in:

    ~/.local/share/backgrounds/

Provide simple controls for:

    set
    next
    previous
    random

Use a lightweight X11-compatible mechanism.

No heavyweight wallpaper manager.


=======================================================================
32. NOTIFICATIONS
=======================================================================

Use dunst.

Notifications should be:

    concise
    readable
    useful
    quiet
    temporary

Do not notify the user about meaningless events.


=======================================================================
33. PICOM
=======================================================================

Use picom only for subtle visual enhancement.

Possible uses:

    subtle shadows
    limited transparency

Avoid:

    excessive blur
    expensive effects
    animations
    visual effects that negatively affect performance


=======================================================================
34. VISUAL SYSTEM
=======================================================================

SPACBR must have one visual language.

Define centrally:

    background
    foreground
    muted
    accent
    selection
    border
    warning
    error
    success

Synchronize the visual system across, where practical:

    dwm
    dmenu
    st
    dwmblocks
    dunst
    GTK
    terminal applications
    Vim/Neovim
    Zathura
    PCManFM
    mpv

The system should look like one environment.


=======================================================================
35. TYPOGRAPHY
=======================================================================

Define a coherent typography system.

Choose:

    primary UI font
    monospace font
    terminal font
    icon font only if actually necessary

Typography must remain readable and restrained.


=======================================================================
36. APPLICATION COHERENCE
=======================================================================

Existing applications include:

    Firefox
    PCManFM
    mpv
    Zathura
    Neovim
    Vim
    htop

Make them feel like part of SPACBR through:

    fonts
    colors
    GTK settings
    Xresources
    cursor
    selection
    spacing

Do not customize applications unnecessarily.


=======================================================================
37. SHELL
=======================================================================

Use zsh.

Keep:

    ~/.zshrc

fast and understandable.

Organize configuration logically into:

    environment
    PATH
    aliases
    functions
    interactive configuration
    SPACBR integration

Avoid giant shell plugin ecosystems.

Use ~/.local/bin for user scripts.


=======================================================================
38. SCRIPT DESIGN
=======================================================================

Prefer POSIX sh when possible.

Use Bash only when necessary.

Use Python, Rust or C only when technically justified.

Every script should:

    have one responsibility
    handle errors
    return meaningful exit codes
    avoid unnecessary dependencies
    avoid arbitrary delays
    avoid unnecessary polling


=======================================================================
39. PACKAGE PHILOSOPHY
=======================================================================

Package selection is part of SPACBR architecture.

Never install software merely because it is popular.

For every package ask:

    What problem does this solve?

    Does SPACBR actually need it?

    Can an existing package solve it?

    Can a standard Linux command solve it?

    Can a small script solve it?

    Does it run continuously?

    How much RAM does it consume?

    How much CPU does it consume?

    How many dependencies does it introduce?

    Is it maintained?

    Is it available in official Arch repositories?

    If it is AUR, why is AUR necessary?

Only install software that earns its place.


=======================================================================
40. PACKAGE CATEGORIES
=======================================================================

Organize packages into:

    REQUIRED
    RECOMMENDED
    OPTIONAL
    AUR

The standard SPACBR installation should contain a deliberately curated
set of packages.

Do not create an enormous package list.


=======================================================================
41. OFFICIAL ARCH FIRST
=======================================================================

Prefer official Arch repositories.

Use AUR only when:

    required functionality is unavailable officially
    OR
    the AUR package provides a meaningful improvement

Do not use AUR simply because another configuration uses it.


=======================================================================
42. AUR POLICY
=======================================================================

Every AUR package must have a reason.

Inspect:

    PKGBUILD
    dependencies
    source
    maintenance status

Avoid:

    abandoned packages
    unnecessary -git packages
    duplicate utilities
    unnecessary helpers


=======================================================================
43. AUR HELPER
=======================================================================

Use at most one AUR helper.

If needed, use:

    paru

or another well-maintained helper.

Do not install multiple AUR helpers.

The core installer must remain capable of installing official Arch
packages without an AUR helper.


=======================================================================
44. FUNCTIONAL SOFTWARE
=======================================================================

SPACBR should provide a complete practical desktop workflow.

Evaluate packages for:

    networking
    audio
    Bluetooth
    display management
    brightness
    screenshots
    clipboard
    notifications
    media control
    locking
    power management
    removable media
    process monitoring
    filesystem management
    document viewing
    media playback
    development

Use the smallest reliable tools.

Do not install duplicate utilities.


=======================================================================
45. DEPENDENCY POLICY
=======================================================================

Before adding a dependency:

    check existing Linux utilities
    check the standard system
    check existing SPACBR scripts
    check official Arch packages
    then consider AUR

Prefer:

    existing tool
over:
    new dependency

Prefer:

    small script
over:
    framework

Prefer:

    system service
over:
    custom daemon


=======================================================================
46. PERFORMANCE
=======================================================================

SPACBR must remain lightweight.

Avoid unnecessary:

    daemons
    background polling
    Electron applications
    heavyweight frameworks
    duplicate services
    permanent GUI processes

Prefer:

    command execution
    event-driven behavior
    native services
    small scripts

Measure resource usage rather than guessing.

Every permanent background process must justify its existence.


=======================================================================
47. MEMORY AND RESOURCE TARGET
=======================================================================

Do not allow SPACBR to accumulate unnecessary background memory usage.

When evaluating alternatives consider:

    RAM
    CPU
    process count
    startup time
    dependency count
    maintenance burden

A feature that can be implemented by a small command should not require
a large permanent process.


=======================================================================
48. MACHINE-SPECIFIC CONFIGURATION
=======================================================================

Separate portable SPACBR configuration from hardware-specific settings.

Machine-specific configuration may include:

    monitor layout
    keyboard hardware
    GPU configuration
    laptop battery settings
    brightness hardware

Do not make the entire system machine-specific.


=======================================================================
49. SPACBR CLI
=======================================================================

SPACBR must provide a central command:

    spacbr

The command is the primary management interface.

The mature system must support:

    spacbr install
    spacbr update
    spacbr repair
    spacbr doctor
    spacbr info
    spacbr version
    spacbr uninstall

Potential system commands include:

    spacbr network
    spacbr audio
    spacbr bluetooth
    spacbr display
    spacbr wallpaper
    spacbr screenshot
    spacbr power
    spacbr theme

Only add commands that provide real functionality.

The CLI must remain lightweight.


=======================================================================
50. SPACBR INFO
=======================================================================

Implement:

    spacbr info

It should display:

    SPACBR version
    Arch version
    kernel
    architecture
    X11
    dwm
    terminal
    shell
    important services


=======================================================================
51. SPACBR VERSION
=======================================================================

Implement:

    spacbr version

It must return the exact installed SPACBR release.


=======================================================================
52. SPACBR DOCTOR
=======================================================================

Implement:

    spacbr doctor

Check:

    Arch Linux
    x86_64
    kernel
    Xorg
    X11
    dwm
    dmenu
    st
    dwmblocks
    slock
    dunst
    picom
    NetworkManager
    PipeWire
    WirePlumber
    BlueZ
    required binaries
    XDG directories
    PATH
    fonts
    permissions
    startup configuration
    required services

Use clear results:

    ✓ working
    ✗ broken
    ! warning

Every failure should provide useful remediation where possible.


=======================================================================
53. INSTALLER — CORE PRODUCT
=======================================================================

The installer is a fundamental part of SPACBR.

It must not be an afterthought.

SPACBR must eventually be installable on a supported Arch Linux system
using:

    curl -fsSL https://YOUR-DOMAIN/install | sh

This is the public entry point.

The intended experience is:

    one command
        ↓
    SPACBR installer
        ↓
    complete configured system


=======================================================================
54. CURL PIPE SHELL ARCHITECTURE
=======================================================================

DO NOT place the complete SPACBR installer inside the public:

    curl | sh

script.

The public bootstrap must remain small and auditable.

The architecture must be:

    curl
      ↓
    tiny bootstrap
      ↓
    detect system
      ↓
    determine release
      ↓
    download versioned release
      ↓
    verify integrity/signature where practical
      ↓
    execute real installer


The actual installation logic belongs to the versioned SPACBR release.


=======================================================================
55. DOMAIN
=======================================================================

The SPACBR domain is the public front door.

Conceptually:

    https://YOUR-DOMAIN/install

The domain should eventually provide:

    /install
    /docs
    /releases
    /source

The exact URL structure may be chosen during implementation.


=======================================================================
56. DOMAIN IS NOT SOURCE OF TRUTH
=======================================================================

The source repository remains authoritative.

The architecture must be:

    source repository
          ↓
       release
          ↓
    release artifacts
          ↓
       domain
          ↓
      bootstrap
          ↓
      installer


If the domain becomes unavailable, SPACBR must still be installable
through:

    repository clone
    release archive
    local filesystem


=======================================================================
57. VERSIONED RELEASES
=======================================================================

SPACBR must use versioned releases.

Examples:

    v0.1.0
    v0.2.0
    v1.0.0

The installer must support exact versions.

Never permanently depend on:

    main
    master
    unversioned HEAD
    arbitrary latest source


=======================================================================
58. RELEASE MANIFEST
=======================================================================

Every release should describe:

    SPACBR version
    installer version
    Arch package set
    AUR package set
    configuration version
    Suckless versions
    patches
    compatibility requirements

The installer must use this information to reproduce the release.


=======================================================================
59. SECURE DISTRIBUTION
=======================================================================

Use:

    HTTPS
    immutable/versioned releases
    checksums
    signed metadata/artifacts where practical

The installer must not blindly execute arbitrary unverified remote
content.


=======================================================================
60. INTERACTIVE INSTALLER
=======================================================================

After the bootstrap, the user should receive a proper installer.

The installer should display:

    SPACBR
    version
    detected system
    architecture
    hardware
    packages
    AUR packages
    configuration changes
    Suckless components
    services
    installation destination

The user must understand significant changes before they happen.


=======================================================================
61. INSTALLER MODES
=======================================================================

Support:

    install
    update
    repair
    uninstall


=======================================================================
62. INSTALLATION SAFETY
=======================================================================

Before modifying user files:

    detect conflicts
    create backups
    preserve unrelated configuration
    explain important changes

Never blindly overwrite:

    ~/.config
    ~/.local
    ~/.zshrc
    ~/.vimrc


=======================================================================
63. IDEMPOTENCY
=======================================================================

Running the installer multiple times must not progressively damage the
system.

Detect existing:

    packages
    configurations
    binaries
    services
    Suckless builds
    SPACBR versions

Act accordingly.


=======================================================================
64. LOCAL INSTALLATION
=======================================================================

SPACBR must support local installation from the repository.

For example:

    ./install/install.sh

The same underlying installation logic should be shared between:

    web installation
    local installation
    development/testing


=======================================================================
65. UPDATE
=======================================================================

Implement:

    spacbr update

It should:

    detect installed version
    check releases
    show important changes
    create backups
    retrieve release
    update configuration
    rebuild affected Suckless components
    validate the system
    run spacbr doctor


=======================================================================
66. REPAIR
=======================================================================

Implement:

    spacbr repair

It should diagnose and repair common problems involving:

    packages
    binaries
    configuration
    permissions
    X11
    Suckless components
    services
    XDG directories
    PATH
    fonts
    startup configuration

Repair only what is broken.


=======================================================================
67. ROLLBACK
=======================================================================

SPACBR updates must have a recovery strategy.

Before updating:

    record current version
    preserve important configuration
    preserve generated state where necessary

If an update fails:

    restore the previous configuration/version where possible

The user must not be left with a half-installed desktop.


=======================================================================
68. UNINSTALL
=======================================================================

Implement:

    spacbr uninstall

It must remove only SPACBR-owned components.

Never delete:

    user documents
    unrelated configuration
    unrelated packages
    personal data


=======================================================================
69. INSTALLATION FLOW
=======================================================================

The mature installation flow must look like:

    USER
      │
      ▼
    curl -fsSL https://YOUR-DOMAIN/install | sh
      │
      ▼
    tiny bootstrap
      │
      ▼
    detect Arch Linux
      │
      ▼
    determine SPACBR release
      │
      ▼
    verify release
      │
      ▼
    interactive installer
      │
      ├── packages
      ├── configuration
      ├── Suckless
      ├── X11
      ├── services
      └── SPACBR tools
      │
      ▼
    validation
      │
      ▼
    spacbr doctor
      │
      ▼
    installation complete


=======================================================================
70. FINAL USER EXPERIENCE
=======================================================================

The user-facing experience must eventually become:

    curl -fsSL https://YOUR-DOMAIN/install | sh

followed by a proper interactive installer.

After installation, the user manages SPACBR using:

    spacbr install
    spacbr update
    spacbr repair
    spacbr doctor
    spacbr info
    spacbr version
    spacbr uninstall

This CLI is a fundamental part of the system.

Do not implement it as an afterthought.


=======================================================================
71. XDG DEPLOYMENT
=======================================================================

The installer must deploy files consistently into:

    ~/.config
    ~/.local/bin
    ~/.local/share
    ~/.local/state
    ~/.local/src

while preserving user-owned data.

Choose a deliberate deployment strategy:

    symlinks
or
    managed copies

Do not mix deployment strategies randomly.


=======================================================================
72. SUCKLESS BUILD SYSTEM
=======================================================================

The installer must be able to build:

    dwm
    dmenu
    st
    dwmblocks
    slock

from SPACBR-controlled source.

Prefer installing resulting user-controlled binaries into:

    ~/.local/bin/

where practical.

Do not unnecessarily install SPACBR binaries into /usr/local.


=======================================================================
73. KEYBINDINGS
=======================================================================

Design keybindings as one coherent system.

Common operations should be keyboard-first.

Avoid random shortcuts.

Document important bindings.

The user should be able to operate most of SPACBR without a mouse.


=======================================================================
74. INTERACTION HIERARCHY
=======================================================================

SPACBR has three primary interaction layers.

LEVEL 1:

    keyboard shortcuts

LEVEL 2:

    dmenu

LEVEL 3:

    terminal commands/applications

Example:

    Mod + Shift + N
        ↓
    dmenu
        ↓
    NetworkManager action


=======================================================================
75. DESIGN DECISION RULE
=======================================================================

When two visual designs are equally functional, prefer:

    fewer permanent elements
    better spacing
    stronger hierarchy
    fewer colors
    fewer icons
    fewer effects
    better readability


=======================================================================
76. ARCHITECTURAL DECISION RULE
=======================================================================

When multiple implementations are possible, prefer the implementation
that is:

    simpler
    smaller
    faster
    more native to Linux
    more native to Arch
    more native to X11
    more compatible with dwm
    easier to debug
    easier to remove
    easier to reproduce
    lower in dependencies


=======================================================================
77. FEATURE DECISION RULE
=======================================================================

Never ask:

    "What cool feature can we add?"

Ask:

    "What problem does the user have?"

Then solve the problem with the smallest reliable mechanism.

If the feature does not solve a real problem:

    do not implement it.


=======================================================================
78. PACKAGE DECISION RULE
=======================================================================

Never ask:

    "Which packages are popular?"

Ask:

    "What capabilities must SPACBR provide?"

Then select the smallest reliable tools required to provide those
capabilities.


=======================================================================
79. NO FEATURE CREEP
=======================================================================

Before adding a feature, determine:

    what problem it solves
    why it belongs in SPACBR
    why an existing utility cannot solve it
    whether it creates background resource usage
    how it integrates with the SPACBR UX

If the feature fails these tests:

    do not implement it.


=======================================================================
80. NO DEPENDENCY CREEP
=======================================================================

Before adding a dependency:

    check standard Linux utilities
    check existing SPACBR scripts
    check official Arch packages
    then consider AUR

Prefer:

    existing tool
over:
    new dependency

Prefer:

    script
over:
    framework

Prefer:

    system service
over:
    custom daemon


=======================================================================
81. PERSONAL IDENTITY
=======================================================================

SPACBR must feel like a personal system.

Its personality should come from:

    workflow
    typography
    colors
    shortcuts
    scripts
    command naming
    subtle visual details
    consistency

Not from:

    giant logos
    excessive branding
    flashy effects
    decorative UI


=======================================================================
82. OMARCHY INSPIRATION
=======================================================================

Omarchy may be considered inspiration for:

    cohesive defaults
    integrated configuration
    opinionated workflow
    easy installation
    unified system experience

However, SPACBR must remain independently designed.

Do not copy Omarchy's:

    architecture
    visual identity
    package selection
    scripts
    workflow
    implementation


=======================================================================
83. DOCUMENTATION
=======================================================================

The project must contain:

    README.md
    installation documentation
    architecture documentation
    package documentation
    keybindings
    troubleshooting
    development documentation
    release notes

Documentation should explain both:

    WHAT
    WHY


=======================================================================
84. TESTING
=======================================================================

Before considering SPACBR production-ready, test:

    fresh Arch installation
    existing Arch installation
    existing dotfiles
    clean home directory
    package installation
    AUR installation
    X11 startup
    dwm startup
    networking
    audio
    Bluetooth
    screenshots
    clipboard
    brightness
    displays
    notifications
    locking
    suspend
    reboot
    shutdown
    update
    repair
    uninstall
    rollback


=======================================================================
85. DEVELOPMENT PHASES
=======================================================================

Implement in this order.

PHASE 1

    Inspect the current repository.

PHASE 2

    Audit every existing configuration.

PHASE 3

    Audit every Suckless modification.

PHASE 4

    Audit packages and dependencies.

PHASE 5

    Establish the architecture.

PHASE 6

    Clean the repository carefully.

PHASE 7

    Stabilize dwm.

PHASE 8

    Stabilize dmenu.

PHASE 9

    Stabilize st.

PHASE 10

    Stabilize dwmblocks.

PHASE 11

    Stabilize slock.

PHASE 12

    Establish X11 startup.

PHASE 13

    Establish visual system.

PHASE 14

    Establish SPACBR scripts.

PHASE 15

    Establish dmenu contextual interfaces.

PHASE 16

    Integrate networking.

PHASE 17

    Integrate audio.

PHASE 18

    Integrate Bluetooth.

PHASE 19

    Integrate display management.

PHASE 20

    Integrate screenshots, clipboard, media and power workflows.

PHASE 21

    Finalize package manifests.

PHASE 22

    Implement spacbr CLI.

PHASE 23

    Implement spacbr doctor.

PHASE 24

    Implement installer.

PHASE 25

    Implement update.

PHASE 26

    Implement repair.

PHASE 27

    Implement uninstall.

PHASE 28

    Implement release system.

PHASE 29

    Implement web bootstrap.

PHASE 30

    Test clean Arch installation.

PHASE 31

    Performance audit.

PHASE 32

    Security audit.

PHASE 33

    Final release.


=======================================================================
86. IMPORTANT DEVELOPMENT RULE
=======================================================================

Before writing or changing code:

    inspect the existing repository
    understand the current architecture
    identify dependencies
    identify existing functionality
    identify duplication
    identify missing functionality
    identify risks

Then create an architecture/migration plan.

Do not immediately rewrite the repository.

Do not delete working configuration simply to make the structure look
cleaner.

Preserve existing personal configuration wherever it is compatible
with the architecture.


=======================================================================
87. CHANGE SAFETY
=======================================================================

Do not make destructive changes without explaining them.

When modifying important configuration:

    create backups where appropriate
    preserve user data
    maintain rollback capability

Never treat the user's home directory as disposable.


=======================================================================
88. RECOVERY
=======================================================================

If X11 fails:

    the user must still be able to reach a TTY.

If SPACBR configuration fails:

    backups must exist.

If an update fails:

    previous state should be recoverable.

If SPACBR is uninstalled:

    the underlying Arch Linux installation must remain usable.


=======================================================================
89. FINAL SYSTEM MODEL
=======================================================================

The final SPACBR system should conceptually be:

                         SPACBR
                           │
        ┌──────────────────┼───────────────────┐
        │                  │                   │
        ▼                  ▼                   ▼
   Configuration      Interaction          Installer
        │                  │                   │
        ▼                  ▼                   ▼
      XDG files          dmenu              Domain
        │                  │                   │
        ▼                  ▼                   ▼
    Xresources          dwmblocks          Bootstrap
        │                  │                   │
        └────────────┬─────┘                   ▼
                     ▼                    Versioned
                    dwm                    Release
                     │                        │
                     ▼                        ▼
                    X11                   Installer
                     │                        │
                     ▼                        ▼
                Arch Linux              Arch Linux
                     │
                     ▼
                  Hardware


=======================================================================
90. FINAL PRODUCT DEFINITION
=======================================================================

SPACBR is:

    an opinionated personal desktop system
    built on Arch Linux
    using X11 and dwm
    assembled from Suckless tools and native Linux utilities
    integrated through lightweight scripts
    unified by one visual language
    unified by one interaction model
    reproducible through versioned releases
    installable through a secure web bootstrap
    manageable through the spacbr CLI
    diagnosable through spacbr doctor
    updateable through versioned releases
    recoverable without destroying Arch Linux


=======================================================================
91. FINAL EXPERIENCE
=======================================================================

The user logs in.

There is almost nothing on the screen.

The system is quiet.

dwm manages windows.

dwmblocks shows only essential state.

dmenu provides access to everything else.

Keyboard shortcuts handle common operations.

Linux utilities perform the actual work.

Suckless tools provide the minimal graphical primitives.

SPACBR scripts connect everything.

The visual language is consistent.

The interaction model is consistent.

Nothing feels random.

Nothing feels unnecessary.

Nothing feels like someone else's rice.

It feels like one complete personal operating environment.

Underneath, it remains clean Arch Linux.


=======================================================================
92. FINAL PRINCIPLE
=======================================================================

DO NOT BUILD SPACBR TO HAVE MANY FEATURES.

BUILD SPACBR TO HAVE THE RIGHT FEATURES.

The visible system should remain extremely simple.

The underlying system should remain extremely capable.

The user should be able to perform complex tasks without needing a
complex desktop.


=======================================================================
93. FINAL IMPLEMENTATION REQUIREMENT
=======================================================================

Build the smallest complete system that satisfies this specification.

Do not over-engineer.

Do not introduce unnecessary frameworks.

Do not introduce unnecessary daemons.

Do not introduce unnecessary dependencies.

Do not copy another distribution.

Do not turn SPACBR into a distribution.

Do not replace working components without reason.

Do not add features simply because they look impressive.

Every component must have a clear responsibility.

Every package must justify its existence.

Every permanent process must justify its resource usage.

Every visual element must justify its existence.

Every script must have a clear responsibility.

Every architectural decision must prioritize:

    simplicity
    functionality
    performance
    maintainability
    security
    reproducibility
    consistency


=======================================================================
                         SPACBR
=======================================================================

                    SIMPLE AT THE SURFACE
                    POWERFUL UNDERNEATH
                    BUILT FOR THE USER
=======================================================================
