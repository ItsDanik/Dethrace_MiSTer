Dethrace for MiSTer - Carmageddon and its Splat Pack as a hybrid port
=====================================================================

The game (dethrace, a reimplementation of Carmageddon) runs on the MiSTer's
ARM CPU; the Dethrace FPGA core provides native 15kHz video (CRT, VGA and
HDMI), audio and input.

Disclaimer: AI is being used to speed up development of this project.

Requirements
  - danik_hybrid_ports, the launcher that comes with this release
    (Scripts/danik_hybrid_ports.sh): run it ONCE from the MiSTer's Scripts
    menu. It starts the game whenever its menu entry is loaded, keeps
    running after a reboot, and serves all our hybrid ports; its screen
    picks which ports and games to have, and can keep them up to date
    through update_all. It replaces danik_hybrid_cores, the launcher before
    it, and moves ports installed the old way (games/Dethrace/) into the
    new folders by itself. Without it the core says "Game not running".
  - Game data. It is not included: the DATA folder of Carmageddon, from
    your original CD or the GOG release (Carmageddon Max Pack), and
    optionally that of the Splat Pack, or of a demo.

Install
  With update_all (Downloader 2.4 or newer): copy
  downloader_danik_hybrid_ports.ini to /media/fat/, run update_all, run
  danik_hybrid_ports from the Scripts menu, tick the games, X: Apply.
  By hand:
  1. Extract the zip to the root of the SD card (/media/fat): _Other/,
     games/dnk/Dethrace/, Scripts/ and downloader_danik_hybrid_ports.ini
     (with which update_all keeps the ports up to date from then on).
  2. Copy Carmageddon's DATA folder to /media/fat/games/dnk/Dethrace/DATA
     (DATA/GENERAL.TXT must exist).
  3. Optional, the Splat Pack: its DATA folder to
     /media/fat/games/dnk/Dethrace/SPLATPAK/DATA
  4. Optional CD music (GOG): the MUSIC folder (Track02.ogg ...) to
     /media/fat/games/dnk/Dethrace/MUSIC (the Splat Pack's to
     SPLATPAK/MUSIC)
  5. Run danik_hybrid_ports from the Scripts menu, if you have not done so
     before (see Requirements).
  6. Load the game from the Other menu, e.g. dnk-Carmageddon.

A menu entry starts the demo of its game when the full game is not there.
When a game's files are missing, the core says which files to copy where.
Each game keeps its own OSD settings and button mappings. The core file
itself (_Other/dnk/dnk-Dethrace_*.rbf, or from Recent) lists the games that
are there to pick from; quitting a game then returns to the list, otherwise
to the MiSTer menu.

OSD options
  Aspect ratio, Scale, Scandoubler Fx, Stereo Mix as usual.
  FPS Counter   shows the pictures per second in the top left corner.
  HDMI Only     as in the other hybrid ports, for resolutions of 640x400
                and more: Dethrace has none, so nothing changes here.
  CRT Options   for a 15kHz screen: Horizontal Size, Horizontal Pos and
                Vertical Pos fit the picture to it. The pixels stay as they
                are; HDMI is not affected. The size is for the game's
                picture: the core's own, with its messages, keeps its
                width. Not there with forced_scandoubler=1. HUD (Top) and
                HUD (Bottom): in a race in 320x240, how many lines the
                instruments at the top and at the bottom are from the edges
                of the screen, 0 to 24 (10 by default), so that a CRT's
                overscan does not hide them; greyed out with 320x200.
  Sound Volume  master volume of sound effects and cutscene audio
  Music Volume  master volume of the CD music
                (both on top of the game's own volume settings)
  Resolution    320x200 (default): the original mode. 320x240: the view
                from outside the car is drawn with 240 rows instead of 200
                during a race: the same view, finer vertically. The
                instruments keep their size and sit the HUD (Top) / HUD
                (Bottom) margins from the edges. Menus, the cockpit view,
                the map and a reduced view size stay 320x200. Takes about
                10% more time per frame. Applies at once.
  Renderer      Optimized (default): rewritten rasteriser and fog loops,
                pixel for pixel the same picture as the original code.
                Fast: also simplifies the perspective texture mapping; the
                picture is nearly the same, the game runs 20-25% faster.
                Original: the original rasteriser code.
  Lock to 30 FPS
                shows every frame for exactly two video fields (29.8 fps)
                instead of a frame rate that floats between 30 and 60 fps.
                Steadier motion, best together with the Fast renderer.
  Cutscenes     Off skips the intro and the other videos.
  Cheats        in a race: Invulnerability: the car takes no damage while
                it is on. Instant Repair: the car repaired at once. Extra
                Credits: 10000 credits. Finish Lap: the lap counts as
                completed (the last one finishes the race).
  Rumble        On (default): the controller rumbles when the car is hit.
                Off.
  Menu OK, Menu Back
                the gamepad button that acts as Enter / Esc in the game's
                menus, even if it is also a race control. MiSTer (default)
                uses the OK/Back buttons of your MiSTer menu.

Controls
  Keyboard: the original PC controls.
  Gamepad in a race (default mapping):
    Left stick                          Steer, analog
    D-pad                               Steer
    Right trigger (RT / R2)             Accelerate, analog
    Left trigger (LT / L2)              Brake, analog
    B (Xbox A / PlayStation Cross)      Accelerate
    Y (Xbox X / PlayStation Square)     Brake
    A (Xbox B / PlayStation Circle)     Handbrake
    X (Xbox Y / PlayStation Triangle)   Change View
    L (LB / L1)                         Repair
    R (RB / R1)                         Map
    Select                              Recover
    Start                               Pause (Esc)
  The triggers need no mapping: MiSTer passes no trigger axes to a core, so
  the game reads them from the controller itself (the one pressed furthest).
  The controller rumbles when the car is hit, the harder the stronger (OSD
  option Rumble).
  "Pratcam" (the driver's face in the corner, key P) has no button by
  default: give it one in "Define Dethrace buttons" to switch it on and off
  from the gamepad.
  "Menu OK" and "Menu Back" in "Define Dethrace buttons" are only needed for
  a button that has no race function. MiSTer doesn't let you assign a button
  twice there, so to use a race control as Enter/Esc in menus, pick that
  button in the OSD's Menu OK/Menu Back options instead.

Quitting from the game's main menu returns to the MiSTer menu.
Logs: /media/fat/logs/dnk/Dethrace/dethrace.log

Credits
  dethrace by Jeff Harris and the dethrace-labs contributors.
  BRender by Argonaut Software.
  MiSTer by Sorgelig and the MiSTer-devel contributors.
  MiSTer Frontier by MiSTer Organize
  (https://github.com/MiSTerOrganize/MiSTer_Frontier): thank you for the
  inspiration. Hybrid cores on the MiSTer, and the way their game is
  launched, come from MiSTer Frontier. Our launcher is a separate
  implementation and does not need MiSTer Frontier installed.

License
  dethrace: LICENSE-dethrace.txt
  The launcher scripts: GPL-3.0 (LICENSE-gpl3.txt)
  The FPGA core: GPL-2.0
  Source: https://github.com/ItsDanik/Dethrace_MiSTer
          https://github.com/ItsDanik/Hybrid_MiSTer (launcher)
