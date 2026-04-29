# 📡 PXE Direct Server (iPXE + dnsmasq)

Script Bash per avviare rapidamente un server PXE locale basato su **iPXE**, con supporto a boot via HTTP di immagini come **SystemRescue** e **Kali Linux**.

---

## 🚀 Funzionalità

- Setup automatico di:
  - DHCP + TFTP tramite `dnsmasq`
  - HTTP server (`python3 -m http.server`)
- Supporto boot UEFI e BIOS
- Menu iPXE dinamico via HTTP
- Boot supportati:
  - SystemRescue (RAM / Safe)
  - Kali Linux (GUI / Text / Forensic)
- Uso opzionale di build custom iPXE

---

## 📁 Struttura richiesta


- /srv/tftp # file PXE (ipxe.efi, undionly.kpxe, ecc.)

- /srv/http # kernel, initrd, filesystem squashfs


---

## ⚙️ Configurazione

Modifica le variabili all’inizio dello script:


- INTERFACE="eth0"

- SERVER_IP="192.168.11.1"


Se utilizzi una build custom iPXE:


- IPXE_BUILD_DIR=~/blobspace/pxe-direct-server/ipxe/src/bin-x86_64-efi


---

## ▶️ Utilizzo

- Rendi eseguibile lo script:


chmod +x pxe-direct-server-netboot.sh

chmod +x pxe-direct-systemrescue-locale.sh



- Avvia il server:


sudo ./pxe-direct-server-netboot.sh

sudo ./pxe-direct-systemrescue-locale.sh

---

## 🌐 Accesso

- PXE boot client → menu iPXE automatico
- HTTP server disponibile su: http://192.168.11.1:8080

---

## 📦 Requisiti

- Linux (testato su Kali)
- dnsmasq
- python3
- Permessi root

---

## 📌 Aggiungere nuove ISO al server PXE

Per aggiungere una nuova immagine:

1. Montare la ISO:
   sudo mount -o loop file.iso /mnt/iso

2. Identificare i file di boot (vmlinuz, initrd, filesystem.squashfs)

3. Copiarli in /srv/http:
   sudo mkdir -p /srv/http/<nome_distro>
   sudo cp ... /srv/http/<nome_distro>/

4. Aggiornare il menu iPXE con i nuovi path HTTP

	- Nel file menu-locale.ipxe aggiungi:

:kali
kernel http://${server_ip}:8080/kali/vmlinuz \
    boot=live \
    components \
    netboot=http \
    fetch=http://${server_ip}:8080/kali/filesystem.squashfs \
    ip=dhcp

initrd http://${server_ip}:8080/kali/initrd.img
boot || goto menu

	- Nel menu iniziale aggiungi:

item kali Kali Linux

5. Smontare la ISO:
   sudo umount /mnt/iso

---

## ⚠️ Note

- Disabilita altri servizi DHCP nella rete per evitare conflitti
- Verifica che la scheda di rete sia corretta (eth0, wlan0, ecc.)
- Porte richieste:
  - UDP 67/68 → DHCP
  - UDP 69 → TFTP
  - TCP 8080 → HTTP
