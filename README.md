# LinuxSetup
Here are some of my configs, tools and scripts that I am actively using in my Linux Fedora KDE setup

Command for building system monitor:
gcc -o sysmon_widget ~/monitor.c $(pkg-config --cflags --libs gtk4 gtk4-layer-shell-0)
