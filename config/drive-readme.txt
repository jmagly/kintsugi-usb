==============================================================================
  KINTSUGI USB  —  your AI-assisted rescue & recovery drive
==============================================================================

If you are reading this, you have opened the main storage area of a Kintsugi
USB drive. This file explains what the drive is and how to use it. You do not
need to be technical to follow it.


WHAT IS THIS DRIVE?
-------------------
A bootable USB that can start a computer even when its normal system will not.
It carries rescue tools and an offline AI assistant that can help diagnose and
repair problems — no internet required for the offline assistant.


WHAT YOU MIGHT SEE WHEN YOU PLUG IT IN
--------------------------------------
  KINTSUGI   - this storage area (where this README lives). Safe to browse.
  VTOYEFI    - a tiny ~34 MB area. This is the boot machinery. LEAVE IT ALONE.

  >> Do NOT reformat or "erase" the drive. That destroys the rescue system.


HOW TO BOOT FROM IT
-------------------
1. Leave the drive plugged in and restart the computer.
2. As it powers on, press the one-time boot-menu key for your machine:
       Dell / generic .... F12        HP ........... F9 or Esc
       Lenovo ............ F12 or Enter   ASUS ...... F8
       Acer .............. F12        Apple Mac .... hold the Option (⌥) key
   (If unsure, search "<your computer model> boot menu key".)
3. Choose the USB drive from the list.
4. At the Kintsugi (Ventoy) menu, choose the Kintsugi entry to start it.
5. If asked, choose "Try" / "Live" — NOT "Install".


YOUR CHANGES ARE SAVED (PERSISTENCE)
------------------------------------
This drive keeps your settings, downloaded AI models, and files across
restarts. You can pull models and set things up once and they will still be
there next time you boot it.


GETTING HELP
------------
Project & full guides:  https://git.integrolabs.net/roctinam/kintsugi-usb
Once booted, open a terminal and run:  start-ai.sh  (launches the AI assistant)

Keep this drive somewhere safe. It is most useful on the day something breaks.
==============================================================================
