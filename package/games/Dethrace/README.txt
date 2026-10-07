Dethrace for MiSTer - Carmageddon as a hybrid core
===================================================

The game (dethrace, a reimplementation of Carmageddon) runs on the MiSTer's
ARM CPU; the Dethrace FPGA core provides native 15kHz video (CRT, VGA and
HDMI), audio and input.

Disclaimer: AI is being used to speed up development of this project.

Requirements
  - danik_hybrid_cores, the launcher that comes with this release
    (Scripts/danik_hybrid_cores.sh): copy it to /media/fat/Scripts/ and run
    it ONCE from the MiSTer's Scripts menu. It starts the game whenever
    the core is loaded, keeps running after a reboot, and serves all our
    hybrid cores. Every hybrid core brings the launcher along and the
    newest version is the one that runs, so it never has to be run again
    after an update. Without it the core only shows the MiSTer logo.
  - Carmageddon game data. It is not included: use your original CD or the
    GOG release (Carmageddon Max Pack).

Install
  1. Copy _Other/Dethrace_*.rbf to /media/fat/_Other/
  2. Copy games/Dethrace/ to /media/fat/games/Dethrace/
  3. Copy the game's DATA folder to /media/fat/games/Dethrace/DATA
     (DATA/GENERAL.TXT must exist).
  4. Optional CD music (GOG): copy the MUSIC folder (Track02.ogg ...) to
     /media/fat/games/Dethrace/MUSIC
  5. Run danik_hybrid_cores from the Scripts menu, if you have not done so
     before (see Requirements).
  6. Load Dethrace from the Other menu.

OSD options
  Stereo Mix, Scandoubler Fx, Aspect ratio as usual.
  HDMI Only     as in the other hybrid cores, for resolutions of 640x400
                and more: Dethrace has none, so nothing changes here.
  CRT Options   for a 15kHz screen: Horizontal Size, Horizontal Pos and
                Vertical Pos fit the picture to it. The pixels stay as they
                are; HDMI is not affected. Not there with
                forced_scandoubler=1.
  Sound Volume  master volume of sound effects and cutscene audio
  Music Volume  master volume of the CD music
                (both on top of the game's own volume settings)
  Resolution    320x200 (default): the original mode.
                320x240: the view from outside the car is drawn with 240
                rows instead of 200 during a race: the same view, finer
                vertically. The instruments keep their size: the ones at
                the top start at the top of the screen, the ones at the
                bottom (speed, revs, gear, damage) are about 10 rows above
                its lower edge. Menus, the cockpit view, the map and
                a reduced view size stay 320x200. Takes about 10% more
                time per frame. Applies at once.
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
  Menu OK, Menu Back
                the gamepad button that acts as Enter / Esc in the game's
                menus, even if it is also a race control. MiSTer (default)
                uses the OK/Back buttons of your MiSTer menu.

Controls
  Keyboard: the original PC controls.
  Gamepad in a race (default mapping):
    D-pad / left stick                  Steer
    B (Xbox A / PlayStation Cross)      Accelerate
    Y (Xbox X / PlayStation Square)     Brake
    A (Xbox B / PlayStation Circle)     Handbrake
    X (Xbox Y / PlayStation Triangle)   Change View
    L (LB / L1)                         Repair
    R (RB / R1)                         Map
    Select                              Recover
    Start                               Pause (Esc)
  To accelerate and brake with the triggers (RT/LT), assign them in the OSD
  under "Define Dethrace buttons". MiSTer's default mapping can't use
  triggers.
  "Pratcam" (the driver's face in the corner, key P) has no button by
  default: give it one in "Define Dethrace buttons" to switch it on and off
  from the gamepad.
  "Menu OK" and "Menu Back" in "Define Dethrace buttons" are only needed for
  a button that has no race function. MiSTer doesn't let you assign a button
  twice there, so to use a race control as Enter/Esc in menus, pick that
  button in the OSD's Menu OK/Menu Back options instead.

Quitting from the game's main menu returns to the MiSTer menu.
Logs: /media/fat/logs/Dethrace/dethrace.log

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
