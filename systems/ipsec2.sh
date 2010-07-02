#/bin/bash
qemu -kernel bzImage -append "root=/dev/hda1 clocksource=pit" \
    -kernel-kqemu \
    -redir tcp:10022::22 \
    -net nic,macaddr=52:54:00:12:34:57 -net socket,connect=127.0.0.1:1234 \
    ipsec2.qcow2
