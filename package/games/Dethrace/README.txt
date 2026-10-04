Dethrace for MiSTer - Carmageddon as a hybrid core
===================================================

The game (dethrace, a reimplementation of Carmageddon) runs on the MiSTer's
ARM CPU; the Dethrace FPGA core provides native 15kHz video (CRT, VGA and
HDMI), audio and input.

Requirements
  - danik_hybrid_cores, the launcher that comes with this release
    (Scripts/danik_hybrid_cores.sh): copy it to /media/fat/Scripts/ and run
    it ONCE from the MiSTer's Scripts menu. It starts the game whenever
    the core is loaded, keeps running after a reboot, and serves all our
    hybrid cores. Without it the core only shows colour bars.
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
  Stereo Mix, Scandoubler Fx, Aspect ratio as usual. The game runs in its
  original 320x200 mode.
  Sound Volume  master volume of sound effects and cutscene audio
  Music Volume  master volume of the CD music
                (both on top of the game's own volume settings)
  Renderer      Optimized (default): rewritten rasteriser and fog loops,
                pixel for pixel the same picture as the original code.
                Fast: also simplifies the perspective texture mapping; the
                picture is nearly the same, the game runs 20-25% faster.
                Original: the original rasteriser code.
  Lock to 30 FPS
                shows every frame for exactly two video fields (29.8 fps)
                instead of a frame rate that floats between 30 and 60 fps.
                Steadier motion, best together with the Fast renderer.
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
  "Menu OK" and "Menu Back" in "Define Dethrace buttons" are only needed for
  a button that has no race function. MiSTer doesn't let you assign a button
  twice there, so to use a race control as Enter/Esc in menus, pick that
  button in the OSD's Menu OK/Menu Back options instead.

Quitting from the game's main menu returns to the MiSTer menu.
Logs: /media/fat/logs/Dethrace/dethrace.log
