# dionysus system setup - sudo, bash, and ssh segment

tested with debian-10.0.0-amd64-i386-netinst.iso

install debian (creating a non-root user during the setup process)

sign in as root

## install sudo

`apt-get install -y sudo`

add your non-root user to sudoers (replacing `$username` with the name of your non-root user)

```
echo -e "\n$username ALL=(ALL) ALL\n">>/etc/sudoers
```

## update system

`apt-get update`

`apt-get upgrade`

## ensure bash is installed

`apt-get install bash`

## install ssh

`apt-get install -y openssh-server`

## enable and start ssh

`systemctl enable ssh`

`systemctl start ssh`

you can now log out of root and log in (or ssh in) with your non-root user

transfer or download the dionysus install scripts and any supplementary files and run as sudo
