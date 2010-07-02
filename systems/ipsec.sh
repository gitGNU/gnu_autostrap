#/bin/bash
#    -redir tcp:10022::22 \
qemu -kernel bzImage -append "root=/dev/hda1 clocksource=pit" \
    -kernel-kqemu \
    -net nic -net socket,listen=:1234 \
    ipsec.qcow2
