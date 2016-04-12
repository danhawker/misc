# installation
sudo apt-get install pcscd opensc openct libhal1
sudo apt-get install libnss3-tools
sudo apt-get install p11-kit

# unpacking pkiclient-5.00.28-0.i386.rpm
sudo cp libeToken.so.5.00 /usr/local/lib
sudo ldconfig

# fixing pcscd
echo 'DAEMON_ARGS="-d"' | sudo tee /etc/default/pcscd
sudo sed -i 's/^exit 0/#&/' /etc/init.d/pcscd
sudo killall pcscd
sudo /etc/init.d/pcscd start

# hardware verification
pkcs11-tool --module libeToken.so.5 -T
pkcs11-tool --module libeToken.so.5 -l -O
opensc-tool -l

# dump certs
pkcs11-tool --module libeToken.so.5 --slot 0 --type cert -O | awk '$1=="label:" { print $2 }' | while read l; do pkcs11-tool --module libeToken.so.5 --slot 0 --type cert --label $l -r | openssl x509 -inform der -text > $l.crt; done

# eToken for SSH
ssh-keygen -D libeToken.so.5
ssh -I libeToken.so.5 localhost
sftp -oPKCS11Provider=libeToken.so.5 localhost

# eToken for SSH agent
sudo mv /etc/xdg/autostart/gnome-keyring-ssh.desktop /etc/xdg/autostart/gnome-keyring-ssh.desktop.disabled
logout # for restarting ssh-agent
ssh-add ~/.ssh/id_???
ssh-add -s /usr/local/lib/libeToken.so.5
ssh-add -l
ssh -A localhost ssh-add -l

# eToken for firefox
modutil -add eToken -libfile libeToken.so.5 -dbdir $HOME/.mozilla/firefox/*.default
modutil -list -dbdir $HOME/.mozilla/firefox/*.default
certutil -L -d $HOME/.mozilla/firefox/*.default -h eToken

# eToken for evolution
mkdir -p $HOME/.pki/nssdb
modutil -add eToken -libfile libeToken.so.5 -dbdir $HOME/.pki/nssdb
modutil -list -dbdir $HOME/.pki/nssdb
certutil -L -d $HOME/.pki/nssdb -h eToken

# eToken for p11-kit
echo 'module: /usr/local/lib/libeToken.so.5' | sudo tee /etc/pkcs11/modules/etoken
p11-kit -l
pkcs11-tool --module libp11-kit.so.0 -T
