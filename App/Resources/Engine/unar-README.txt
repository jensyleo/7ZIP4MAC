lsar and unar (version 1.10.7, as packaged by Homebrew) are bundled, unmodified, from The Unarchiver's
command-line tools, built on the XADMaster library.

  Authors:  Dag Agren, MacPaw
  Source:   https://github.com/MacPaw/XADMaster
  License:  GNU Lesser General Public License, version 2.1 or later
            (full text in unar-LICENSE-LGPL-2.1.txt)

They are used only as a fallback for multi-part RAR sets that 7-Zip cannot
open (a 0-byte or missing volume). The corresponding source code is available
at the address above; the executables are separate programs launched by
7ZIP4MAC and are not linked into it.
