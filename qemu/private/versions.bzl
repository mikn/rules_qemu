"""Version -> URL + sha256 mappings for QEMU-related binaries."""

# OVMF firmware versions (from Debian packages)
OVMF_VERSIONS = {
    "2025.02-8": {
        "url": "https://snapshot.debian.org/archive/debian/20250828T025831Z/pool/main/e/edk2/ovmf_2025.02-8_all.deb",
        "sha256": "d82312d863b18aebde958133144185c45685d3c6e1d217b4969913d713c05bf7",
        "code_path": "usr/share/OVMF/OVMF_CODE_4M.secboot.fd",
        "vars_path": "usr/share/OVMF/OVMF_VARS_4M.fd",
    },
}

# swtpm versions — built from source with rules_foreign_cc
SWTPM_VERSIONS = {
    "0.10.1": {
        "swtpm": {
            "url": "https://github.com/stefanberger/swtpm/archive/refs/tags/v0.10.1.tar.gz",
            "sha256": "f8da11cadfed27e26d26c5f58a7b8f2d14d684e691927348906b5891f525c684",
            "strip_prefix": "swtpm-0.10.1",
        },
        "libtpms": {
            "url": "https://github.com/stefanberger/libtpms/archive/refs/tags/v0.10.2.tar.gz",
            "sha256": "edac03680f8a4a1c5c1d609a10e3f41e1a129e38ff5158f0c8deaedc719fb127",
            "strip_prefix": "libtpms-0.10.2",
        },
        "json_glib": {
            "url": "https://download.gnome.org/sources/json-glib/1.10/json-glib-1.10.8.tar.xz",
            "sha256": "55c5c141a564245b8f8fbe7698663c87a45a7333c2a2c56f06f811ab73b212dd",
            "strip_prefix": "json-glib-1.10.8",
        },
        "libtasn1": {
            "url": "https://ftp.gnu.org/gnu/libtasn1/libtasn1-4.19.0.tar.gz",
            "sha256": "1613f0ac1cf484d6ec0ce3b8c06d56263cc7242f1c23b30d82d23de345a63f7a",
            "strip_prefix": "libtasn1-4.19.0",
        },
        "gmp": {
            "url": "https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz",
            "sha256": "a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898",
            "strip_prefix": "gmp-6.3.0",
        },
    },
}

# QEMU versions - currently host-only, will add download URLs later
QEMU_VERSIONS = {
    "9.2.0": {
        "x86_64": {
            # TODO: Add deb URL for hermetic QEMU when needed
        },
    },
}
