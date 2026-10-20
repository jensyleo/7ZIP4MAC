lsar and unar (XADMaster 1.10.7) are bundled from The Unarchiver's command-line
tools, built on the XADMaster library. THESE ARE MODIFIED BUILDS, not the original
MacPaw binaries.

  Authors:  Dag Agren, MacPaw
  Source:   https://github.com/MacPaw/XADMaster  (tag v1.10.7)
            https://github.com/MacPaw/universal-detector  (tag 1.1)
  License:  GNU Lesser General Public License, version 2.1 or later
            (full text in unar-LICENSE-LGPL-2.1.txt)

Modification (2026-10-20, by Jensy Leonardo Martinez Cruz for 7ZIP4MAC):
  added the -password-stdin option, so a password can be given on standard input
  instead of the command line, where other users of the Mac could read it.
  The changes are in unar-password-stdin.patch and unar-build-libcxx.patch (next to
  this file); the full corresponding source and a build script are in the
  ThirdParty/unar folder of https://github.com/jensyleo/7ZIP4MAC, and the patched
  source tree is attached to each release as 7ZIP4MAC-unar-source.tar.gz.

They are used only as a fallback for multi-part RAR sets that 7-Zip cannot
open (a 0-byte or missing volume), and run as separate programs launched by
7ZIP4MAC; they are not linked into it. They are not made or endorsed by MacPaw.
