# edX-in-a-box installer
# edX + VirtualBox + Vagrant install script
# see here https://github.com/natea/edx-in-a-box/

# based on Ike Chuang's mitx-vagrant howto:
# http://people.csail.mit.edu/ichuang/edx/

### WARNING WARNING WARNING WARNING WARNING
#
# This script uses sudo (to install VirtualBox if needed)
# You should read through this script before running it.
#
###


if [ -z "$BASH" ]; then
    if [ ! -z "$-" ]; then
        opts="-$-"
    fi
    exec /usr/bin/env bash $opts "$0" "$@"
    echo "Error: this installer needs to be run by bash"
    echo "Unable to restart with bash shell"
    exit 1
fi

###
#
# Static variables:
#
###

VERSION=02sep13a
RELEASE_DATE=2013-09-08
DOWNLOAD_URL=https://people.csail.mit.edu/ichuang/edx/download.php?file=mitxvm-edx-platform-02sep13a.box

# Get OS type. Expect: linux or darwin or something else
OS=$OSTYPE
if [ -z "$OS" ]; then OS="unknown"; fi
# Remove version from darwin10.0
OS=${OS/[0-9]*/}
# Remove -gnu from linux-gnu
OS=${OS/-*/}

VIRTUALBOX_DMG_URL=http://download.virtualbox.org/virtualbox/4.2.12/VirtualBox-4.2.12-84980-OSX.dmg
VIRTUALBOX_DMG_FILE=${VIRTUALBOX_DMG_URL/*\//}

VAGRANT_DMG_URL=http://files.vagrantup.com/packages/7e400d00a3c5a0fdf2809c8b5001a035415a607b/Vagrant-1.2.2.dmg
VAGRANT_DMG_FILE=${VAGRANT_DMG_URL/*\//}

###
#
# Define all the steps to perform in separate functions, then call them at the
# bottom of the script.
#
###

welcome() {
    cat <<EOS

*** Welcome to the edX-in-a-box quick installer - version $VERSION - $RELEASE_DATE

EOS

    verify_os

    cat <<EOS

This script will automate the following things for you:

    * Download and Install Virtualbox (if not already installed)
    * Download and Install Vagrant (if not already installed)
    * Download the edX .box image file (if not already downloaded)
    * Import the edX .box image file into VirtualBox
    * Download and install the edx4edx_lite sample course
    * Download and install the 18.02SC Multivariable Calculus sample course
    * Start the newly installed/configured VM
    * Print a message of what to do next, and where to find more docs

You will be asked for your password if VirtualBox needs to be installed.

EOS

    prompt
}

verify_os() {
    x=`type which`; catch
    if [ $OS != 'linux' ] && [ $OS != 'darwin' ]; then
        die "Error: this installer currently only runs on Debian Linux or OS X"
    fi
    if [ $OS == 'linux' ]; then
        APTGET=`which apt-get`
        if [ -z $APTGET ]; then
            die "Error: this installer currently only runs on Debian-style for Linux"
        fi
    fi
}

verify_system() {
    need_cmd 'bash'
    need_cmd 'cat'
    need_cmd 'curl'
    need_cmd 'ifconfig'
    need_cmd 'perl'
    need_cmd 'rm'
    need_cmd 'sudo'
    need_cmd 'unzip'
    need_cmd 'which'
    need_cmd 'tar'

    if [ $OS == 'darwin' ]; then
        need_cmd 'grep'
        need_cmd 'hdiutil'
        need_cmd 'installer'
        need_cmd 'vm_stat'
        need_cmd 'wc'
    else
        need_cmd 'free'
    fi

    # Extract the active network device name from ifconfig
    NET_DEVICE=`ifconfig | perl -e '$t=do{local$/;<>};@m=split/^(\S+)(?::|\s\s+)/m,$t;shift(@m);%m=@m;for$k(sort keys%m){next if$k=~/^(lo|ppp|vmnet)/;next unless$m{$k}=~/inet (addr:)?\d/;print$k;last}'`
    if [ -z $NET_DEVICE ]; then
        die "Error: No network device seems to be active."
    fi

    # Get memory requirement and make sure host has it
    get_mem_size
    if [[ $MEM_REQUIRED_MB -gt $MEM_FREE_MB ]]; then
        cat <<EOS

*** WARNING WARNING WARNING

${MEM_REQUIRED_MB}MB free memory required, ${MEM_FREE_MB}MB available."

Starting edX in this state may cause your host to run out of memory
and become unresponsive. :-(

EOS
        prompt
    fi
}

set_edx_variables() {
#    export VERSION=`curl -I -s $DOWNLOAD_URL | perl -ne 'print if s!^Location: .*/edx/v([\d\.]+).*!$1!'`
    export EDX_BOX_FILE=mitxvm-edx-platform-$VERSION.box
    export EDX_BOX_URL=http://people.csail.mit.edu/ichuang/edx/download.php?file=$EDX_BOX_FILE

    export EDX4EDX_URL=https://github.com/mitocw/edx4edx_lite/archive/master.zip
    export EDX4EDX_ZIP_FILE=${EDX4EDX_URL/*\//}
    
    # see http://ocw.mit.edu/ocw-labs/opencourseware-bundles-for-edx/
    export EDX_BUNDLE_URL=http://ocw.mit.edu/ans7870/18/18.02SC/edx-bundle/18.02SC.tar.gz
    export EDX_BUNDLE_TARBALL=${EDX_BUNDLE_URL/*\//}
    
    export EDX_DIR=~/mitx-vagrant
    export DATA_DIR=${EDX_DIR}/data
}

check_for_other_hypervisors() {
    if [ $OS == "darwin" ]; then
        INSTALLED=`ls -l /Applications/ | grep -i vmware | wc -l`
        RUNNING=`ps -eaf | grep -i vmware | grep app | wc -l`
        if [ $RUNNING != '0' ]; then
            cat <<EOS

*** WARNING WARNING WARNING

You appear to be running a VMware hypervisor program. This script wants to run
VirtualBox. Running these two programs together has been known to cause a
system crash in some cases. You may wish to cancel this script and stop your
other VM software. Then you can run this script again.

EOS
            prompt
        elif [ $INSTALLED != '0' ]; then
            cat <<EOS

*** WARNING WARNING WARNING

You appear to have a VMware product installed (but not running).  Note that
this script is trying to start a VirtualBox VM. These two programs are known
to sometimes cause a system crash when run together. Be sure to not run
VMware, whilst running VirtualBox (unless you really know what you are doing).

EOS
            prompt
        fi
    fi
}

install_vbox() {
    VBOXMANAGE=`which VBoxManage`
    if [ -z $VBOXMANAGE ]; then
        sudo -k; catch
        echo
        case $OS in
            linux)
                echo "*** Installing VirtualBox from Debian package"
                if [ `apt-cache search virtualbox | grep -i '^virtualbox ' | wc -l` == '1' ]; then
                    PKG=virtualbox
                elif [ `apt-cache search virtualbox-ose | grep -i '^virtualbox-ose ' | wc -l` == '1' ]; then
                    PKG=virtualbox-ose
                else
                    echo "Can't find a virtualbox debian package."
                    die "Try installing VirtualBox yourself and then run this again."
                fi
                echo "sudo apt-get install -y $PKG"
                sudo apt-get install -y $PKG; catch
                ;;
            darwin)
                echo "*** Installing VirtualBox from virtualbox.org"
                echo "curl -L $VIRTUALBOX_DMG_URL > $VIRTUALBOX_DMG_FILE"
                curl -L $VIRTUALBOX_DMG_URL > $VIRTUALBOX_DMG_FILE; catch
                echo "hdiutil mount $VIRTUALBOX_DMG_FILE"
                hdiutil mount $VIRTUALBOX_DMG_FILE; catch
                echo 'sudo installer -pkg /Volumes/VirtualBox/VirtualBox.mpkg -target /'
                sudo installer -pkg /Volumes/VirtualBox/VirtualBox.mpkg -target /; catch
                echo "hdiutil unmount /Volumes/VirtualBox"
                hdiutil unmount /Volumes/VirtualBox; catch
                ;;
        esac

        VBOXMANAGE=`which VBoxManage`
    fi
}

install_vagrant() {
    VAGRANT=`which vagrant`
    if [ -z $VAGRANT ]; then
        sudo -k; catch
        echo
        case $OS in
            linux)
                echo "*** Installing Vagrant from Debian package"
                if [ `apt-cache search vagrant | grep -i '^vagrant ' | wc -l` == '1' ]; then
                    PKG=vagrant
                else
                    echo "Can't find a vagrant debian package."
                    die "Try installing Vagrant yourself and then run this again."
                fi
                echo "sudo apt-get install -y $PKG"
                sudo apt-get install -y $PKG; catch
                ;;
            darwin)
                echo "*** Installing Vagrant from vagrantup.com"
                echo "curl -L $VAGRANT_DMG_URL > $VAGRANT_DMG_FILE"
                curl -L $VAGRANT_DMG_URL > $VAGRANT_DMG_FILE; catch
                echo "hdiutil mount $VAGRANT_DMG_FILE"
                hdiutil mount $VAGRANT_DMG_FILE; catch
                echo 'sudo installer -pkg /Volumes/Vagrant/Vagrant.pkg -target /'
                sudo installer -pkg /Volumes/Vagrant/Vagrant.pkg -target /; catch
                echo "hdiutil unmount /Volumes/Vagrant"
                hdiutil unmount /Volumes/Vagrant; catch
                ;;
        esac

        VAGRANT=`which vagrant`
    fi
}

make_edx_dir() {
    if [ ! -d $EDX_DIR ]; then
        echo
        echo "*** Making edX dir"
        mkdir $EDX_DIR; catch
        cd $EDX_DIR; catch
    fi
}

download_edx() {
    if [ ! -f $EDX_DIR/$EDX_BOX_FILE ]; then
        echo
        echo "*** Downloading edX for VirtualBox .box file"
        echo "curl -L $EDX_BOX_URL > $EDX_BOX_FILE"
        echo "This make take awhile (4GB), so you might"
        echo "want to go grab a coffee."
        # TODO: resume broken downloads with
        # curl -C - -o file http://www.server.com/
        cd $EDX_DIR; catch
        curl -L $EDX_BOX_URL > $EDX_BOX_FILE; catch
    fi
}

make_data_dir() {
    if [ ! -d $DATA_DIR ]; then
        echo
        echo "*** Making data dir"
        mkdir $DATA_DIR; catch
    fi
}

download_edx4edx() {
    if [ ! -f $DATA_DIR/$EDX4EDX_ZIP_FILE ]; then
        echo
        echo "*** Downloading edx4edx_lite file"
        echo "curl -L $EDX4EDX_URL > $EDX4EDX_ZIP_FILE"
        cd $DATA_DIR
        curl -L $EDX4EDX_URL > $EDX4EDX_ZIP_FILE; catch
    fi
}

unzip_edx4edx() {
    if [ ! -d $DATA_DIR/edx4edx_lite ]; then
        echo
        echo "*** Unzipping edx4edx_lite zip file"
        echo "unzip $EDX4EDX_ZIP_FILE"
        cd $DATA_DIR
        unzip $EDX4EDX_ZIP_FILE; catch
        mv edx4edx_lite-master edx4edx_lite; catch
    fi
}

download_edx_bundle() {
    if [ ! -f $EDX_BUNDLE_TARBALL ]; then
        echo
        echo "*** Downloading edX bundle file"
        echo "curl -L $EDX_BUNDLE_URL > $EDX_BUNDLE_TARBALL"
        cd $DATA_DIR; catch
        curl -L $EDX_BUNDLE_URL > $EDX_BUNDLE_TARBALL; catch
    fi
}

untar_edx_bundle() {
    if [ ! -d $DATA_DIR/18.02SC ]; then
        echo
        echo "*** Uncompressing edX bundle file"
        echo "tar xvfz $EDX_BUNDLE_TARBALL"
        cd $DATA_DIR; catch
        tar xvfz $EDX_BUNDLE_TARBALL; catch
    fi
}

vagrant_init() {
    if [ ! -z $VAGRANT ] && [ ! -f $EDX_DIR/Vagrantfile ]; then
        echo
        echo "*** Initializing Virtualbox image with Vagrant"
        echo "vagrant init mitxvm $EDX_VM_FILE"
        cd $EDX_DIR; catch
        vagrant init mitxvm $EDX_VM_FILE; catch
    fi
}
vagrant_start() {
    if [ ! -z $VAGRANT ]; then
        echo
        echo "*** Starting Virtualbox image with Vagrant"
        echo "vagrant up"
        cd $EDX_DIR; catch
        vagrant up; catch
    fi
}

success() {
    cd $EDX_DIR; catch
    cat <<EOS

Everything seems to have worked. You should now see 
a VirtualBox VM booting.

Watch the console screen and wait for the boot to finish. 
It may take several minutes. 

After the VM boots, browse to:

http://192.168.42.2 -- LMS
http://192.168.42.3 -- CMS (Studio)
http://192.168.42.4 -- Preview (Studio)
http://192.168.42.5 -- Edge (Studio)

There are two main workflows you can use to develop courseware:

LMS (+github)
    edit XML files of courses in the data directory, 
    then click on "Reload course from XML files" in 
    the Instructor Dashboard (under the Admin tab). 
    The course files may be stored in github, and a 
    webhook configured to make the LMS automatically 
    update upon checkins ("gitreload"). 
    See edX documentation of XML formats.

Studio
    Create course using the web-based interface, and 
    view on the Preview ("draft") and Edge ("live") sites. 
    Beware that the Studio system is really meant for 
    single-author work; it loses all history, and there 
    is no visibility for what changes are being 
    made by authors. But Studio is wysiwyg and 
    gives fast feedback, so it can be a good way to start.

You may login to the system using a pre-created user: 
(email "xadmin@mitxvm.local", password "xadmin"); 

If you create your own user, to activate the user 
use the "xmanage" command (see below).

The MITx virtual machine Vagrant box comes with a simple 
management tool, xmanage. To see what you can do with it, run:

    vagrant ssh -- xmanage help

from within the mitx-vagrant directory. Running this command 
will also tell you what initial users you can 
login to your edX instances with.

Enjoy!

PS For more help getting started, look here:

    http://people.csail.mit.edu/ichuang/edx/

EOS
}

###
#
# Helper functions
#
###

die() {
    echo $1
    exit 1
}

catch() {
    if [ $? -ne 0 ]; then
        die "Error: command failed"
    fi
}

need_cmd() {
    CMD=$1
    bin=`which $CMD`
    if [ -z $bin ]; then die "Error: '$CMD' command required"; fi
}

prompt() {
    # Open a file descriptor to terminal
    exec 5<> /dev/tty
    echo -n "Press <CTL>-c to exit or press <ENTER> to continue..."
    read <&5
    # Close the file descriptor
    exec 5>&-
}

# Check free mem on host and guess a number to use between 1-2GB
get_mem_size() {
    case $OS in
        linux)
            MEM_FREE_MB=`free -m | perl -0e '($t=<>)=~s/.*?buffers\/cache:\s+\S+\s+(\S+).*/$1/s;print$1'`
            ;;
        darwin)
            MEM_FREE_MB=`vm_stat | perl -0e '($t=<>)=~/(\d+)\s+bytes.*Pages free:\s+(\d+).*Pages active:\s+(\d+)/s or die; print($1*($2+$3)/1024)'`
            ;;
    esac
    MEM_FREE_MB=$((MEM_FREE_MB/10*8))
    if [[ $MEM_FREE_MB -gt 2048 ]]; then
        MEM_REQUIRED_MB=2048
    elif [[ $MEM_FREE_MB -lt 1024 ]]; then
        MEM_REQUIRED_MB=1024
    else
        MEM_REQUIRED_MB=$MEM_FREE_MB
    fi
}

###
#
# These are the calls to the high level functions performed by this script:
#
###

welcome
verify_os
verify_system
set_edx_variables
check_for_other_hypervisors
install_vbox
install_vagrant
make_edx_dir
download_edx
make_data_dir
download_edx4edx
unzip_edx4edx
download_edx_bundle
untar_edx_bundle
vagrant_init
vagrant_start
success
