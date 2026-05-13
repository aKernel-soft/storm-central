# STOLER Central Repository

Official package index for **STOLER** – a decentralized package manager using magnet links and direct URLs.  
Developer: **aKernel** within the **STORM** project.

---

## Quick Start

Install STOLER with a single command:
```bash
curl -sL https://raw.githubusercontent.com/aKernel-soft/storm-central/main/install.sh | bash
```

After installation the central repository will be added automatically. Open the shop:

```bash
stoler shop
```

List all available packages:

```bash
stoler list
```

---

How It Works

1. Central index is stored in this repository (index.json).
      Users add it with: stoler remote add storm-central URL.
2. Packages can be retrieved in two ways:
   · Direct URL – downloaded via HTTP/HTTPS (fast, always available).
   · Magnet link – decentralized torrent download (requires transmission client and active seeders).
3. STOLER update is performed with:
      stoler self-update https://raw.githubusercontent.com/aKernel/storm-central/main/packages/stoler.sh.

---

Adding Your Own Package

1. Fork this repository.
2. Place your file into the packages/ folder.
3. Edit index.json by adding an entry following this template:
   ```json
   {
       "name": "your-package",
       "desc": "Short description",
       "type": "script|apk|binary|other",
       "url": "https://direct-link-to-your-file",
       "magnet": "magnet:?xt=urn:btih:..."
   }
   ```
4. Submit a Pull Request. Once merged, the package becomes available to everyone.

