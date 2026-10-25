Dethrace for MiSTer
===================

Carmageddon (1997) and its Splat Pack on MiSTer FPGA as a hybrid port.

Everything about it (options, controls, help):
  https://github.com/ItsDanik/Dethrace_MiSTer

Game files
  Copy your game's folders into this folder, /media/fat/games/dnk/Dethrace/,
  whole and with all the files as they are:
    Carmageddon                 its DATA folder to DATA
                                (DATA/GENERAL.TXT must be there)
    Splat Pack (optional)       its DATA folder to SPLATPAK/DATA
    CD music (optional, GOG)    the MUSIC folder to MUSIC, the Splat Pack's
                                to SPLATPAK/MUSIC
  They can go on a USB drive instead, in /media/usb0/games/dnk/Dethrace/.

Playing
  1. Run danik_hybrid_ports once from the MiSTer's Scripts menu. It starts
     the game whenever its menu entry is loaded.
  2. Load the game from the Other menu, e.g. dnk-Carmageddon, or from the
     Hybrid Ports folder if you moved the games there in the launcher.
  Buttons are changed in the OSD under "Define Dethrace buttons". A button
  left without a name there does not reach the game at all: name every
  button, or leave the definition as it is.

If something is wrong
  Open the OSD while it happens and pick Save Diagnostic Report, the last
  line. Send the file it saves in games/dnk/diagnostics/ with a few words
  on what went wrong: https://github.com/ItsDanik/Dethrace_MiSTer/issues

Credits and licenses
  dethrace by Jeff Harris and the dethrace-labs contributors, with BRender
  by Argonaut Software (LICENSE-dethrace.txt; it may only be used with the
  assets of a copy of Carmageddon you own). MiSTer by Sorgelig and the
  MiSTer-devel contributors. Inspired by MiSTer Frontier by MiSTer
  Organize. The launcher: GPL-3.0 (LICENSE-gpl3.txt); the FPGA core:
  GPL-2.0. Source: https://github.com/ItsDanik/Dethrace_MiSTer

Support the project: https://www.patreon.com/itsdanik
