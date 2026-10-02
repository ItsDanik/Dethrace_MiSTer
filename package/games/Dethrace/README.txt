Dethrace for MiSTer - Carmageddon as a hybrid core
===================================================

The game (dethrace, a reimplementation of Carmageddon) runs on the MiSTer's
ARM CPU; the Dethrace FPGA core provides native 15kHz video (CRT, VGA and
HDMI), audio and input.

Requirements
  - MiSTer Frontier (Master_Daemon.sh), which starts the game when the core
    is loaded.
  - Carmageddon game data. It is not included: use your original CD or the
    GOG release (Carmageddon Max Pack).

Install
  1. Copy _Other/Dethrace_*.rbf to /media/fat/_Other/
  2. Copy games/Dethrace/ to /media/fat/games/Dethrace/
  3. Copy the game's DATA folder to /media/fat/games/Dethrace/DATA
     (DATA/GENERAL.TXT must exist).
  4. Optional CD music (GOG): copy the MUSIC folder (Track02.ogg ...) to
     /media/fat/games/Dethrace/MUSIC

OSD options
  Stereo Mix, Scandoubler Fx, Aspect ratio as usual. The game runs in its
  original 320x200 mode.
  Sound Volume  master volume of sound effects and cutscene audio
  Music Volume  master volume of the CD music
                (both on top of the game's own volume settings)
  Renderer      Optimized: rewritten rasteriser and fog loops, same picture,
                about 1.6x faster. Original: the original rasteriser code.

Controls
  Keyboard: the original PC controls.
  Gamepad (map the buttons in the OSD):
    Menus   D-pad = cursor keys, Accelerate/Pause = Enter, Brake/Map = Esc
    Race    D-pad/stick = steer, Up/Accelerate = accelerate, Down/Brake =
            brake, Handbrake, Change View, Repair, Recover, Map, Pause (Esc)

Quitting from the game's main menu returns to the MiSTer menu.
Logs: /media/fat/logs/Dethrace/dethrace.log
