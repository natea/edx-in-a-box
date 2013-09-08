edx-in-a-box
============

edX-in-a-box is a one-click installer to quickly evaluate edX on your computer. It includes a couple sample courses so you can see examples for how to author your own courses.

Once you download the script and double-click on it, the script will do the following:

    * Download and Install Virtualbox (if not already installed)
    * Download and Install Vagrant (if not already installed)
    * Download the edX .box image file (if not already downloaded)
    * Import the edX .box image file into VirtualBox
    * Download and install the edx4edx_lite sample course
    * Download and install the 18.02SC Multivariable Calculus sample course
    * Start the newly installed/configured VM
    * Print a message of what to do next, and where to find more docs

Note: The script has the extension .tool which on MacOSX makes it clickable as an executable file. Linux users can rename this to edx-installer.sh and run it with bash::

	$ mv edx-installer.tool edx-installer.sh
	$ chmod +x edx-installer.sh
	$ ./edx-installer.sh