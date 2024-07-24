SUMMARY = "A image just capable of allowing a device to boot."

FILESEXTRAPATHS_prepend := "${THISDIR}/files:"
IMAGE_LINGUAS = " "

LICENSE = "MIT"
IMAGE_INSTALL = " \
                 packagegroup-foundation-layer \
                 packagegroup-vendor-layer \
                 packagegroup-middleware-generic \
                 packagegroup-application-layer \
                 "
inherit core-image

inherit custom-rootfs-creation

IMAGE_ROOTFS_SIZE ?= "8192"
IMAGE_ROOTFS_EXTRA_SPACE_append = "${@bb.utils.contains("DISTRO_FEATURES", "systemd", " + 4096", "" ,d)}"

PACKAGE_TYPE ="VBN_ENTOS"

create_init_link() {
        ln -sf /sbin/init ${IMAGE_ROOTFS}/init
}

# All kirstone builds use qt515 and dunfell use qt512
yocto_suffix = "${@bb.utils.contains('DISTRO_FEATURES', 'kirkstone', 'kirkstone', 'dunfell', d)}"
qt_version = "${@bb.utils.contains('DISTRO_FEATURES', 'kirkstone', 'qt515', 'qt512', d)}"


ROOTFS_POSTPROCESS_COMMAND += "create_init_link; "

ROOTFS_POSTPROCESS_COMMAND += "wpeframework_binding_patch; "

wpeframework_binding_patch(){
    sed -i "s/127.0.0.1/0.0.0.0/g" ${IMAGE_ROOTFS}/etc/WPEFramework/config.json
}
